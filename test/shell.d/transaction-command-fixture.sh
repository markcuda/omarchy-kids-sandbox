# shellcheck shell=bash
# Shared isolated machine for issue 107 command crash/concurrency tests.

TX_ACTIVE_PIDS=()

tx_forget_pid() {
  local target="$1" pid kept=()
  for pid in "${TX_ACTIVE_PIDS[@]+"${TX_ACTIVE_PIDS[@]}"}"; do
    [[ "$pid" == "$target" ]] || kept+=("$pid")
  done
  TX_ACTIVE_PIDS=("${kept[@]}")
}

tx_fixture_cleanup_processes() {
  local pid
  for pid in "${TX_ACTIVE_PIDS[@]+"${TX_ACTIVE_PIDS[@]}"}"; do
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
}

tx_fixture_init() {
  local label="$1"
  TX_CASE="$TX_SCRATCH/$label"
  TX_ETC="$TX_CASE/etc/omarchy-kids"
  TX_ROOT="$TX_CASE/root"
  TX_HOME="$TX_CASE/home-root"
  TX_STATE="$TX_CASE/admin-state"
  TX_STUBS="$TX_CASE/stubs"
  TX_TREE="$TX_CASE/tree"
  TX_LOG="$TX_CASE/events.log"
  TX_BIN="$TX_TREE/bin/omarchy-kids-provision"
  # shellcheck disable=SC2034 # consumed by the sourcing command tests.
  TX_CONF="$TX_TREE/bin/omarchy-kids-conf"
  # shellcheck disable=SC2034 # consumed by the sourcing command tests.
  TX_FULL_REMOVE="$TX_TREE/bin/omarchy-kids-remove"
  TX_RECORDS="$TX_ROOT/var/lib/omarchy-kids/transactions"
  mkdir -p "$TX_ETC/kids" "$TX_ROOT/usr/lib/pam.d" "$TX_ROOT/etc/pam.d" \
    "$TX_HOME/home/parent" "$TX_STATE" "$TX_STUBS"
  printf 'account include system-login\nsession include system-login\n' >"$TX_ROOT/usr/lib/pam.d/systemd-user"
  printf 'auth include system-login\naccount include system-login\nsession include system-login\n' >"$TX_ROOT/etc/pam.d/sddm"
  printf 'parent=parent\nboot=disk\n' >"$TX_ETC/machine.conf"
  printf '0=parent:omarchy.desktop\n' >"$TX_ETC/luks-slots"
  : >"$TX_LOG"

  kids_tree "$TX_TREE" "$TX_REPO"
  rm -f "$TX_TREE/lib"
  cp -a "$TX_REPO/lib" "$TX_TREE/lib"
  kids_set_const "$TX_TREE/lib/boot-mode.sh" BOOT_MODE_MACHINE_CONF "$TX_ETC/machine.conf"

  tx_fixture_write_stubs
  TX_BASE_PATH="$(kids_base_path "$TX_CASE/base" flock setsid)"
  TX_PATH="$TX_STUBS:$TX_BASE_PATH"
}

tx_fixture_stub() {
  local name="$1"
  shift
  {
    printf '#!/bin/bash\nset -euo pipefail\n'
    printf 'printf "%%s" %q >>%q; printf " %%s" "$@" >>%q; printf "\\n" >>%q\n' \
      "$name" "$TX_LOG" "$TX_LOG" "$TX_LOG"
    printf '%s\n' "$*"
  } >"$TX_STUBS/$name"
  chmod +x "$TX_STUBS/$name"
}

