# shellcheck shell=bash
# lib/boot-mode-transition.sh -- converges boot artifacts while the caller
# holds lib/boot-mode.sh's one transition lock (R-BOOTMODE-3,4,9,10).

# Fixed production paths. Tests substitute these in a copied library tree.
BOOT_TRANSITION_KIDS_DIR=/etc/omarchy-kids/kids
BOOT_TRANSITION_SLOTS_FILE=/etc/omarchy-kids/luks-slots
BOOT_TRANSITION_TEMPLATE=/usr/share/omarchy-kids/boot/omarchy_kids.conf
BOOT_TRANSITION_DROPIN=/etc/mkinitcpio.conf.d/omarchy_kids.conf
BOOT_TRANSITION_UKI_DIR=/boot/EFI/Linux
BOOT_TRANSITION_FINDMNT=/usr/bin/findmnt
BOOT_TRANSITION_LSBLK=/usr/bin/lsblk
BOOT_TRANSITION_CRYPTSETUP=/usr/bin/cryptsetup
BOOT_TRANSITION_LSINITCPIO=/usr/bin/lsinitcpio
BOOT_TRANSITION_LIMINE_CONF=/boot/limine.conf
BOOT_TRANSITION_LIMINE_DEFAULT=/etc/default/limine
BOOT_TRANSITION_LIMINE_SYNC=/usr/bin/limine-snapper-sync
BOOT_TRANSITION_LIMINE_MARKER='# omarchy-kids: was MAX_SNAPSHOT_ENTRIES='
BOOT_TRANSITION_LIMINE_SYNCED_MARKER='# omarchy-kids: snapshot sync complete'
BOOT_TRANSITION_LIMINE_EDITOR_MARKER='# omarchy-kids: was editor_enabled='
BOOT_TRANSITION_MKINITCPIO_CONF=/etc/mkinitcpio.conf
BOOT_TRANSITION_MKINITCPIO_CONF_DIR=/etc/mkinitcpio.conf.d
BOOT_TRANSITION_ENV=/usr/bin/env
BOOT_TRANSITION_BASH=/bin/bash
BOOT_TRANSITION_RECOVERY=/etc/omarchy-kids/boot-transition.recovery

BOOT_TRANSITION_PASSWORD_KIDS=()
BOOT_TRANSITION_MAP_ENTRIES=()
BOOT_TRANSITION_MISSING_KIDS=()
BOOT_TRANSITION_MISSING_SLOTS=()
BOOT_TRANSITION_SECRETS=()
BOOT_TRANSITION_RECOVERY_MAP=""
BOOT_TRANSITION_RECOVERY_BEFORE=()
BOOT_TRANSITION_RECOVERY_ADDITIONS=()
BOOT_TRANSITION_PARENT=""
BOOT_TRANSITION_DEVICE=""

