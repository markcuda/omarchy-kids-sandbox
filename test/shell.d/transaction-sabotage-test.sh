#!/bin/bash
# R-SEC-4, R-FND-2: prove the command-level safety assertions reject five known invariant breaks.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
source test/shell.d/lib.sh
source test/shell.d/tree.sh
source test/shell.d/transaction-command-fixture.sh

TX_REPO="$PWD"
TX_REAL_PY="$(command -v python3)"
TX_REAL_FLOCK="$(command -v flock)"
TX_REAL_MV="$(command -v mv)"
TX_REAL_STAT="$(command -v stat)"
TX_SCRATCH="$(mktemp -d)"
trap 'tx_fixture_cleanup_processes; rm -rf "$TX_SCRATCH"' EXIT

make_secrets() {
  TX_SECRETS="$TX_CASE/secrets"
  printf 'synthetic-kid-password\nsynthetic-parent-password\n' >"$TX_SECRETS"
  chmod 0600 "$TX_SECRETS"
}

require_red() {
  local label="$1" rc=0
  shift
  set +e
  "$@"
  rc=$?
  set -e
  [[ "$rc" != 0 ]] || {
    echo "sabotage escaped its safety assertion: $label" >&2
    exit 1
  }
  printf 'SABOTAGE RED %-24s detector_rc=%s\n' "$label" "$rc"
}

ownership_probe() {
  tx_add Ada
  sed -i '/# The proof is checked/,/if \[\[ -n "\$key_fd"/s/luks_token_matches_transaction .* || {/true || {/' \
    "$TX_TREE/lib/kids.sh"
  grep -q '^[[:space:]]*true || {$' "$TX_TREE/lib/kids.sh"
  tx_start_paused remove after-removing kid-ada
  jq '.transaction = "00000000-0000-4000-8000-000000000000"' "$TX_STATE/token.1.json" \
    >"$TX_STATE/token.1.changed"
  mv "$TX_STATE/token.1.changed" "$TX_STATE/token.1.json"
  tx_release_paused || true
  [[ ! -e "$TX_STATE/kill-without-proof" ]]
}

tx_fixture_init sabotage-ownership
make_secrets
require_red ownership-before-kill ownership_probe
[[ -e "$TX_STATE/kill-without-proof" && -e "$TX_STATE/slot.1" ]]

device_probe() {
  tx_start_paused add after-transaction-create Ada
  tx_kill_paused
  sed -i '/^luks_reconcile_transaction_locked()/,/^  slot=/ { /== "\$device_uuid"/c\  true || {
}' "$TX_TREE/lib/kids.sh"
  [[ "$(sed -n '/^luks_reconcile_transaction_locked()/,/^  slot=/p' "$TX_TREE/lib/kids.sh" |
    grep -c '^[[:space:]]*true || {$')" == 1 ]]
  tx_env "$TX_BIN" add Ada --band 6-8 --avatar fox --password-stdin \
    --parent-password-stdin --luks-device wrong-device <"$TX_SECRETS" \
    >"$TX_CASE/mutant.out" 2>&1 || true
  [[ ! -e "$TX_STATE/wrong.slot.1" ]]
}

tx_fixture_init sabotage-device
make_secrets
require_red device-validation device_probe
[[ -e "$TX_STATE/wrong.slot.1" && ! -e "$TX_STATE/slot.1" ]]

lock_probe() {
  sed -i '/kids_transaction transition .* adding added/i\    luks_lock_release' \
    "$TX_TREE/lib/provision-add.sh"
  [[ "$(grep -c '^[[:space:]]*luks_lock_release$' "$TX_TREE/lib/provision-add.sh")" -ge 2 ]]
  tx_start_paused add after-added Ada
  local completed="$TX_CASE/completed.fifo" contender_rc
  mkfifo "$completed"
  setsid timeout 45 env PATH="$TX_PATH" DRY_RUN=0 OMARCHY_KIDS_ETC="$TX_ETC" \
    OMARCHY_KIDS_SHARE="$TX_REPO/share" OMARCHY_KIDS_ROOT="$TX_ROOT" \
    OMARCHY_KIDS_HOME_ROOT="$TX_HOME" TX_STATE="$TX_STATE" TX_HOME="$TX_HOME" \
    TX_LOG="$TX_LOG" TX_RECORDS="$TX_RECORDS" TX_PAUSE="$TX_STUBS/fixture-pause" \
    bash -c '
    rc=0
    "$1" add Cy --band 6-8 --avatar fox --password-stdin --parent-password-stdin \
      --luks-device fixture-device <"$2" >/dev/null 2>&1 || rc=$?
    printf "%s\n" "$rc" >"$3"
    exit "$rc"
  ' _ "$TX_BIN" "$TX_SECRETS" "$completed" &
  local contender=$!
  TX_ACTIVE_PIDS+=("$contender")
  contender_rc="$(timeout 20 bash -c 'IFS= read -r value <"$1"; printf "%s\n" "$value"' _ "$completed")" || return 1
  tx_wait_pid "$contender" || return 1
  [[ "$contender_rc" == 0 ]] || return 1
  [[ ! -e "$TX_RECORDS/kid-cy.json" && ! -e "$TX_STATE/account.kid-cy" ]]
}

tx_fixture_init sabotage-lock
make_secrets
require_red shortened-lock lock_probe
tx_kill_paused

map_probe() {
  tx_start_paused add after-added Ada
  tx_kill_paused
  sed -i '/luks_rebuild_map_locked "\$device" || die "add: could not derive the slot map" 1/d' \
    "$TX_TREE/lib/provision-add.sh"
  ! grep -q 'could not derive the slot map' "$TX_TREE/lib/provision-add.sh"
  tx_add Ada >/dev/null
  grep -qx '1=kid-ada' "$TX_ETC/luks-slots"
}

tx_fixture_init sabotage-map
make_secrets
require_red omitted-map-recovery map_probe
[[ "$(grep -c '=kid-ada$' "$TX_ETC/luks-slots" || true)" == 0 ]]

recycled_probe() {
  tx_add Ada
  tx_remove kid-ada
  tx_add Cy
  sed -i '/if \[\[ "\$state" == removed \]\]; then/a\    slot="$(luks_transaction_field "$account" slot)" || return 1\
    cryptsetup luksKillSlot --batch-mode "$device" "$slot" || return 1' "$TX_TREE/lib/kids.sh"
  grep -A2 'if \[\[ "\$state" == removed' "$TX_TREE/lib/kids.sh" | grep -q luksKillSlot
  tx_remove kid-ada >/dev/null 2>&1 || true
  [[ ! -e "$TX_STATE/kill-without-proof" ]]
}

tx_fixture_init sabotage-recycled
make_secrets
require_red recycled-old-transaction recycled_probe
[[ -e "$TX_STATE/kill-without-proof" && -e "$TX_STATE/slot.1" ]]
[[ "$(jq -r .account "$TX_STATE/token.1.json")" == kid-cy ]]

echo 'transaction-sabotage-test RESULT: PASS (all five copied-source mutants were caught RED)'
