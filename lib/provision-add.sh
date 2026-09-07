# shellcheck shell=bash
# lib/provision-add.sh — omarchy-kids-provision's "add" subcommand.
# Sourced by the dispatcher; not meant to be executed directly.
# docs/provision.md has the full design and every judgment call below.

resolve_add_account_locked() {
  local base="$1" display="$2" band="$3" avatar="$4" password_mode="$5" luks_mode="$6"
  local candidate="" account state accounts
  if [[ ! -d "$TRANSACTIONS_DIR" ]]; then
    printf '%s 0\n' "$(unique_account "$base")"
    return 0
  fi
  accounts="$(kids_transaction list "$TRANSACTIONS_DIR")" || return 1
  while IFS= read -r account; do
    [[ "$account" == "$base" || "$account" =~ ^${base}-[0-9]+$ ]] || continue
    kids_transaction validate "$TRANSACTIONS_DIR" "$account" || return 1
    state="$(luks_transaction_field "$account" account_state)" || return 1
    [[ "$state" != complete && "$state" != cleaned ]] || continue
    [[ "$(luks_transaction_field "$account" display)" == "$display" &&
    "$(luks_transaction_field "$account" band)" == "$band" &&
    "$(luks_transaction_field "$account" avatar)" == "$avatar" &&
    "$(luks_transaction_field "$account" password_mode)" == "$password_mode" &&
    "$(luks_transaction_field "$account" luks_mode)" == "$luks_mode" ]] || {
      echo "add: unfinished transaction for $account does not match this add request" >&2
      return 1
    }
    [[ -z "$candidate" ]] || {
      echo "add: more than one unfinished transaction matches $base; repair the journals before retrying" >&2
      return 1
    }
    candidate="$account"
  done <<<"$accounts"
  if [[ -n "$candidate" ]]; then
    printf '%s 1\n' "$candidate"
  else
    printf '%s 0\n' "$(unique_account "$base")"
  fi
}

account_matches_add_intent() {
  local account="$1" group="$2" entry name home shell groups expected
  entry="$(getent passwd "$account" 2>/dev/null)" || return 1
  IFS=: read -r name _ _ _ _ home shell <<<"$entry"
  [[ "$name" == "$account" && "$home" == "$(home_dir_for "$account")" && "$shell" == /bin/bash ]] || return 1
  groups="$(id -nG "$account" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -u)" || return 1
  expected="$(printf '%s\n' "$account" omarchy-kids "$group" | sort -u)"
  [[ "$groups" == "$expected" ]]
}