boot_transition_root_luks_device() {
  local source tree path fstype
  source="$("$BOOT_TRANSITION_FINDMNT" -nro SOURCE --target / 2>/dev/null)" || return 1
  source="${source%%\[*}"
  [[ "$source" == /dev/* ]] || return 1
  tree="$("$BOOT_TRANSITION_LSBLK" -srno PATH,FSTYPE "$source" 2>/dev/null)" || return 1
  while read -r path fstype; do
    [[ "$fstype" == crypto_LUKS && "$path" == /dev/* ]] || continue
    printf '%s\n' "$path"
    return 0
  done <<<"$tree"
  return 1
}

boot_transition_occupied_slots() {
  "$BOOT_TRANSITION_CRYPTSETUP" luksDump "$1" 2>/dev/null | sed -n \
    -e 's/^[[:space:]]*\([0-9][0-9]*\):[[:space:]]*luks2[[:space:]]*$/\1/p' \
    -e 's/^Key Slot \([0-9][0-9]*\): ENABLED[[:space:]]*$/\1/p' |
    sort -n -u
}

boot_transition_config_safe() {
  local path="$1" kind="$2" mode
  [[ ! -L "$path" ]] || return 1
  if [[ "$kind" == dir ]]; then [[ -d "$path" ]]; else [[ -f "$path" ]]; fi || return 1
  [[ "$(file_stat u "$path")" == 0 && "$(file_stat G "$path")" == root ]] || return 1
  mode="$(file_stat a "$path")"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  ((8#$mode & 022)) && return 1
  return 0
}

boot_transition_hook_shape_supported() {
  local configs=() file
  if [[ -e "$BOOT_TRANSITION_MKINITCPIO_CONF" || -L "$BOOT_TRANSITION_MKINITCPIO_CONF" ]]; then
    boot_transition_config_safe "$BOOT_TRANSITION_MKINITCPIO_CONF" file || return 1
    configs+=("$BOOT_TRANSITION_MKINITCPIO_CONF")
  fi
  boot_transition_config_safe "$BOOT_TRANSITION_MKINITCPIO_CONF_DIR" dir || return 1
  shopt -s nullglob
  for file in "$BOOT_TRANSITION_MKINITCPIO_CONF_DIR"/*.conf; do
    boot_transition_config_safe "$file" file || {
      shopt -u nullglob
      return 1
    }
    configs+=("$file")
  done
  shopt -u nullglob
  ((${#configs[@]})) || return 1

  "$BOOT_TRANSITION_ENV" -i PATH=/usr/bin:/bin "$BOOT_TRANSITION_BASH" \
    --noprofile --norc -s -- "${configs[@]}" <<'EOF'
set -uo pipefail
for config in "$@"; do
  source "$config"
done
has_encrypt=0
for hook in "${HOOKS[@]-}"; do
  [[ "$hook" == encrypt ]] && has_encrypt=1
  [[ "$hook" == sd-encrypt ]] && exit 1
done
((has_encrypt))
EOF
}

boot_transition_collect_kids() {
  local file account password LC_ALL=C
  BOOT_TRANSITION_PASSWORD_KIDS=()
  BOOT_TRANSITION_PARENT="$(conf_get "$BOOT_MODE_MACHINE_CONF" parent 2>/dev/null || true)"
  [[ "$BOOT_TRANSITION_PARENT" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  [[ -e "$BOOT_TRANSITION_KIDS_DIR" || -L "$BOOT_TRANSITION_KIDS_DIR" ]] || return 0
  boot_transition_config_safe "$BOOT_TRANSITION_KIDS_DIR" dir || return 1
  for file in "$BOOT_TRANSITION_KIDS_DIR"/*.conf; do
    [[ -e "$file" ]] || continue
    boot_transition_config_safe "$file" file || return 1
    account="$(basename "$file" .conf)"
    [[ "$account" =~ ^kid-[a-z0-9-]{1,28}$ ]] || return 1
    password="$(conf_get "$file" password 2>/dev/null || true)"
    [[ -n "$password" ]] || password="set"
    [[ "$password" == set || "$password" == none ]] || return 1
    [[ "$password" == none ]] || BOOT_TRANSITION_PASSWORD_KIDS+=("$account")
  done
}

boot_transition_is_password_kid() {
  is_in "$1" "${BOOT_TRANSITION_PASSWORD_KIDS[@]+"${BOOT_TRANSITION_PASSWORD_KIDS[@]}"}"
}

boot_transition_load_disk_map() {
  local file="$BOOT_TRANSITION_SLOTS_FILE" line slot account session
  local active seen_slots=" " seen_accounts=" " kid mapped kept=()
  BOOT_TRANSITION_MAP_ENTRIES=()
  BOOT_TRANSITION_MISSING_KIDS=()
  if [[ -e "$file" || -L "$file" ]]; then
    [[ -f "$file" && ! -L "$file" ]] || return 1
    [[ "$(file_stat a "$file")" == 600 ]] || return 1
    [[ "$(file_stat u "$file")" == 0 && "$(file_stat G "$file")" == root ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in '' | '#'*) continue ;; esac
      [[ "$line" =~ ^(0|[1-9][0-9]*)=([a-z_][a-z0-9_-]{0,31})(:([A-Za-z0-9._-]+))?$ ]] || return 1
      slot="${BASH_REMATCH[1]}"
      account="${BASH_REMATCH[2]}"
      session="${BASH_REMATCH[4]:-}"
      ((slot <= 31)) || return 1
      [[ "$seen_slots" != *" $slot "* && "$seen_accounts" != *" $account "* ]] || return 1
      seen_slots+="$slot "
      seen_accounts+="$account "
      if [[ "$slot" == 0 ]]; then
        [[ "$account" == "$BOOT_TRANSITION_PARENT" ]] || return 1
        continue
      fi
      boot_transition_is_password_kid "$account" || return 1
      [[ -z "$session" || "$session" == omarchy-kids.desktop ]] || return 1
      BOOT_TRANSITION_MAP_ENTRIES+=("$slot=$account")
    done <"$file"
  fi

  active="$(boot_transition_occupied_slots "$BOOT_TRANSITION_DEVICE")" || return 1
  grep -qxF 0 <<<"$active" || return 1
  for line in "${BOOT_TRANSITION_MAP_ENTRIES[@]+"${BOOT_TRANSITION_MAP_ENTRIES[@]}"}"; do
    slot="${line%%=*}"
    grep -qxF "$slot" <<<"$active" && kept+=("$line")
  done
  BOOT_TRANSITION_MAP_ENTRIES=("${kept[@]+"${kept[@]}"}")
  for kid in "${BOOT_TRANSITION_PASSWORD_KIDS[@]+"${BOOT_TRANSITION_PASSWORD_KIDS[@]}"}"; do
    mapped=""
    for line in "${BOOT_TRANSITION_MAP_ENTRIES[@]+"${BOOT_TRANSITION_MAP_ENTRIES[@]}"}"; do
      [[ "${line#*=}" == "$kid" ]] || continue
      slot="${line%%=*}"
      if grep -qxF "$slot" <<<"$active"; then mapped="$slot"; else line=""; fi
      break
    done
    [[ -n "$mapped" ]] || BOOT_TRANSITION_MISSING_KIDS+=("$kid")
  done
}

boot_transition_slot_for_kid() {
  local line
  for line in "${BOOT_TRANSITION_MAP_ENTRIES[@]+"${BOOT_TRANSITION_MAP_ENTRIES[@]}"}"; do
    [[ "${line#*=}" == "$1" ]] || continue
    printf '%s\n' "${line%%=*}"
    return 0
  done
  return 1
}

boot_transition_read_secrets() {
  local from_stdin="$1" secret extra kid
  BOOT_TRANSITION_SECRETS=()
  if [[ "$from_stdin" == 1 ]]; then
    for kid in parent "${BOOT_TRANSITION_PASSWORD_KIDS[@]+"${BOOT_TRANSITION_PASSWORD_KIDS[@]}"}"; do
      secret=""
      IFS= read -r secret || [[ -n "$secret" ]] || return 1
      [[ -n "$secret" ]] || return 1
      BOOT_TRANSITION_SECRETS+=("$secret")
    done
    extra=""
    if IFS= read -r extra || [[ -n "$extra" ]]; then return 1; fi
    return 0
  fi

  [[ -t 0 ]] || return 1
  IFS= read -r -s -p 'Current disk passphrase: ' secret </dev/tty || return 130
  printf '\n' >/dev/tty
  [[ -n "$secret" ]] || return 1
  BOOT_TRANSITION_SECRETS+=("$secret")
  for kid in "${BOOT_TRANSITION_PASSWORD_KIDS[@]+"${BOOT_TRANSITION_PASSWORD_KIDS[@]}"}"; do
    IFS= read -r -s -p "Current password for $kid: " secret </dev/tty || return 130
    printf '\n' >/dev/tty
    [[ -n "$secret" ]] || return 1
    BOOT_TRANSITION_SECRETS+=("$secret")
  done
}

boot_transition_secret_opens() {
  local secret="$1" device="$2" slot="${3:-}"
  if [[ -n "$slot" ]]; then
    "$BOOT_TRANSITION_CRYPTSETUP" open --test-passphrase --key-file=/dev/fd/3 \
      --key-slot "$slot" "$device" 3< <(printf '%s' "$secret") >/dev/null 2>&1
  else
    "$BOOT_TRANSITION_CRYPTSETUP" open --test-passphrase --key-file=/dev/fd/3 \
      "$device" 3< <(printf '%s' "$secret") >/dev/null 2>&1
  fi
}

boot_transition_validate_secrets() {
  local index=1 kid slot prior_index
  boot_transition_secret_opens "${BOOT_TRANSITION_SECRETS[0]}" "$BOOT_TRANSITION_DEVICE" || return 1
  for kid in "${BOOT_TRANSITION_PASSWORD_KIDS[@]+"${BOOT_TRANSITION_PASSWORD_KIDS[@]}"}"; do
    for ((prior_index = 1; prior_index < index; prior_index++)); do
      if [[ "${BOOT_TRANSITION_SECRETS[$index]}" == "${BOOT_TRANSITION_SECRETS[$prior_index]}" ]]; then
        echo "omarchy-kids-conf: password for $kid is already in use by another child" >&2
        return 1
      fi
    done
    slot="$(boot_transition_slot_for_kid "$kid" 2>/dev/null || true)"
    if [[ -n "$slot" ]]; then
      boot_transition_secret_opens "${BOOT_TRANSITION_SECRETS[$index]}" "$BOOT_TRANSITION_DEVICE" "$slot" || return 1
    elif boot_transition_secret_opens "${BOOT_TRANSITION_SECRETS[$index]}" "$BOOT_TRANSITION_DEVICE"; then
      echo "omarchy-kids-conf: password for $kid already unlocks an existing disk slot" >&2
      return 1
    fi
    index=$((index + 1))
  done
}

boot_transition_fsync() {
  "$KIDS_PY" -c 'import os, sys
p = sys.argv[1]
for target in (p, os.path.dirname(p)):
    fd = os.open(target, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)' "$1"
}

boot_transition_fsync_dir() {
  "$KIDS_PY" -c 'import os, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
try:
    os.fsync(fd)
finally:
    os.close(fd)' "$1"
}

boot_transition_secret_for_kid() {
  local index=1 kid
  for kid in "${BOOT_TRANSITION_PASSWORD_KIDS[@]+"${BOOT_TRANSITION_PASSWORD_KIDS[@]}"}"; do
    if [[ "$kid" == "$1" ]]; then
      printf '%s' "${BOOT_TRANSITION_SECRETS[$index]}"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}

boot_transition_allocate_slots() {
  local active slot kid found
  active="$(boot_transition_occupied_slots "$BOOT_TRANSITION_DEVICE")" || return 1
  BOOT_TRANSITION_MISSING_SLOTS=()
  for kid in "${BOOT_TRANSITION_MISSING_KIDS[@]+"${BOOT_TRANSITION_MISSING_KIDS[@]}"}"; do
    found=""
    for slot in {1..31}; do
      grep -qxF "$slot" <<<"$active" && continue
      found="$slot"
      active+=$'\n'"$slot"
      break
    done
    [[ -n "$found" ]] || return 1
    BOOT_TRANSITION_MISSING_SLOTS+=("$found=$kid")
  done
}

boot_transition_write_state_file() {
  local file="$1" mode="$2" tmp line
  shift 2
  tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")" || return 1
  if (($#)); then
    printf '%s\n' "$@" >"$tmp" || {
      rm -f "$tmp"
      return 1
    }
  else
    : >"$tmp" || {
      rm -f "$tmp"
      return 1
    }
  fi
  if ! chmod "$mode" "$tmp" || ! chown root:root "$tmp" ||
    ! boot_transition_fsync "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  boot_transition_fsync_dir "$(dirname "$file")"
}

boot_transition_prepare_additions() {
  local current="$1" line record=("version=1")
  [[ "$current" == portal || ${#BOOT_TRANSITION_MISSING_SLOTS[@]} -gt 0 ]] || return 0
  [[ ! -e "$BOOT_TRANSITION_RECOVERY" && ! -L "$BOOT_TRANSITION_RECOVERY" ]] || return 1
  if [[ -f "$BOOT_TRANSITION_SLOTS_FILE" && ! -L "$BOOT_TRANSITION_SLOTS_FILE" ]]; then
    record+=("map=present")
    while IFS= read -r line || [[ -n "$line" ]]; do
      case "$line" in '' | '#'*) continue ;; esac
      record+=("before=$line")
    done <"$BOOT_TRANSITION_SLOTS_FILE"
  else
    record+=("map=absent")
  fi
  for line in "${BOOT_TRANSITION_MISSING_SLOTS[@]+"${BOOT_TRANSITION_MISSING_SLOTS[@]}"}"; do
    record+=("add=$line")
  done
  boot_transition_write_state_file "$BOOT_TRANSITION_RECOVERY" 0600 "${record[@]}"
}

boot_transition_parse_recovery() {
  local line value line_number=0 map_count=0 before_slots=" " before_accounts=" "
  local add_slots=" " add_accounts=" " slot account
  BOOT_TRANSITION_RECOVERY_MAP=""
  BOOT_TRANSITION_RECOVERY_BEFORE=()
  BOOT_TRANSITION_RECOVERY_ADDITIONS=()
  boot_transition_config_safe "$BOOT_TRANSITION_RECOVERY" file || return 1
  [[ "$(file_stat a "$BOOT_TRANSITION_RECOVERY")" == 600 ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    if [[ "$line_number" -eq 1 ]]; then
      [[ "$line" == version=1 ]] || return 1
      continue
    fi
    case "$line" in
      map=present | map=absent)
        map_count=$((map_count + 1))
        [[ "$map_count" -eq 1 ]] || return 1
        BOOT_TRANSITION_RECOVERY_MAP="${line#map=}"
        ;;
      before=*)
        [[ "$map_count" -eq 1 ]] || return 1
        value="${line#before=}"
        [[ "$value" =~ ^(0|[1-9][0-9]*)=([a-z_][a-z0-9_-]{0,31})(:([A-Za-z0-9._-]+))?$ ]] || return 1
        slot="${BASH_REMATCH[1]}"
        account="${BASH_REMATCH[2]}"
        ((slot <= 31)) || return 1
        [[ "$before_slots" != *" $slot "* && "$before_accounts" != *" $account "* ]] || return 1
        [[ "$add_slots" != *" $slot "* ]] || return 1
        before_slots+="$slot "
        before_accounts+="$account "
        BOOT_TRANSITION_RECOVERY_BEFORE+=("$value")
        ;;
      add=*)
        [[ "$map_count" -eq 1 ]] || return 1
        value="${line#add=}"
        [[ "$value" =~ ^([1-9][0-9]*)=(kid-[a-z0-9-]{1,28})$ ]] || return 1
        slot="${BASH_REMATCH[1]}"
        account="${BASH_REMATCH[2]}"
        ((slot <= 31)) || return 1
        [[ "$add_slots" != *" $slot "* && "$add_accounts" != *" $account "* ]] || return 1
        [[ "$before_slots" != *" $slot "* ]] || return 1
        add_slots+="$slot "
        add_accounts+="$account "
        BOOT_TRANSITION_RECOVERY_ADDITIONS+=("$value")
        ;;
      *) return 1 ;;
    esac
  done <"$BOOT_TRANSITION_RECOVERY"
  [[ "$line_number" -ge 2 && "$map_count" -eq 1 ]] || return 1
  [[ "$BOOT_TRANSITION_RECOVERY_MAP" == present || ${#BOOT_TRANSITION_RECOVERY_BEFORE[@]} -eq 0 ]]
}

boot_transition_remove_recovery() {
  rm -f "$BOOT_TRANSITION_RECOVERY" || return 1
  boot_transition_fsync_dir "$(dirname "$BOOT_TRANSITION_RECOVERY")"
}

boot_transition_rollback_additions() {
  local line slot active failed=0
  boot_transition_parse_recovery || return 1
  active="$(boot_transition_occupied_slots "$BOOT_TRANSITION_DEVICE")" || return 1
  for line in "${BOOT_TRANSITION_RECOVERY_ADDITIONS[@]+"${BOOT_TRANSITION_RECOVERY_ADDITIONS[@]}"}"; do
    slot="${line%%=*}"
    grep -qxF "$slot" <<<"$active" || continue
    "$BOOT_TRANSITION_CRYPTSETUP" luksKillSlot --batch-mode \
      "$BOOT_TRANSITION_DEVICE" "$slot" || failed=1
  done
  ((failed == 0)) || return 1

  if [[ "$BOOT_TRANSITION_RECOVERY_MAP" == present ]]; then
    boot_transition_write_state_file "$BOOT_TRANSITION_SLOTS_FILE" 0600 \
      "${BOOT_TRANSITION_RECOVERY_BEFORE[@]+"${BOOT_TRANSITION_RECOVERY_BEFORE[@]}"}" || return 1
  else
    rm -f "$BOOT_TRANSITION_SLOTS_FILE" || return 1
    boot_transition_fsync_dir "$(dirname "$BOOT_TRANSITION_SLOTS_FILE")" || return 1
  fi
  boot_transition_remove_recovery
}

boot_transition_recover_additions() {
  local requested="$1" line slot active committed=0
  if [[ ! -e "$BOOT_TRANSITION_RECOVERY" && ! -L "$BOOT_TRANSITION_RECOVERY" ]]; then
    return 0
  fi
  boot_transition_parse_recovery || return 1
  if [[ "$requested" == disk ]] &&
    boot_transition_config_safe "$BOOT_TRANSITION_SLOTS_FILE" file &&
    [[ "$(file_stat a "$BOOT_TRANSITION_SLOTS_FILE")" == 600 ]]; then
    active="$(boot_transition_occupied_slots "$BOOT_TRANSITION_DEVICE")" || return 1
    committed=1
    for line in "${BOOT_TRANSITION_RECOVERY_ADDITIONS[@]+"${BOOT_TRANSITION_RECOVERY_ADDITIONS[@]}"}"; do
      slot="${line%%=*}"
      if ! grep -qxF "$line" "$BOOT_TRANSITION_SLOTS_FILE" ||
        ! grep -qxF "$slot" <<<"$active"; then
        committed=0
        break
      fi
    done
    if [[ "$committed" == 1 ]]; then
      boot_transition_remove_recovery
      return $?
    fi
  fi
  boot_transition_rollback_additions
}

boot_transition_add_slots() {
  local line slot kid secret
  for line in "${BOOT_TRANSITION_MISSING_SLOTS[@]+"${BOOT_TRANSITION_MISSING_SLOTS[@]}"}"; do
    slot="${line%%=*}"
    kid="${line#*=}"
    secret="$(boot_transition_secret_for_kid "$kid")" || return 1
    "$BOOT_TRANSITION_CRYPTSETUP" luksAddKey --batch-mode \
      --key-file=/dev/fd/3 --key-slot "$slot" "$BOOT_TRANSITION_DEVICE" /dev/fd/4 \
      3< <(printf '%s' "${BOOT_TRANSITION_SECRETS[0]}") \
      4< <(printf '%s' "$secret") || return 1
    boot_transition_secret_opens "$secret" "$BOOT_TRANSITION_DEVICE" "$slot" || return 1
  done
}

boot_transition_write_disk_map() {
  local entries=("${BOOT_TRANSITION_MAP_ENTRIES[@]+"${BOOT_TRANSITION_MAP_ENTRIES[@]}"}") desired
  entries+=("${BOOT_TRANSITION_MISSING_SLOTS[@]+"${BOOT_TRANSITION_MISSING_SLOTS[@]}"}")
  desired="$(
    printf '0=%s\n' "$BOOT_TRANSITION_PARENT"
    ((${#entries[@]})) && printf '%s\n' "${entries[@]}"
  )"
  if [[ -f "$BOOT_TRANSITION_SLOTS_FILE" && ! -L "$BOOT_TRANSITION_SLOTS_FILE" ]] &&
    [[ "$(cat "$BOOT_TRANSITION_SLOTS_FILE")" == "$desired" ]]; then
    return 0
  fi
  boot_transition_write_state_file "$BOOT_TRANSITION_SLOTS_FILE" 0600 \
    "0=$BOOT_TRANSITION_PARENT" "${entries[@]+"${entries[@]}"}"
}

boot_transition_install_dropin() {
  local tmp
  boot_transition_config_safe "$BOOT_TRANSITION_TEMPLATE" file || return 2
  boot_transition_config_safe "$(dirname "$BOOT_TRANSITION_DROPIN")" dir || return 2
  cmp -s "$BOOT_TRANSITION_TEMPLATE" "$BOOT_TRANSITION_DROPIN" && return 1
  tmp="$(mktemp "$(dirname "$BOOT_TRANSITION_DROPIN")/.omarchy_kids.conf.XXXXXX")" || return 2
  if ! cp "$BOOT_TRANSITION_TEMPLATE" "$tmp" || ! chmod 0644 "$tmp" ||
    ! chown root:root "$tmp" || ! mv -f "$tmp" "$BOOT_TRANSITION_DROPIN"; then
    rm -f "$tmp"
    return 2
  fi
  boot_transition_fsync "$BOOT_TRANSITION_DROPIN" || return 2
  return 0
}

boot_transition_limine_editor() {
  local file="$BOOT_TRANSITION_LIMINE_CONF" marker old line tmp mode owner group
  [[ -e "$file" || -L "$file" ]] || return 0
  boot_transition_config_safe "$file" file || return 1
  marker="$(grep -F "$BOOT_TRANSITION_LIMINE_EDITOR_MARKER" "$file" 2>/dev/null | tail -n1 || true)"
  if [[ -n "$marker" ]]; then
    old="${marker#"$BOOT_TRANSITION_LIMINE_EDITOR_MARKER"}"
    [[ -z "$old" || "$old" == yes || "$old" == no ]] || return 1
  else
    grep -qE '^editor_enabled:[[:space:]]*no[[:space:]]*$' "$file" && return 0
    line="$(grep -E '^editor_enabled:' "$file" | tail -n1 || true)"
    if [[ -n "$line" ]]; then
      [[ "$line" =~ ^editor_enabled:[[:space:]]*(yes|no)[[:space:]]*$ ]] || return 1
      old="${BASH_REMATCH[1]}"
    fi
  fi
  mode="$(file_stat a "$file")"
  owner="$(file_stat u "$file")"
  group="$(file_stat G "$file")"
  tmp="$(mktemp "$(dirname "$file")/.limine.conf.XXXXXX")" || return 1
  {
    printf 'editor_enabled: no\n'
    grep -vE "^editor_enabled:|^${BOOT_TRANSITION_LIMINE_EDITOR_MARKER}" "$file" || true
    printf '%s%s\n' "$BOOT_TRANSITION_LIMINE_EDITOR_MARKER" "$old"
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! chmod "$mode" "$tmp" || ! chown "$owner:$group" "$tmp" ||
    ! boot_transition_fsync "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  boot_transition_fsync_dir "$(dirname "$file")"
}

boot_transition_limine_snapshots() {
  local file="$BOOT_TRANSITION_LIMINE_DEFAULT" old marker tmp mode owner group
  local marker_count synced_count
  [[ -e "$file" || -L "$file" ]] || return 0
  boot_transition_config_safe "$file" file || return 1
  marker_count="$(grep -cF "$BOOT_TRANSITION_LIMINE_MARKER" "$file" 2>/dev/null || true)"
  synced_count="$(grep -cxF "$BOOT_TRANSITION_LIMINE_SYNCED_MARKER" "$file" 2>/dev/null || true)"
  [[ "$marker_count" =~ ^[01]$ && "$synced_count" =~ ^[01]$ ]] || return 1
  ((synced_count == 0 || marker_count == 1)) || return 1
  marker="$(grep -F "$BOOT_TRANSITION_LIMINE_MARKER" "$file" 2>/dev/null | tail -n1 || true)"
  if [[ -n "$marker" ]]; then
    old="${marker#"$BOOT_TRANSITION_LIMINE_MARKER"}"
    [[ -z "$old" || "$old" =~ ^[0-9]+$ ]] || return 1
  else
    old="$(grep -E '^MAX_SNAPSHOT_ENTRIES=' "$file" | tail -n1 || true)"
    old="${old#MAX_SNAPSHOT_ENTRIES=}"
    [[ -z "$old" || "$old" =~ ^[0-9]+$ ]] || return 1
  fi
  if [[ -n "$marker" ]] && grep -qxF 'MAX_SNAPSHOT_ENTRIES=0' "$file" &&
    ((synced_count == 1)); then
    return 0
  fi
  mode="$(file_stat a "$file")"
  owner="$(file_stat u "$file")"
  group="$(file_stat G "$file")"
  tmp="$(mktemp "$(dirname "$file")/.limine.default.XXXXXX")" || return 1
  {
    grep -vF "$BOOT_TRANSITION_LIMINE_SYNCED_MARKER" "$file" |
      grep -vE "^MAX_SNAPSHOT_ENTRIES=|^${BOOT_TRANSITION_LIMINE_MARKER}" || true
    printf '%s%s\n' "$BOOT_TRANSITION_LIMINE_MARKER" "$old"
    printf 'MAX_SNAPSHOT_ENTRIES=0\n'
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! chmod "$mode" "$tmp" || ! chown "$owner:$group" "$tmp" ||
    ! boot_transition_fsync "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  boot_transition_fsync_dir "$(dirname "$file")" || return 1
  [[ ! -x "$BOOT_TRANSITION_LIMINE_SYNC" ]] || "$BOOT_TRANSITION_LIMINE_SYNC" || return 1

  tmp="$(mktemp "$(dirname "$file")/.limine.default.XXXXXX")" || return 1
  {
    grep -vxF "$BOOT_TRANSITION_LIMINE_SYNCED_MARKER" "$file" || true
    printf '%s\n' "$BOOT_TRANSITION_LIMINE_SYNCED_MARKER"
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! chmod "$mode" "$tmp" || ! chown "$owner:$group" "$tmp" ||
    ! boot_transition_fsync "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  boot_transition_fsync_dir "$(dirname "$file")"
}

boot_transition_disk_abort() {
  local current="$1" mode_written="${2:-0}" failed=0
  if [[ "$current" == portal && "$mode_written" == 1 ]]; then
    boot_mode_set portal || failed=1
  fi
  if [[ -e "$BOOT_TRANSITION_RECOVERY" || -L "$BOOT_TRANSITION_RECOVERY" ]]; then
    boot_transition_rollback_additions || failed=1
  fi
  if [[ "$current" == portal ]]; then
    rm -f "$BOOT_TRANSITION_DROPIN" || failed=1
    boot_transition_restore_limine_editor || failed=1
    boot_transition_restore_limine || failed=1
  fi
  ((failed == 0)) || echo "omarchy-kids-conf: disk transition rollback needs repair" >&2
  return 1
}

boot_transition_disk() {
  local current="$1" from_stdin="$2" need_secrets=0 dropin_status hook_status mode_written=0
  BOOT_TRANSITION_DEVICE="$(boot_transition_root_luks_device)" || return 1
  boot_transition_hook_shape_supported || return 1
  boot_transition_uki_has_hook && hook_status=0 || hook_status=$?
  if [[ "$hook_status" -eq 2 || "$hook_status" -eq 3 ]]; then
    echo "omarchy-kids-conf: refusing disk transition without an inspectable current UKI" >&2
    return 1
  fi
  boot_transition_collect_kids || return 1
  boot_transition_recover_additions disk || return 1
  boot_transition_load_disk_map || return 1

  [[ "$current" == portal || ${#BOOT_TRANSITION_MISSING_KIDS[@]} -gt 0 || "$from_stdin" == 1 ]] && need_secrets=1
  if [[ "$need_secrets" == 1 ]]; then
    boot_transition_read_secrets "$from_stdin" || return $?
    boot_transition_validate_secrets || return 1
  fi
  boot_transition_allocate_slots || return 1
  boot_transition_prepare_additions "$current" || return 1
  if ! boot_transition_add_slots; then
    boot_transition_disk_abort "$current"
    return 1
  fi
  if ! boot_transition_write_disk_map; then
    boot_transition_disk_abort "$current"
    return 1
  fi

  if boot_transition_install_dropin; then
    dropin_status=0
  else
    dropin_status=$?
  fi
  if [[ "$dropin_status" -eq 2 ]]; then
    boot_transition_disk_abort "$current"
    return 1
  fi
  if ! boot_transition_limine_editor || ! boot_transition_limine_snapshots; then
    boot_transition_disk_abort "$current"
    return 1
  fi
  boot_transition_uki_has_hook && hook_status=0 || hook_status=$?
  if [[ "$hook_status" -eq 1 ]]; then
    boot_transition_rebuild_needed
    return 1
  fi
  [[ "$hook_status" -eq 0 ]] || return 1
  if ! boot_mode_set disk; then
    mode_written="$BOOT_MODE_SET_COMMITTED"
    boot_transition_disk_abort "$current" "$mode_written"
    return 1
  fi
  mode_written="$BOOT_MODE_SET_COMMITTED"
  if [[ "$(boot_mode_get 2>/dev/null || true)" != disk ]]; then
    boot_transition_disk_abort "$current" "$mode_written"
    return 1
  fi
  if [[ -e "$BOOT_TRANSITION_RECOVERY" || -L "$BOOT_TRANSITION_RECOVERY" ]]; then
    boot_transition_remove_recovery || return 1
  fi
  return 0
}

boot_transition_remove_kid_slots() {
  local file="$BOOT_TRANSITION_SLOTS_FILE" line slot account session
  local device active seen_slots=" " seen_accounts=" " entries=()
  [[ -e "$file" || -L "$file" ]] || return 0
  [[ -f "$file" && ! -L "$file" ]] || return 1
  [[ "$(file_stat a "$file")" == 600 ]] || return 1
  [[ "$(file_stat u "$file")" == 0 && "$(file_stat G "$file")" == root ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in '' | '#'*) continue ;; esac
    [[ "$line" =~ ^(0|[1-9][0-9]*)=([a-z_][a-z0-9_-]{0,31})(:([A-Za-z0-9._-]+))?$ ]] || return 1
    slot="${BASH_REMATCH[1]}"
    account="${BASH_REMATCH[2]}"
    session="${BASH_REMATCH[4]:-}"
    ((slot <= 31)) || return 1
    [[ "$seen_slots" != *" $slot "* && "$seen_accounts" != *" $account "* ]] || return 1
    seen_slots+="$slot "
    seen_accounts+="$account "
    if [[ "$slot" == 0 ]]; then
      [[ "$account" != kid-* ]] || return 1
      continue
    fi
    [[ "$account" =~ ^kid-[a-z0-9-]{1,28}$ ]] || return 1
    [[ -z "$session" || "$session" == omarchy-kids.desktop ]] || return 1
    entries+=("$slot=$account")
  done <"$file"

  if ((${#entries[@]})); then
    device="$(boot_transition_root_luks_device)" || return 1
    active="$(boot_transition_occupied_slots "$device")" || return 1
    for line in "${entries[@]}"; do
      slot="${line%%=*}"
      grep -qxF "$slot" <<<"$active" || continue
      "$BOOT_TRANSITION_CRYPTSETUP" luksKillSlot --batch-mode "$device" "$slot" || return 1
    done
  fi
  rm -f "$file"
}

boot_transition_restore_limine() {
  local file="$BOOT_TRANSITION_LIMINE_DEFAULT" old tmp mode owner group
  [[ -e "$file" || -L "$file" ]] || return 0
  [[ -f "$file" && ! -L "$file" ]] || return 1
  old="$(grep -F "$BOOT_TRANSITION_LIMINE_MARKER" "$file" 2>/dev/null | tail -n1 || true)"
  [[ -n "$old" ]] || return 0
  old="${old#"$BOOT_TRANSITION_LIMINE_MARKER"}"
  [[ -z "$old" || "$old" =~ ^[0-9]+$ ]] || return 1
  mode="$(file_stat a "$file")"
  owner="$(file_stat u "$file")"
  group="$(file_stat G "$file")"
  [[ -n "$mode" && "$owner" == 0 && "$group" == root ]] || return 1
  tmp="$(mktemp "$(dirname "$file")/.limine.default.XXXXXX")" || return 1
  {
    grep -vF "$BOOT_TRANSITION_LIMINE_SYNCED_MARKER" "$file" |
      grep -vE "^MAX_SNAPSHOT_ENTRIES=|^${BOOT_TRANSITION_LIMINE_MARKER}" || true
    [[ -z "$old" ]] || printf 'MAX_SNAPSHOT_ENTRIES=%s\n' "$old"
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! chmod "$mode" "$tmp" || ! chown "$owner:$group" "$tmp" ||
    ! boot_transition_fsync "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  boot_transition_fsync_dir "$(dirname "$file")" || return 1
  [[ ! -x "$BOOT_TRANSITION_LIMINE_SYNC" ]] || "$BOOT_TRANSITION_LIMINE_SYNC"
}

boot_transition_restore_limine_editor() {
  local file="$BOOT_TRANSITION_LIMINE_CONF" marker old tmp mode owner group
  [[ -e "$file" || -L "$file" ]] || return 0
  boot_transition_config_safe "$file" file || return 1
  marker="$(grep -F "$BOOT_TRANSITION_LIMINE_EDITOR_MARKER" "$file" 2>/dev/null | tail -n1 || true)"
  [[ -n "$marker" ]] || return 0
  old="${marker#"$BOOT_TRANSITION_LIMINE_EDITOR_MARKER"}"
  [[ -z "$old" || "$old" == yes || "$old" == no ]] || return 1
  mode="$(file_stat a "$file")"
  owner="$(file_stat u "$file")"
  group="$(file_stat G "$file")"
  tmp="$(mktemp "$(dirname "$file")/.limine.conf.XXXXXX")" || return 1
  {
    grep -vE "^editor_enabled:|^${BOOT_TRANSITION_LIMINE_EDITOR_MARKER}" "$file" || true
    [[ -z "$old" ]] || printf 'editor_enabled: %s\n' "$old"
  } >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if ! chmod "$mode" "$tmp" || ! chown "$owner:$group" "$tmp" ||
    ! boot_transition_fsync "$tmp" || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
  boot_transition_fsync_dir "$(dirname "$file")"
}

boot_transition_current_uki() {
  local file LC_ALL=C
  for file in "$BOOT_TRANSITION_UKI_DIR"/*.efi; do
    [[ -f "$file" ]] || continue
    printf '%s\n' "$file"
    return 0
  done
  return 1
}

boot_transition_current_mode() {
  local mode
  if mode="$(boot_mode_get 2>/dev/null)"; then
    printf '%s\n' "$mode"
    return 0
  fi
  boot_mode_dir_safe "$(dirname "$BOOT_MODE_MACHINE_CONF")" || return 1
  if [[ -e "$BOOT_MODE_MACHINE_CONF" || -L "$BOOT_MODE_MACHINE_CONF" ]]; then
    boot_mode_file_safe "$BOOT_MODE_MACHINE_CONF" || return 1
    boot_mode_scan "$BOOT_MODE_MACHINE_CONF" 1 >/dev/null || return 1
  fi
  printf 'missing\n'
}

boot_transition_uki_has_hook() {
  local uki listing
  uki="$(boot_transition_current_uki)" || return 2
  listing="$("$BOOT_TRANSITION_LSINITCPIO" -a "$uki" 2>/dev/null)" || return 3
  grep -q 'omarchy-kids-unlock' <<<"$listing"
}

boot_transition_rebuild_needed() {
  echo "omarchy-kids-conf: run 'sudo mkinitcpio -P' to finish changing boot mode. A power loss while it runs can leave this computer unable to start. Then retry this Boot choice." >&2
  return 1
}

boot_transition_portal() {
  local current="$1" hook_status uki
  uki="$(boot_transition_current_uki)" || {
    echo "omarchy-kids-conf: refusing portal transition without a current UKI" >&2
    return 1
  }
  boot_transition_uki_has_hook && hook_status=0 || hook_status=$?
  if [[ "$hook_status" -eq 2 || "$hook_status" -eq 3 ]]; then
    echo "omarchy-kids-conf: refusing portal transition without an inspectable current UKI" >&2
    return 1
  fi

  if [[ "$current" == disk || "$current" == missing ]]; then
    boot_mode_set portal || return 1
  fi

  if [[ -e "$BOOT_TRANSITION_RECOVERY" || -L "$BOOT_TRANSITION_RECOVERY" ]]; then
    BOOT_TRANSITION_DEVICE="$(boot_transition_root_luks_device)" || return 1
    boot_transition_recover_additions portal || return 1
  fi
  boot_transition_remove_kid_slots || return 1
  boot_transition_restore_limine_editor || return 1
  boot_transition_restore_limine || return 1
  rm -f "$BOOT_TRANSITION_DROPIN" || return 1
  boot_transition_fsync_dir "$(dirname "$BOOT_TRANSITION_DROPIN")" || return 1

  boot_transition_uki_has_hook && hook_status=0 || hook_status=$?
  if [[ "$hook_status" -eq 0 ]]; then
    boot_transition_rebuild_needed
    return 1
  fi
  [[ "$hook_status" -eq 1 ]] || return 1
  [[ "$(boot_mode_get 2>/dev/null || true)" == portal ]]
}

boot_mode_transition() {
  local requested="$1" from_stdin="${2:-0}" current status
  current="$(boot_transition_current_mode)" || return 1
  case "$requested" in
    portal) boot_transition_portal "$current" ;;
    disk)
      if [[ "$current" == missing ]]; then
        boot_mode_set portal || return 1
        current=portal
      fi
      if boot_transition_disk "$current" "$from_stdin"; then
        status=0
      else
        status=$?
      fi
      BOOT_TRANSITION_SECRETS=()
      return "$status"
      ;;
    *) return 2 ;;
  esac
}
