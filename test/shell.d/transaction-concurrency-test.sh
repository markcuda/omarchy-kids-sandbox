#!/bin/bash
# R-SEC-4, R-FND-2, R-FND-6: real add/remove commands contend inside the production writer lock.
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

start_contender() {
  local operation="$1" value="$2"
  TX_ATTEMPT="$TX_CASE/lock-attempt.fifo"
  mkfifo "$TX_ATTEMPT"
  if [[ "$operation" == add ]]; then
    setsid timeout 45 env PATH="$TX_PATH" DRY_RUN=0 OMARCHY_KIDS_ETC="$TX_ETC" \
      OMARCHY_KIDS_SHARE="$TX_REPO/share" OMARCHY_KIDS_ROOT="$TX_ROOT" \
      OMARCHY_KIDS_HOME_ROOT="$TX_HOME" TX_STATE="$TX_STATE" TX_HOME="$TX_HOME" \
      TX_LOG="$TX_LOG" TX_RECORDS="$TX_RECORDS" TX_PAUSE="$TX_STUBS/fixture-pause" \
      FIXTURE_LOCK_ATTEMPT="$TX_ATTEMPT" "$TX_BIN" add "$value" --band 6-8 --avatar fox \
      --password-stdin --parent-password-stdin --luks-device fixture-device \
      <"$TX_SECRETS" >"$TX_CASE/contender.out" 2>&1 &
  else
    setsid timeout 45 env PATH="$TX_PATH" DRY_RUN=0 OMARCHY_KIDS_ETC="$TX_ETC" \
      OMARCHY_KIDS_SHARE="$TX_REPO/share" OMARCHY_KIDS_ROOT="$TX_ROOT" \
      OMARCHY_KIDS_HOME_ROOT="$TX_HOME" TX_STATE="$TX_STATE" TX_HOME="$TX_HOME" \
      TX_LOG="$TX_LOG" TX_RECORDS="$TX_RECORDS" TX_PAUSE="$TX_STUBS/fixture-pause" \
      FIXTURE_LOCK_ATTEMPT="$TX_ATTEMPT" "$TX_BIN" remove "$value" \
      --luks-device fixture-device >"$TX_CASE/contender.out" 2>&1 &
  fi
  TX_SECOND_PID=$!
  TX_ACTIVE_PIDS+=("$TX_SECOND_PID")
  timeout 20 bash -c 'IFS= read -r line <"$1"; [[ "$line" == attempt ]]' _ "$TX_ATTEMPT"
  kill -0 "$TX_SECOND_PID"
}

finish_pair() {
  local first_pid="$TX_PID"
  tx_release_paused
  TX_PID="$first_pid"
  tx_wait_pid "$TX_SECOND_PID"
  rm -f "$TX_ATTEMPT"
}

start_parent_contender() {
  TX_ATTEMPT="$TX_CASE/lock-attempt.fifo"
  mkfifo "$TX_ATTEMPT"
  setsid timeout 45 env PATH="$TX_PATH" DRY_RUN=0 OMARCHY_KIDS_ETC="$TX_ETC" \
    OMARCHY_KIDS_SHARE="$TX_REPO/share" OMARCHY_KIDS_ROOT="$TX_ROOT" \
    OMARCHY_KIDS_HOME_ROOT="$TX_HOME" TX_STATE="$TX_STATE" TX_HOME="$TX_HOME" \
    TX_LOG="$TX_LOG" TX_RECORDS="$TX_RECORDS" TX_PAUSE="$TX_STUBS/fixture-pause" \
    FIXTURE_LOCK_ATTEMPT="$TX_ATTEMPT" "$TX_CONF" machine set parent parent \
    >"$TX_CASE/contender.out" 2>&1 &
  TX_SECOND_PID=$!
  TX_ACTIVE_PIDS+=("$TX_SECOND_PID")
  timeout 20 bash -c 'IFS= read -r line <"$1"; [[ "$line" == attempt ]]' _ "$TX_ATTEMPT"
  kill -0 "$TX_SECOND_PID"
}

# Two adds: the second reaches production flock while the first is inside
# the checked add/header/token interval, and cannot reserve or mutate early.
tx_fixture_init two-adds
make_secrets
tx_start_paused add after-add Ada
start_contender add Cy
[[ ! -e "$TX_RECORDS/kid-cy.json" && ! -e "$TX_STATE/account.kid-cy" ]]
[[ "$(find "$TX_STATE" -name 'slot.*' -type f | wc -l)" == 1 ]]
finish_pair
tx_assert_add_complete kid-ada
tx_assert_add_complete kid-cy
[[ "$(jq -r .slot "$TX_RECORDS/kid-ada.json")" != "$(jq -r .slot "$TX_RECORDS/kid-cy.json")" ]]
echo 'PASS concurrency two-adds'