cmd_add() {
  local display="" band="" avatar="fox"
  local want_password=0 no_password=0
  local parent_pw_stdin=0 parent_pw_fd="" luks_device=""

  while (($#)); do
    case "$1" in
      --band)
        band="${2:?--band needs a value}"
        shift 2
        ;;
      --avatar)
        avatar="${2:?--avatar needs a value}"
        shift 2
        ;;
      --password-stdin)
        want_password=1
        shift
        ;;
      --no-password)
        no_password=1
        shift
        ;;
      --parent-password-stdin)
        parent_pw_stdin=1
        shift
        ;;
      --parent-password-fd)
        parent_pw_fd="${2:?--parent-password-fd needs a value}"
        shift 2
        ;;
      --luks-device)
        luks_device="${2:?--luks-device needs a value}"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --) shift ;;
      -*) die "add: unknown option '$1'" ;;
      *)
        if [[ -z "$display" ]]; then display="$1"; else die "add: unexpected argument '$1'"; fi
        shift
        ;;
    esac
  done

  [[ -n "$display" ]] || die "add: needs a display name"
  valid_display_name "$display" || die "add: display name may not contain a tab or newline and must be 1-64 characters"
  [[ -n "$band" ]] || die "add: needs --band"
  is_valid_band "$band" || die "add: unknown band '$band' (must be one of ${VALID_BANDS[*]})"
  if ((want_password && no_password)); then
    die "add: --password-stdin and --no-password are mutually exclusive"
  fi
  if ((! want_password && ! no_password)); then
    die "add: needs --password-stdin or --no-password"
  fi
  if ((no_password)); then
    local optional
    optional="$(band_field "$band" password_optional)"
    [[ "$optional" == "true" ]] || die "add: --no-password is only allowed for band 3-5"
  fi

  local boot_mode device=""
  boot_mode="$(read_boot_mode)"
  if [[ "$boot_mode" == portal ]] &&
    { ((parent_pw_stdin)) || [[ -n "$parent_pw_fd" || -n "$luks_device" ]]; }; then
    die "add: LUKS options are not available in portal mode"
  fi
  local base_account account group gecos_name transaction_exists=0 expected_password_mode expected_luks_mode
  expected_password_mode="$([[ $no_password == 1 ]] && echo none || echo set)"
  expected_luks_mode="$([[ $boot_mode == disk && $want_password == 1 ]] && echo owned || echo none)"
  base_account="$("$CONF_BIN" slug "$display")"
  group="$(group_for_band "$band")"
  gecos_name="$(gecos_name_for_display "$display")"

  local kid_password="" parent_password=""
  if ((want_password)); then
    if ! IFS= read -r kid_password; then
      [[ -n "$kid_password" ]] || die "add: --password-stdin needs the password on stdin"
    fi
    local min
    min="$(band_field "$band" password_min)"
    [[ "${#kid_password}" -ge "$min" ]] || die "add: password too short for band $band (minimum $min characters)"
  fi
  if ((parent_pw_stdin)); then
    if ! IFS= read -r parent_password; then
      [[ -n "$parent_password" ]] || die "add: --parent-password-stdin needs a second stdin line"
    fi
  elif [[ -n "$parent_pw_fd" ]]; then
    IFS= read -r parent_password <&"$parent_pw_fd" || die "add: could not read the parent password from fd $parent_pw_fd"
  fi
  if [[ "$boot_mode" == disk ]] && ((want_password)); then
    device="$(detect_luks_device "$luks_device")" ||
      die "add: disk mode needs a LUKS root; pass --luks-device if auto-detection failed" 1
    [[ -n "$parent_password" ]] ||
      die "add: disk mode needs the parent passphrase via --parent-password-stdin or --parent-password-fd"
  fi

  local parent
  parent="$(read_parent)"
  [[ -n "$parent" ]] || die "cannot find 'parent=' in $MACHINE_CONF; run machine setup before provisioning a kid"

  if [[ "$DRY_RUN" == 0 ]]; then
    transaction_dir_ensure || die "add: could not create trusted transaction storage" 1
    luks_lock_acquire "$SLOTS_FILE" || die "add: could not acquire the shared transaction lock" 1
  fi
  read -r account transaction_exists < <(resolve_add_account_locked "$base_account" "$display" "$band" "$avatar" \
    "$expected_password_mode" "$expected_luks_mode") || die "add: could not resolve the account transaction" 1

  # Durable ownership precedes the slot; portal/no-password records carry no fabricated LUKS identity.
  if [[ "$boot_mode" == disk ]] && ((want_password)); then
    # Never through `run`: its preview would print both secrets.
    if [[ "$DRY_RUN" == "0" ]]; then
      add_luks_slot "$account" "$device" "$display" "$band" "$avatar" "$transaction_exists" \
        3< <(printf '%s\n' "$kid_password") \
        4< <(printf '%s\n' "$parent_password")
    else
      printf '  [dry-run]'
      printf ' %q' add_luks_slot "$account" "$device"
      printf ' <secret> <secret>\n'
    fi
  elif [[ "$DRY_RUN" == 0 && "$transaction_exists" == 0 ]]; then
    kids_transaction create "$TRANSACTIONS_DIR" "$account" add - - \
      "$expected_password_mode" "$display" "$band" "$avatar" ||
      die "add: could not durably create the account transaction" 1
  fi

  echo "Adding kid '$display' as $account (band $band)"

  # R-FND-2: the account itself (groupadd -f: a checkout run may lack these).
  run groupadd -f omarchy-kids
  run groupadd -f "$group"
  if [[ "$DRY_RUN" == 0 ]]; then
    local account_state
    account_state="$(luks_transaction_field "$account" account_state)"
    if [[ "$account_state" == planned ]]; then
      kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" planned creating || die "add: could not record account creation intent" 1
      account_state=creating
    fi
    if [[ "$account_state" == creating ]]; then
      useradd -m -s /bin/bash -G "omarchy-kids,$group" "$account" ||
        account_matches_add_intent "$account" "$group" ||
        die "add: existing account $account does not match the recorded shell, home, and groups" 1
      kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" creating created || die "add: could not record account creation" 1
      account_state=created
    fi
  else
    run useradd -m -s /bin/bash -G "omarchy-kids,$group" "$account"
  fi

  # R-SEC-3: one password, or a locked account (3-5 only).
  if ((no_password)); then
    run usermod -L "$account"
  else
    printf '%s:%s\n' "$account" "$kid_password" | run chpasswd
  fi
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == created ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" created passworded || die "add: could not record password setup" 1
  fi

  # R-LOGIN, issue #39: keep a GECOS fallback where passwd(5) can carry it.
  # The root-owned portal profile is the exact display-name source.
  run usermod -c "$gecos_name" "$account"

  # R-FND-2: home bind-mounted nosuid,nodev,noexec (must exist before remount).
  run posture_add_fstab_line "$account"
  if ! command -v findmnt >/dev/null 2>&1 || ! findmnt -no TARGET "$(home_dir_for "$account")" >/dev/null 2>&1; then
    run mount --bind "$(home_dir_for "$account")" "$(home_dir_for "$account")"
    run mount -o remount,bind,nosuid,nodev,noexec "$(home_dir_for "$account")"
  fi
  if [[ "$DRY_RUN" == 0 ]]; then
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != passworded ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" passworded fstab
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != fstab ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" fstab mounted
  fi

  # Appendix B: the profile.
  run "$CONF_BIN" set "$account" name "$display"
  run "$CONF_BIN" set "$account" avatar "$avatar"
  run "$CONF_BIN" set "$account" band "$band"
  run "$CONF_BIN" set "$account" password "$([[ $no_password == 1 ]] && echo none || echo set)"
  run "$CONF_BIN" set "$account" onboarded no
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == mounted ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" mounted profile || die "add: could not record profile setup" 1
  fi

  # R-FND-3, R-FND-4: polkit admin identity + denies.
  run posture_write_polkit_admin_rule "$parent"
  run posture_write_polkit_deny_rule

  # R-FND-5: text consoles masked while any kid profile exists.
  local n sysctl_root=()
  [[ -n "${OMARCHY_KIDS_ROOT:-}" ]] && sysctl_root=(--root="$OMARCHY_KIDS_ROOT")
  for n in 2 3 4 5 6; do
    run systemctl "${sysctl_root[@]+"${sysctl_root[@]}"}" mask "getty@tty$n.service"
  done

  # R-FND-2a: a private noexec tmpfs for /tmp and /dev/shm.
  run posture_add_namespace_lines "$account"
  run posture_ensure_pam_namespace sddm
  run posture_ensure_pam_namespace systemd-user

  run posture_ensure_pam_namespace sddm-autologin
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == profile ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" profile namespace || die "add: could not record namespace setup" 1
  fi

  # R-SEC-2: the parent-unlock verifier line (docs/authd.md), idempotent.
  # Soft-fails: the lock screen's PAM stack may not exist yet on this box.
  ensure_parent_unlock_soft sddm
  ensure_parent_unlock_soft "$(posture_parent_unlock_lock_stack)"

  # R-LOGIN-3: pin the kid session, no session picker.
  run posture_write_accountsservice "$account" "$avatar"
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == namespace ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" namespace accountsservice || die "add: could not record AccountsService setup" 1
  fi

  # R-LOGIN, issue #39: the file SDDM's UserModel actually reads for the
  # avatar, not AccountsService's Icon= above (docs/portal.md's "Avatars").
  run posture_write_face_icon "$SHARE/avatars/$avatar.svg" "$account"
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == accountsservice ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" accountsservice face || die "add: could not record face setup" 1
  fi

  # R-LOGIN: select the portal theme. Left alone by "remove" until
  # Remove Kids Mode (R-FND-6) -- still correct while any kid remains.
  run posture_write_sddm_theme_dropin

  # R-LOGIN, issue #39: theme.conf.user, rebuilt whole (docs/portal.md).
  # This kid's entry is appended explicitly, not read back off $KIDS_DIR,
  # so DRY_RUN=1's preview shows the correct content unwritten.
  local portal_entries=() line
  while IFS= read -r line; do
    [[ -n "$line" ]] && portal_entries+=("$line")
  done < <(portal_conf_entries "$KIDS_DIR" "$account")
  portal_entries+=("$account"$'\t'"$display"$'\t'"$avatar")
  run posture_write_portal_conf "$parent" "${portal_entries[@]}"
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == face ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" face portal || die "add: could not record portal setup" 1
  fi

  # Issue #10 finding (b): so the desktop never shows "Pending Omarchy
  # Migrations" -- docs/provision.md's "Known gap". A failure here is a
  # warning, not a failed provision: everything else is already in place.
  if command -v omarchy-provision-user >/dev/null 2>&1; then
    if ! run runuser -l "$account" -c "omarchy-provision-user --first-install"; then
      echo "warning: omarchy-provision-user failed for $account; marking Omarchy migrations done instead" >&2
      run mark_migrations_done "$account"
    fi
  else
    run mark_migrations_done "$account"
  fi

  # Issue #44: override whatever chromium-flags.conf Omarchy's per-user
  # setup just left in this fresh home with Kids Mode's own copy, minus
  # the extension-loading flag the kids policy always refuses.
  run install_kids_chromium_flags "$account"

  # R-DESK, issue #53: the kid's desktop matches the house look at first
  # login -- docs/theming.md. "$CONF_BIN" set is the one writer; nothing here
  # touches theme files directly.
  local parent_theme=""
  parent_theme="$(THEME_KIDS_HOME="$(posture_parent_home "$parent")" theme_current_name)"
  if [[ -n "$parent_theme" ]]; then
    run "$CONF_BIN" set "$account" theme "$parent_theme"
  else
    echo "warning: parent '$parent' has no current Omarchy theme yet (never ran 'omarchy theme set'); $account keeps the desktop's stock theme" >&2
  fi

  # Root-built argv keeps kid-writable runtime data out of execution (finding 2).
  run launcher_map_fix "$account"
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == portal ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" portal launcher || die "add: could not record launcher setup" 1
  fi
  # The manifest is the single session input and must follow the launcher map.
  run session_manifest_build "$account"
  if [[ "$DRY_RUN" == 0 ]]; then
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != launcher ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" launcher session
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != session ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" session complete
    luks_lock_release
  fi

  echo "Done: $account"
}

