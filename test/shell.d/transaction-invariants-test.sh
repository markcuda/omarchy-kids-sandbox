#!/bin/bash
# R-SEC-4, R-FND-2, R-FND-6: entry-point regressions for transaction ownership and lifecycle invariants.
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

run_add_on() {
  local device="$1"
  tx_env "$TX_BIN" add Ada --band 6-8 --avatar fox --password-stdin \
    --parent-password-stdin --luks-device "$device" <"$TX_SECRETS"
}

# A reserved retry is bound to the recorded device before occupancy, state,
# map, account, or either fixture header may change.
tx_fixture_init wrong-device-add
make_secrets
tx_start_paused add after-transaction-create Ada
tx_kill_paused
record_before="$(sha256sum "$TX_RECORDS/kid-ada.json")"
map_before="$(sha256sum "$TX_ETC/luks-slots")"
: >"$TX_LOG"
if run_add_on wrong-device >"$TX_CASE/wrong-add.out" 2>&1; then
  echo 'wrong-device add unexpectedly succeeded' >&2
  exit 1
fi
[[ "$(sha256sum "$TX_RECORDS/kid-ada.json")" == "$record_before" ]]
[[ "$(sha256sum "$TX_ETC/luks-slots")" == "$map_before" ]]
[[ ! -e "$TX_STATE/slot.1" && ! -e "$TX_STATE/wrong.slot.1" ]]
[[ ! -e "$TX_STATE/account.kid-ada" ]]
! grep -q 'luksAddKey\|luksKillSlot' "$TX_LOG"
echo 'PASS invariant wrong-device add'

# Removal on a second UUID cannot retire the record, rewrite the map, remove
# the account, or touch either fixture header.
tx_fixture_init wrong-device-remove
make_secrets
tx_add Ada
record_before="$(sha256sum "$TX_RECORDS/kid-ada.json")"
map_before="$(sha256sum "$TX_ETC/luks-slots")"
: >"$TX_LOG"
if tx_env "$TX_BIN" remove kid-ada --luks-device wrong-device >"$TX_CASE/wrong-remove.out" 2>&1; then
  echo 'wrong-device remove unexpectedly succeeded' >&2
  exit 1
fi
[[ "$(sha256sum "$TX_RECORDS/kid-ada.json")" == "$record_before" ]]
[[ "$(sha256sum "$TX_ETC/luks-slots")" == "$map_before" ]]
[[ -e "$TX_STATE/slot.1" && -e "$TX_STATE/token.1.json" ]]
[[ -e "$TX_STATE/account.kid-ada" && ! -e "$TX_STATE/wrong.slot.1" ]]
! grep -q 'luksAddKey\|luksKillSlot\|userdel' "$TX_LOG"
echo 'PASS invariant wrong-device remove'

# Full portal removal consults the authoritative owned transaction even when
# its derived map line has been lost.
tx_fixture_init portal-owned
make_secrets
tx_add Ada
sed -i 's/^boot=disk$/boot=portal/' "$TX_ETC/machine.conf"
sed -i '/=kid-ada$/d' "$TX_ETC/luks-slots"
: >"$TX_LOG"
if tx_env "$TX_FULL_REMOVE" --yes --no-snapshot >"$TX_CASE/portal.out" 2>&1; then
  echo 'portal owned full removal unexpectedly succeeded' >&2
  exit 1
fi
[[ -e "$TX_RECORDS/kid-ada.json" && -e "$TX_STATE/account.kid-ada" ]]
[[ -e "$TX_HOME/home/kid-ada" && -e "$TX_ETC/kids/kid-ada.conf" && -e "$TX_STATE/slot.1" ]]
! grep -q '^cryptsetup\|^userdel' "$TX_LOG"
echo 'PASS invariant portal owned transaction'