# Add/remove: remove attempts the lock while another account is between its
# LUKS add and token attachment. Neither identity crosses accounts.
tx_fixture_init add-remove
make_secrets
tx_add Ada
tx_start_paused add after-add Cy
start_contender remove kid-ada
[[ -e "$TX_STATE/account.kid-ada" && -e "$TX_STATE/slot.1" ]]
[[ ! -e "$TX_STATE/kills" ]]
finish_pair
tx_assert_add_complete kid-cy
tx_assert_removed kid-ada
[[ "$(cat "$TX_STATE/kills")" == 1 ]]
echo 'PASS concurrency add-remove'

# Two removes: the second has attempted flock while the first is inside the
# proof/kill interval; each owned stub records exactly its own one kill.
tx_fixture_init two-removes
make_secrets
tx_add Ada
tx_add Cy
tx_start_paused remove after-kill kid-ada
start_contender remove kid-cy
[[ -e "$TX_STATE/account.kid-cy" ]]
[[ "$(wc -l <"$TX_STATE/kills")" == 1 ]]
finish_pair
tx_assert_removed kid-ada
tx_assert_removed kid-cy
[[ "$(sort -n "$TX_STATE/kills")" == $'1\n2' ]]
echo 'PASS concurrency two-removes'

# Reservation: first is durably reserved with an empty slot when the second
# attempts flock. Actual allocation after release must choose another slot.
tx_fixture_init reserved-allocation
make_secrets
tx_start_paused add after-reserved-fsync Ada
start_contender add Cy
[[ "$(jq -r .state "$TX_RECORDS/kid-ada.json")" == reserved ]]
[[ ! -e "$TX_RECORDS/kid-cy.json" ]]
finish_pair
tx_assert_add_complete kid-ada
tx_assert_add_complete kid-cy
[[ "$(jq -r .slot "$TX_RECORDS/kid-ada.json")" == 1 ]]
[[ "$(jq -r .slot "$TX_RECORDS/kid-cy.json")" == 2 ]]
echo 'PASS concurrency reserved-allocation'

# Reconciliation: leave adding+token via an actual killed add. Its actual
# restart reconciles under lock and pauses at added while a writer waits.
tx_fixture_init reconcile-writer
make_secrets
tx_start_paused add after-token Ada
tx_kill_paused
tx_start_paused add after-added Ada
start_contender add Cy
[[ "$(jq -r .state "$TX_RECORDS/kid-ada.json")" == added ]]
[[ ! -e "$TX_RECORDS/kid-cy.json" ]]
finish_pair
tx_assert_add_complete kid-ada
tx_assert_add_complete kid-cy
echo 'PASS concurrency reconcile-writer'

# Derived map: an actual remove pauses after fsyncing the derived map while
# still holding the common lock; the waiting add cannot publish early.
tx_fixture_init derived-map
make_secrets
tx_add Ada
tx_start_paused remove after-map-rewrite kid-ada
start_contender add Cy
[[ "$(grep -c '=kid-ada$' "$TX_ETC/luks-slots" || true)" == 0 ]]
[[ ! -e "$TX_RECORDS/kid-cy.json" ]]
finish_pair
tx_assert_removed kid-ada
tx_assert_add_complete kid-cy
[[ "$(grep -c '=kid-cy$' "$TX_ETC/luks-slots")" == 1 ]]
echo 'PASS concurrency derived-map'

# Parent writer: the actual machine setter reaches the same flock while an
# actual removal holds it across its map rewrite. It cannot publish early.
tx_fixture_init parent-map-writer
make_secrets
tx_add Ada
sed -i '/^0=/d' "$TX_ETC/luks-slots"
tx_start_paused remove after-map-rewrite kid-ada
start_parent_contender
[[ "$(grep -c '^0=parent$' "$TX_ETC/luks-slots" || true)" == 0 ]]
finish_pair
tx_assert_removed kid-ada
[[ "$(cat "$TX_ETC/luks-slots")" == '0=parent' ]]
echo 'PASS concurrency parent-map-writer'

[[ ! -e "$TX_STATE/kill-without-proof" ]]
echo 'transaction-concurrency-test RESULT: PASS (seven production-command contention matrices)'