# add_luks_slot ACCOUNT DEVICE — kid's passphrase on fd 3, parent's on fd
# 4, never argv, never through `run` (review S6, docs/provision.md).
add_luks_slot() {
  local account="$1" device="$2" display="$3" band="$4" avatar="$5" transaction_exists="$6"
  local kid_password parent_password
  IFS= read -r kid_password <&3 || true
  IFS= read -r parent_password <&4 || true
  [[ -n "$kid_password" && -n "$parent_password" ]] || die "add: add_luks_slot needs both passphrases on fds 3 and 4"
  luks_reconcile_all_locked "$device" || die "add: unresolved LUKS transaction blocks allocation" 1
  local slot state device_uuid
  if ((transaction_exists)); then
    slot="$(luks_transaction_field "$account" slot)"
  else
    device_uuid="$(luks_device_uuid "$device")" || die "add: could not read the LUKS device UUID" 1
    slot="$(luks_allocate_slot "$device")" || die "add: no unoccupied, unreserved LUKS slot is available" 1
    kids_transaction create "$TRANSACTIONS_DIR" "$account" add "$device_uuid" "$slot" set "$display" "$band" "$avatar" ||
      die "add: could not durably reserve LUKS slot $slot" 1
  fi
  state="$(luks_transaction_field "$account" state)"
  if [[ "$state" == reserved ]]; then
    if cryptsetup open --test-passphrase --key-file=<(printf '%s' "$kid_password") "$device" >/dev/null 2>&1; then
      die "add: that password already unlocks $device; pick a different one for $account"
    fi
    kids_transaction transition "$TRANSACTIONS_DIR" "$account" reserved adding || die "add: could not record adding state" 1
    state=adding
  fi
  if [[ "$state" == adding ]]; then
    if luks_slot_occupied "$device" "$slot"; then
      :
    else
      local slot_status=$?
      ((slot_status == 1)) || die "add: could not inspect reserved slot $slot" 1
      cryptsetup luksAddKey --batch-mode --key-slot "$slot" --key-file=<(printf '%s' "$parent_password") \
        "$device" <(printf '%s' "$kid_password") || die "add: cryptsetup luksAddKey failed for $account"
      luks_slot_occupied "$device" "$slot" ||
        die "add: LUKS header did not confirm added slot $slot; no slot was deleted" 1
    fi
    # An active untagged slot from a previous process is deliberately ambiguous;
    # only this invocation may bind immediately after its own successful add.
    luks_attach_transaction_token "$device" "$account" ||
      die "add: slot $slot is active but its ownership token could not be attached; no slot was deleted" 1
    kids_transaction transition "$TRANSACTIONS_DIR" "$account" adding added || die "add: could not record added state" 1
    state=added
  fi
  [[ "$(luks_transaction_field "$account" state)" == added ]] || die "add: transaction did not reach added" 1
  # A crash can leave durable `added` before the derived compatibility map.
  luks_rebuild_map_locked "$device" || die "add: could not derive the slot map" 1
  echo "  LUKS slot $slot added for $account"
}
