#!/bin/bash
# R-SEC-4, R-FND-2, R-FND-6: kill and restart the real add/remove entry point at durable boundaries.
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

assert_one_add() {
  tx_assert_add_complete kid-ada
  [[ ! -e "$TX_RECORDS/kid-ada-2.json" ]]
  [[ "$(find "$TX_STATE" -name 'slot.*' -type f | wc -l)" == 1 ]]
  [[ "$(find "$TX_STATE" -name 'token.*.json' -type f | wc -l)" == 1 ]]
  [[ "$(grep -c '^1=kid-ada$' "$TX_ETC/luks-slots")" == 1 ]]
}

add_points=(
  before-transaction-create after-transaction-create after-reserved-fsync after-adding
  after-add after-token after-added after-map-rewrite after-useradd
)
for point in "${add_points[@]}"; do
  tx_fixture_init "add-$point"
  make_secrets
  tx_start_paused add "$point" Ada
  record="$TX_RECORDS/kid-ada.json"
  case "$point" in
    before-transaction-create) [[ ! -e "$record" ]] ;;
    after-transaction-create | after-reserved-fsync) [[ "$(jq -r .state "$record")" == reserved ]] ;;
    after-adding) [[ "$(jq -r .state "$record")" == adding && ! -e "$TX_STATE/slot.1" ]] ;;
    after-add) [[ "$(jq -r .state "$record")" == adding && -e "$TX_STATE/slot.1" && ! -e "$TX_STATE/token.1.json" ]] ;;
    after-token) [[ "$(jq -r .state "$record")" == adding && -e "$TX_STATE/token.1.json" ]] ;;
    after-added) [[ "$(jq -r .state "$record")" == added ]] ;;
    after-map-rewrite) [[ "$(grep -c '^1=kid-ada$' "$TX_ETC/luks-slots")" == 1 ]] ;;
    after-useradd) [[ "$(jq -r .account_state "$record")" == creating && -e "$TX_STATE/account.kid-ada" ]] ;;
  esac
  tx_kill_paused

  if [[ "$point" == after-add ]]; then
    set +e
    output="$(tx_add Ada 2>&1)"
    rc=$?
    set -e
    [[ "$rc" == 1 ]]
    [[ "$output" == *"active without matching ownership"* ]]
    [[ -e "$TX_STATE/slot.1" && ! -e "$TX_STATE/token.1.json" ]]
    [[ ! -e "$TX_STATE/kills" && ! -e "$TX_STATE/kill-without-proof" ]]
    [[ ! -e "$TX_STATE/account.kid-ada" ]]
  else
    tx_add Ada
    assert_one_add
  fi
  printf 'PASS crash/restart add %s\n' "$point"
done

remove_points=(after-removing after-unmount after-userdel after-home-move after-kill after-removed)
for point in "${remove_points[@]}"; do
  tx_fixture_init "remove-$point"
  make_secrets
  tx_add Ada
  tx_start_paused remove "$point" kid-ada
  record="$TX_RECORDS/kid-ada.json"
  case "$point" in
    after-removing) [[ "$(jq -r .state "$record")" == removing && -e "$TX_STATE/slot.1" ]] ;;
    after-unmount) [[ "$(jq -r .account_state "$record")" == removing && ! -e "$TX_STATE/mount.kid-ada" ]] ;;
    after-userdel) [[ "$(jq -r .account_state "$record")" == session_removed && ! -e "$TX_STATE/account.kid-ada" ]] ;;
    after-home-move)
      [[ "$(jq -r .account_state "$record")" == account_removed ]]
      [[ ! -e "$TX_HOME/home/kid-ada" && -d "$TX_HOME/home/parent/Kids Mode/Ada" ]]
      ;;
    after-kill) [[ "$(jq -r .state "$record")" == removing && ! -e "$TX_STATE/slot.1" ]] ;;
    after-removed) [[ "$(jq -r .state "$record")" == removed ]] ;;
  esac
  tx_kill_paused
  tx_remove kid-ada
  tx_assert_removed kid-ada
  [[ "$(wc -l <"$TX_STATE/kills")" == 1 ]]
  [[ ! -e "$TX_ETC/kids/kid-ada.conf" ]]
  printf 'PASS crash/restart remove %s\n' "$point"
done

echo "transaction-crash-test RESULT: PASS (${#add_points[@]} add and ${#remove_points[@]} remove command boundaries)"