tx_fixture_write_stubs() {
  cat >"$TX_STUBS/fixture-pause" <<'EOF'
#!/bin/bash
set -euo pipefail
[[ "${FIXTURE_PAUSE:-}" == "$1" ]] || exit 0
printf '%s\n' "$1" >"$FIXTURE_READY"
IFS= read -r _ <"$FIXTURE_RELEASE"
EOF
  chmod +x "$TX_STUBS/fixture-pause"

  mkdir -p "$TX_STUBS/python-hooks"
  cat >"$TX_STUBS/python-hooks/sitecustomize.py" <<'EOF'
import os
import stat
import sys


def fixture_pause(point):
    if os.environ.get("FIXTURE_PAUSE") != point:
        return
    with open(os.environ["FIXTURE_READY"], "w", encoding="utf-8") as ready:
        ready.write(point + "\n")
    with open(os.environ["FIXTURE_RELEASE"], "r", encoding="utf-8") as release:
        release.readline()


if len(sys.argv) > 1 and sys.argv[0].endswith("/transaction.py") and sys.argv[1] == "create":
    real_replace = os.replace
    real_fsync = os.fsync

    def observed_replace(source, destination):
        real_replace(source, destination)
        fixture_pause("after-transaction-create")

    def observed_fsync(fd):
        real_fsync(fd)
        if stat.S_ISDIR(os.fstat(fd).st_mode):
            fixture_pause("after-reserved-fsync")

    os.replace = observed_replace
    os.fsync = observed_fsync
EOF

  cat >"$TX_STUBS/python3" <<EOF
#!/bin/bash
set -euo pipefail
real=$(printf '%q' "$TX_REAL_PY")
pause=$(printf '%q' "$TX_STUBS/fixture-pause")
if [[ "\${2:-}" == create && "\${FIXTURE_PAUSE:-}" == before-transaction-create ]]; then
  "\$pause" before-transaction-create
fi
if [[ "\${1:-}" == */transaction.py && "\${2:-}" == create ]]; then
  PYTHONPATH=$(printf '%q' "$TX_STUBS/python-hooks") "\$real" "\$@"
else
  "\$real" "\$@"
fi
rc=\$?
((rc == 0)) || exit "\$rc"
if [[ "\${1:-}" == */transaction.py ]]; then
  case "\${2:-}:\${5:-}:\${6:-}" in
    transition:reserved:adding) "\$pause" after-adding ;;
    transition:adding:added) "\$pause" after-added ;;
    transition:added:removing) "\$pause" after-removing ;;
    transition:removing:removed) "\$pause" after-removed ;;
    lifecycle:planned:creating) "\$pause" after-creating ;;
  esac
elif [[ "\${1:-}" == -c && "\${@: -1}" == */luks-slots ]]; then
  "\$pause" after-map-rewrite
fi
EOF
  chmod +x "$TX_STUBS/python3"

  cat >"$TX_STUBS/flock" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == -x && -n "\${FIXTURE_LOCK_ATTEMPT:-}" ]]; then
  rc=0
  $(printf '%q' "$TX_REAL_FLOCK") -xn "\${2:-}" || rc=\$?
  [[ "\$rc" == 1 ]] || {
    [[ "\$rc" != 0 ]] || $(printf '%q' "$TX_REAL_FLOCK") -u "\${2:-}"
    exit 70
  }
  printf 'attempt\n' >"\$FIXTURE_LOCK_ATTEMPT"
fi
exec $(printf '%q' "$TX_REAL_FLOCK") "\$@"
EOF
  chmod +x "$TX_STUBS/flock"

  cat >"$TX_STUBS/cryptsetup" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'cryptsetup' >>"$TX_LOG"; printf ' %s' "$@" >>"$TX_LOG"; printf '\n' >>"$TX_LOG"