# A pre-107 intent with no map/token/transaction remains ambiguous evidence;
# it is never imported as a no-LUKS profile or cleaned up.
tx_fixture_init legacy-intent
make_secrets
tx_add Ada
rm -f "$TX_RECORDS/kid-ada.json" "$TX_STATE/token.1.json"
sed -i '/=kid-ada$/d' "$TX_ETC/luks-slots"
printf '1=kid-ada\n' >"$TX_ETC/luks-slots.removing-kid-ada"
: >"$TX_LOG"
if tx_env "$TX_FULL_REMOVE" --yes --no-snapshot --luks-device fixture-device \
  >"$TX_CASE/legacy.out" 2>&1; then
  echo 'ambiguous legacy intent full removal unexpectedly succeeded' >&2
  exit 1
fi
[[ ! -e "$TX_RECORDS/kid-ada.json" && -e "$TX_ETC/luks-slots.removing-kid-ada" ]]
[[ -e "$TX_STATE/account.kid-ada" && -e "$TX_HOME/home/kid-ada" ]]
[[ -e "$TX_ETC/kids/kid-ada.conf" && -e "$TX_STATE/slot.1" ]]
! grep -q 'luksKillSlot\|userdel' "$TX_LOG"
echo 'PASS invariant legacy intent preserved'

# A valid no-LUKS journal cannot launder conflicting legacy map evidence left
# by an older interrupted importer.
tx_fixture_init nonowned-map-conflict
make_secrets
tx_add Ada
jq '.luks_mode = "none" | .device_uuid = null | .slot = null' "$TX_RECORDS/kid-ada.json" \
  >"$TX_RECORDS/kid-ada.changed"
mv "$TX_RECORDS/kid-ada.changed" "$TX_RECORDS/kid-ada.json"
record_before="$(sha256sum "$TX_RECORDS/kid-ada.json")"
map_before="$(sha256sum "$TX_ETC/luks-slots")"
: >"$TX_LOG"
if tx_remove kid-ada >"$TX_CASE/nonowned-map.out" 2>&1; then
  echo 'non-LUKS transaction with map evidence unexpectedly removed' >&2
  exit 1
fi
[[ "$(sha256sum "$TX_RECORDS/kid-ada.json")" == "$record_before" ]]
[[ "$(sha256sum "$TX_ETC/luks-slots")" == "$map_before" ]]
[[ -e "$TX_STATE/account.kid-ada" && -e "$TX_HOME/home/kid-ada" && -e "$TX_ETC/kids/kid-ada.conf" ]]
! grep -q 'luksKillSlot\|userdel' "$TX_LOG"
echo 'PASS invariant non-LUKS map conflict preserved'

# The same conflict through a legacy intent blocks full removal before any
# account, home, profile, evidence, or header cleanup.
tx_fixture_init nonowned-intent-conflict
make_secrets
tx_add Ada
jq '.luks_mode = "none" | .device_uuid = null | .slot = null' "$TX_RECORDS/kid-ada.json" \
  >"$TX_RECORDS/kid-ada.changed"
mv "$TX_RECORDS/kid-ada.changed" "$TX_RECORDS/kid-ada.json"
sed -i '/=kid-ada$/d' "$TX_ETC/luks-slots"
printf '1=kid-ada\n' >"$TX_ETC/luks-slots.removing-kid-ada"
: >"$TX_LOG"
if tx_env "$TX_FULL_REMOVE" --yes --no-snapshot --luks-device fixture-device \
  >"$TX_CASE/nonowned-intent.out" 2>&1; then
  echo 'non-LUKS transaction with legacy intent unexpectedly removed' >&2
  exit 1
fi
[[ -e "$TX_RECORDS/kid-ada.json" && -e "$TX_ETC/luks-slots.removing-kid-ada" ]]
[[ -e "$TX_STATE/account.kid-ada" && -e "$TX_HOME/home/kid-ada" ]]
[[ -e "$TX_ETC/kids/kid-ada.conf" && -e "$TX_STATE/slot.1" ]]
! grep -q 'luksKillSlot\|userdel' "$TX_LOG"
echo 'PASS invariant non-LUKS intent conflict preserved'