case "$1" in
  luksUUID)
    if [[ "$2" == wrong-device ]]; then
      printf '%s\n' '29fb2bf3-bf6e-4123-8aa5-a182ddddee02'
    else
      printf '%s\n' '18ea1ae2-ae5d-4012-9ff4-f071ccccdd01'
    fi
    ;;
  luksDump)
    if [[ "${2:-}" == --dump-json-metadata ]]; then device="$3"; else device="$2"; fi
    prefix=""; [[ "$device" != wrong-device ]] || prefix=wrong.
    if [[ "${2:-}" == --dump-json-metadata ]]; then
      printf '{"tokens":{'
      comma=
      for token in "$TX_STATE"/${prefix}token.*.json; do
        [[ -e "$token" ]] || continue
        slot="${token##*/}"; slot="${slot#${prefix}token.}"; slot="${slot%.json}"
        printf '%s"%s":' "$comma" "$slot"
        cat "$token"
        comma=,
      done
      printf '}}\n'
    else
      printf 'Keyslots:\n  0: luks2\n'
      for marker in "$TX_STATE"/${prefix}slot.*; do
        [[ -e "$marker" ]] || continue
        printf '  %s: luks2\n' "${marker##*.}"
      done
    fi
    ;;
  open) exit 1 ;;
  luksAddKey)
    device="${@: -2:1}"; prefix=""; [[ "$device" != wrong-device ]] || prefix=wrong.
    slot=
    while (($#)); do
      if [[ "$1" == --key-slot ]]; then slot="$2"; break; fi
      shift
    done
    [[ "$slot" =~ ^[1-9][0-9]*$ && ! -e "$TX_STATE/${prefix}slot.$slot" ]]
    : >"$TX_STATE/${prefix}slot.$slot"
    "$TX_PAUSE" after-add
    ;;
  token)
    [[ "${2:-}" == import ]]
    device="${@: -1}"; prefix=""; [[ "$device" != wrong-device ]] || prefix=wrong.
    json=
    while (($#)); do
      if [[ "$1" == --json-file ]]; then json="$2"; break; fi
      shift
    done
    slot="$(jq -r .slot "$json")"
    [[ -e "$TX_STATE/${prefix}slot.$slot" && ! -e "$TX_STATE/${prefix}token.$slot.json" ]]
    cp "$json" "$TX_STATE/${prefix}token.$slot.json"
    "$TX_PAUSE" after-token
    ;;
  luksKillSlot)
    device="${@: -2:1}"; prefix=""; [[ "$device" != wrong-device ]] || prefix=wrong.
    slot="${@: -1}"
    [[ -e "$TX_STATE/${prefix}slot.$slot" && -f "$TX_STATE/${prefix}token.$slot.json" ]]
    token="$TX_STATE/${prefix}token.$slot.json"
    record="$(jq -r .account "$token")"
    record="$TX_RECORDS/$record.json"
    jq -e --slurpfile record "$record" '
      .account == $record[0].account and .transaction == $record[0].transaction and
      .owner == $record[0].owner and .device_uuid == $record[0].device_uuid and
      .slot == $record[0].slot and $record[0].state == "removing"
    ' "$token" >/dev/null || { : >"$TX_STATE/kill-without-proof"; exit 1; }
    rm -f "$TX_STATE/${prefix}slot.$slot" "$TX_STATE/${prefix}token.$slot.json"
    printf '%s\n' "$slot" >>"$TX_STATE/kills"
    "$TX_PAUSE" after-kill
    ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$TX_STUBS/cryptsetup"

  cat >"$TX_STUBS/useradd" <<'EOF'
#!/bin/bash
set -euo pipefail
account="${@: -1}"
[[ ! -e "$TX_STATE/account.$account" ]] || exit 9
: >"$TX_STATE/account.$account"
mkdir -p "$TX_HOME/home/$account"
printf 'useradd %s\n' "$account" >>"$TX_LOG"
"$TX_PAUSE" after-useradd
EOF
  chmod +x "$TX_STUBS/useradd"

  cat >"$TX_STUBS/id" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
  -u) echo 0 ;;
  -un) echo root ;;
  -nG)
    account="$2"
    [[ -e "$TX_STATE/account.$account" ]]
    printf '%s omarchy-kids omarchy-kids-6-8\n' "$account"
    ;;
  *)
    account="${@: -1}"
    [[ -e "$TX_STATE/account.$account" ]]
    printf 'uid=1001(%s) gid=1001(%s) groups=1001(%s)\n' "$account" "$account" "$account"
    ;;
esac
EOF
  chmod +x "$TX_STUBS/id"

  cat >"$TX_STUBS/userdel" <<'EOF'
#!/bin/bash
set -euo pipefail
account="${@: -1}"
[[ -e "$TX_STATE/account.$account" ]] || exit 6
rm -f "$TX_STATE/account.$account"
printf 'userdel %s\n' "$account" >>"$TX_LOG"
"$TX_PAUSE" after-userdel
EOF
  chmod +x "$TX_STUBS/userdel"

  cat >"$TX_STUBS/getent" <<'EOF'