# When the base account is occupied, restart finds the unfinished generated
# suffix instead of allocating another suffix.
tx_fixture_init suffix-retry
make_secrets
: >"$TX_STATE/account.kid-ada"
tx_start_paused add after-transaction-create Ada
[[ -e "$TX_RECORDS/kid-ada-2.json" ]]
tx_kill_paused
tx_add Ada
tx_assert_add_complete kid-ada-2
[[ ! -e "$TX_RECORDS/kid-ada-3.json" && ! -e "$TX_STATE/account.kid-ada-3" ]]
echo 'PASS invariant suffixed retry'

# An account appearing after creating is durable cannot be adopted unless its
# passwd identity exactly matches the recorded shell, home, and groups.
tx_fixture_init unexpected-account
make_secrets
tx_start_paused add after-creating Ada
: >"$TX_STATE/account.kid-ada"
: >"$TX_STATE/bad-account.kid-ada"
tx_release_paused_rc=0
tx_release_paused || tx_release_paused_rc=$?
[[ "$tx_release_paused_rc" != 0 ]]
[[ "$(jq -r .account_state "$TX_RECORDS/kid-ada.json")" == creating ]]
[[ ! -e "$TX_ETC/kids/kid-ada.conf" ]]
echo 'PASS invariant unexpected account rejected'

# Default preservation cannot declare success when both the source and the
# recorded destination are absent.
tx_fixture_init missing-home
make_secrets
tx_add Ada
rm -rf "$TX_HOME/home/kid-ada"
if tx_remove kid-ada >"$TX_CASE/missing-home.out" 2>&1; then
  echo 'missing-home removal unexpectedly succeeded' >&2
  exit 1
fi
[[ "$(jq -r .account_state "$TX_RECORDS/kid-ada.json")" == account_removed ]]
[[ -e "$TX_ETC/kids/kid-ada.conf" ]]
[[ ! -e "$TX_HOME/home/parent/Kids Mode/Ada" ]]
echo 'PASS invariant missing home fails closed'

# Full removal must retain the journal and profile at the same missing-home
# ambiguity instead of purging the only durable retry evidence.
tx_fixture_init full-missing-home
make_secrets
tx_add Ada
rm -rf "$TX_HOME/home/kid-ada"
if tx_env "$TX_FULL_REMOVE" --yes --no-snapshot --luks-device fixture-device \
  >"$TX_CASE/full-missing-home.out" 2>&1; then
  echo 'full missing-home removal unexpectedly succeeded' >&2
  exit 1
fi
[[ -f "$TX_RECORDS/kid-ada.json" ]]
[[ "$(jq -r .account_state "$TX_RECORDS/kid-ada.json")" == account_removed ]]
[[ -e "$TX_ETC/kids/kid-ada.conf" ]]
[[ ! -e "$TX_HOME/home/parent/Kids Mode/Ada" ]]
[[ ! -e "$TX_STATE/kill-without-proof" ]]
echo 'PASS invariant full removal preserves missing-home evidence'

# A retired journal cannot authorize its old number after a later account
# receives that number and a different on-device identity.
tx_fixture_init recycled-slot
make_secrets
tx_add Ada
tx_remove kid-ada
tx_add Cy
[[ "$(jq -r .slot "$TX_RECORDS/kid-cy.json")" == 1 ]]
tx_remove kid-ada
[[ "$(wc -l <"$TX_STATE/kills")" == 1 ]]
[[ -e "$TX_STATE/slot.1" && "$(jq -r .account "$TX_STATE/token.1.json")" == kid-cy ]]
[[ ! -e "$TX_STATE/kill-without-proof" ]]
echo 'PASS invariant recycled slot rejects old identity'

echo 'transaction-invariants-test RESULT: PASS'