#!/bin/bash
set -euo pipefail
if [[ "$1" == passwd ]]; then
  account="$2"
  if [[ "$account" == parent ]]; then
    printf 'parent:x:1000:1000:Parent:%s/home/parent:/bin/bash\n' "$TX_HOME"
  elif [[ -e "$TX_STATE/account.$account" ]]; then
    if [[ -e "$TX_STATE/bad-account.$account" ]]; then
      printf '%s:x:1001:1001:%s:%s/home/not-%s:/bin/false\n' "$account" "$account" "$TX_HOME" "$account"
    else
      printf '%s:x:1001:1001:%s:%s/home/%s:/bin/bash\n' "$account" "$account" "$TX_HOME" "$account"
    fi
  else
    exit 2
  fi
else
  exit 2
fi
EOF
  chmod +x "$TX_STUBS/getent"

  cat >"$TX_STUBS/findmnt" <<'EOF'
#!/bin/bash
set -euo pipefail
target="${@: -1}"
account="${target##*/}"
[[ -e "$TX_STATE/mount.$account" ]] || exit 1
printf '%s\n' "$target"
EOF
  chmod +x "$TX_STUBS/findmnt"

  cat >"$TX_STUBS/mount" <<'EOF'
#!/bin/bash
set -euo pipefail
target="${@: -1}"; account="${target##*/}"
: >"$TX_STATE/mount.$account"
printf 'mount %s\n' "$account" >>"$TX_LOG"
EOF
  chmod +x "$TX_STUBS/mount"

  cat >"$TX_STUBS/umount" <<'EOF'
#!/bin/bash
set -euo pipefail
target="${@: -1}"; account="${target##*/}"
[[ -e "$TX_STATE/mount.$account" ]]
rm -f "$TX_STATE/mount.$account"
printf 'umount %s\n' "$account" >>"$TX_LOG"
"$TX_PAUSE" after-unmount
EOF
  chmod +x "$TX_STUBS/umount"

  cat >"$TX_STUBS/mv" <<EOF
#!/bin/bash
set -euo pipefail
$(printf '%q' "$TX_REAL_MV") "\$@"
if [[ "\${FIXTURE_PAUSE:-}" == after-home-move && "\${1:-}" == "\$TX_HOME/home/"kid-* ]]; then
  "\$TX_PAUSE" after-home-move
fi
EOF
  chmod +x "$TX_STUBS/mv"

  cat >"$TX_STUBS/stat" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == --version ]]; then exec $(printf '%q' "$TX_REAL_STAT") "\$@"; fi
format="\${2:-}"; target="\${3:-}"
if [[ "\$target" == $(printf '%q' "$TX_ETC") || "\$target" == $(printf '%q' "$TX_ETC/machine.conf") ]]; then
  case "\$format" in %u) echo 0 ;; %G|%Sg) echo root ;; *) exec $(printf '%q' "$TX_REAL_STAT") "\$@" ;; esac
  exit 0
fi
exec $(printf '%q' "$TX_REAL_STAT") "\$@"
EOF
  chmod +x "$TX_STUBS/stat"

  tx_fixture_stub groupadd ':'
  tx_fixture_stub usermod ':'
  tx_fixture_stub chpasswd 'while IFS= read -r _; do :; done'
  tx_fixture_stub systemctl ':'
  tx_fixture_stub runuser ':'
  tx_fixture_stub omarchy-provision-user ':'
  tx_fixture_stub chown ':'
  tx_fixture_stub gpasswd ':'
}

tx_env() {
  env PATH="$TX_PATH" DRY_RUN=0 OMARCHY_KIDS_ETC="$TX_ETC" \
    OMARCHY_KIDS_SHARE="$TX_REPO/share" OMARCHY_KIDS_ROOT="$TX_ROOT" \
    OMARCHY_KIDS_HOME_ROOT="$TX_HOME" TX_STATE="$TX_STATE" TX_HOME="$TX_HOME" \
    TX_LOG="$TX_LOG" TX_RECORDS="$TX_RECORDS" TX_PAUSE="$TX_STUBS/fixture-pause" "$@"
}

tx_add() {
  local display="$1"
  tx_env "$TX_BIN" add "$display" --band 6-8 --avatar fox --password-stdin \
    --parent-password-stdin --luks-device fixture-device <"$TX_SECRETS"
}

tx_remove() {
  tx_env "$TX_BIN" remove "$1" --luks-device fixture-device
}

tx_wait_pid() {
  local pid="$1" rc=0
  wait "$pid" || rc=$?
  tx_forget_pid "$pid"
  return "$rc"
}

tx_start_paused() {
  local operation="$1" point="$2" value="$3"
  TX_READY="$TX_CASE/ready.fifo"
  TX_RELEASE="$TX_CASE/release.fifo"
  mkfifo "$TX_READY" "$TX_RELEASE"
  if [[ "$operation" == add ]]; then
    setsid timeout 45 env PATH="$TX_PATH" DRY_RUN=0 OMARCHY_KIDS_ETC="$TX_ETC" \
      OMARCHY_KIDS_SHARE="$TX_REPO/share" OMARCHY_KIDS_ROOT="$TX_ROOT" \
      OMARCHY_KIDS_HOME_ROOT="$TX_HOME" TX_STATE="$TX_STATE" TX_HOME="$TX_HOME" \
      TX_LOG="$TX_LOG" TX_RECORDS="$TX_RECORDS" TX_PAUSE="$TX_STUBS/fixture-pause" \
      FIXTURE_PAUSE="$point" FIXTURE_READY="$TX_READY" FIXTURE_RELEASE="$TX_RELEASE" \
      "$TX_BIN" add "$value" --band 6-8 --avatar fox --password-stdin \
      --parent-password-stdin --luks-device fixture-device <"$TX_SECRETS" >"$TX_CASE/paused.out" 2>&1 &
  else
    setsid timeout 45 env PATH="$TX_PATH" DRY_RUN=0 OMARCHY_KIDS_ETC="$TX_ETC" \
      OMARCHY_KIDS_SHARE="$TX_REPO/share" OMARCHY_KIDS_ROOT="$TX_ROOT" \
      OMARCHY_KIDS_HOME_ROOT="$TX_HOME" TX_STATE="$TX_STATE" TX_HOME="$TX_HOME" \
      TX_LOG="$TX_LOG" TX_RECORDS="$TX_RECORDS" TX_PAUSE="$TX_STUBS/fixture-pause" \
      FIXTURE_PAUSE="$point" FIXTURE_READY="$TX_READY" FIXTURE_RELEASE="$TX_RELEASE" \
      "$TX_BIN" remove "$value" --luks-device fixture-device >"$TX_CASE/paused.out" 2>&1 &
  fi
  TX_PID=$!
  TX_ACTIVE_PIDS+=("$TX_PID")
  timeout 20 bash -c 'IFS= read -r line <"$1"; [[ "$line" == "$2" ]]' _ "$TX_READY" "$point"
}

tx_kill_paused() {
  kill -KILL -- "-$TX_PID" 2>/dev/null || true
  wait "$TX_PID" 2>/dev/null || true
  tx_forget_pid "$TX_PID"
  rm -f "$TX_READY" "$TX_RELEASE"
}

tx_release_paused() {
  local rc=0
  timeout 20 bash -c 'printf "release\n" >"$1"' _ "$TX_RELEASE"
  tx_wait_pid "$TX_PID" || rc=$?
  rm -f "$TX_READY" "$TX_RELEASE"
  return "$rc"
}

tx_assert_add_complete() {
  local account="$1" slot namespace_file fstab_file
  [[ -f "$TX_RECORDS/$account.json" ]]
  [[ "$(jq -r .state "$TX_RECORDS/$account.json")" == added ]]
  [[ "$(jq -r .account_state "$TX_RECORDS/$account.json")" == complete ]]
  slot="$(jq -r .slot "$TX_RECORDS/$account.json")"
  [[ -e "$TX_STATE/slot.$slot" && -f "$TX_STATE/token.$slot.json" ]]
  jq -e --slurpfile record "$TX_RECORDS/$account.json" '
    (keys | sort) == (["account", "device_uuid", "keyslots", "owner", "schema", "slot", "transaction", "type"] | sort) and
    .type == "omarchy-kids" and .schema == 1 and .keyslots == [(.slot | tostring)] and
    .account == $record[0].account and .transaction == $record[0].transaction and
    .owner == $record[0].owner and .device_uuid == $record[0].device_uuid and
    .slot == $record[0].slot
  ' "$TX_STATE/token.$slot.json" >/dev/null
  [[ "$(find "$TX_STATE" -maxdepth 1 -name "slot.$slot" -type f | wc -l)" == 1 ]]
  [[ "$(find "$TX_STATE" -maxdepth 1 -name "token.$slot.json" -type f | wc -l)" == 1 ]]
  jq -se --arg account "$account" '[.[] | select(.account == $account)] | length == 1' \
    "$TX_STATE"/token.*.json >/dev/null
  [[ "$(grep -c "^$slot=$account$" "$TX_ETC/luks-slots")" == 1 ]]
  [[ -e "$TX_STATE/account.$account" ]]
  [[ -f "$TX_ETC/kids/$account.conf" ]]
  fstab_file="$TX_ROOT/etc/fstab"
  [[ "$(grep -cFx "/home/$account /home/$account none bind,nosuid,nodev,noexec 0 0" "$fstab_file")" == 1 ]]
  [[ -e "$TX_STATE/mount.$account" ]]
  namespace_file="$TX_ROOT/etc/security/namespace.conf"
  [[ "$(grep -cFx "/tmp /tmp/kids-inst/ tmpfs:mntopts=nosuid,nodev,noexec $account" "$namespace_file")" == 1 ]]
  [[ "$(grep -cFx "/dev/shm /dev/shm/kids-inst/ tmpfs:mntopts=nosuid,nodev,noexec $account" "$namespace_file")" == 1 ]]
  [[ "$(grep -c "$account" "$namespace_file")" == 2 ]]
  [[ -f "$TX_ROOT/var/lib/AccountsService/users/$account" ]]
  [[ -f "$TX_ROOT/usr/share/sddm/faces/$account.face.icon" ]]
  [[ -f "$TX_ETC/launchers/$account.json" ]]
  [[ -f "$TX_ETC/sessions/$account.json" ]]
}

tx_assert_removed() {
  local account="$1" slot destination namespace_file fstab_file token
  slot="$(jq -r .slot "$TX_RECORDS/$account.json")"
  destination="$(jq -r .destination "$TX_RECORDS/$account.json")"
  [[ "$(jq -r .state "$TX_RECORDS/$account.json")" == removed ]]
  [[ "$(jq -r .account_state "$TX_RECORDS/$account.json")" == cleaned ]]
  [[ ! -e "$TX_STATE/account.$account" ]]
  [[ "$(grep -c "=$account$" "$TX_ETC/luks-slots" || true)" == 0 ]]
  if [[ -e "$TX_STATE/slot.$slot" ]]; then
    token="$TX_STATE/token.$slot.json"
    [[ -f "$token" ]]
    jq -e --slurpfile record "$TX_RECORDS/$account.json" '
      (.account != $record[0].account or .transaction != $record[0].transaction or
       .owner != $record[0].owner or .device_uuid != $record[0].device_uuid or
       .slot != $record[0].slot)
    ' "$token" >/dev/null
  else
    [[ ! -e "$TX_STATE/token.$slot.json" ]]
  fi
  [[ ! -e "$TX_ETC/kids/$account.conf" ]]
  fstab_file="$TX_ROOT/etc/fstab"
  [[ "$(grep -cFx "/home/$account /home/$account none bind,nosuid,nodev,noexec 0 0" "$fstab_file" || true)" == 0 ]]
  [[ ! -e "$TX_STATE/mount.$account" ]]
  namespace_file="$TX_ROOT/etc/security/namespace.conf"
  [[ "$(grep -c "$account" "$namespace_file" 2>/dev/null || true)" == 0 ]]
  [[ ! -e "$TX_ROOT/var/lib/AccountsService/users/$account" ]]
  [[ ! -e "$TX_ROOT/usr/share/sddm/faces/$account.face.icon" ]]
  [[ ! -e "$TX_ETC/launchers/$account.json" ]]
  [[ ! -e "$TX_ETC/sessions/$account.json" ]]
  [[ "$destination" != null && -d "$destination" ]]
  [[ ! -e "$TX_HOME/home/$account" ]]
  [[ ! -e "$TX_STATE/kill-without-proof" ]]
}
