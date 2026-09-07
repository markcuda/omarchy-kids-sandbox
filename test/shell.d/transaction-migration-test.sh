#!/bin/bash
# R-SEC-4, R-FND-6: legacy state migrates only with exact ownership proof.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
source lib/conf.sh
source lib/kids.sh
LIB="$PWD/lib"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
ETC="$scratch/etc/omarchy-kids"
KIDS_DIR="$ETC/kids"
SLOTS_FILE="$ETC/luks-slots"
TRANSACTIONS_DIR="$scratch/var/lib/omarchy-kids/transactions"
mkdir -p "$KIDS_DIR" "${TRANSACTIONS_DIR%/*}"
chmod 0700 "${TRANSACTIONS_DIR%/*}"
printf 'name=Ada\nband=6-8\navatar=fox\npassword=set\n' >"$KIDS_DIR/kid-ada.conf"
printf 'name=Cy\nband=6-8\navatar=bear\npassword=set\n' >"$KIDS_DIR/kid-cy.conf"
printf 'name=Dot\nband=3-5\navatar=fox\npassword=none\n' >"$KIDS_DIR/kid-dot.conf"
printf '0=parent\n3=kid-ada\n4=kid-cy\n' >"$SLOTS_FILE"

FIXTURE_DEVICE_UUID=18ea1ae2-ae5d-4012-9ff4-f071ccccdd01
FIXTURE_TOKEN='{"type":"omarchy-kids","keyslots":["3"],"account":"kid-ada","transaction":"11111111-1111-4111-8111-111111111111","owner":"22222222-2222-4222-8222-222222222222","device_uuid":"18ea1ae2-ae5d-4012-9ff4-f071ccccdd01","slot":3,"schema":1}'
cryptsetup() {
  case "$1" in
    luksUUID) printf '%s\n' "$FIXTURE_DEVICE_UUID" ;;
    luksDump) printf '{"tokens":{"0":%s}}\n' "$FIXTURE_TOKEN" ;;
    luksKillSlot)
      : >"$scratch/kill-called"
      return 1
      ;;
    *) return 1 ;;
  esac
}

mkdir -m 700 "$TRANSACTIONS_DIR"
luks_migrate_legacy_account_locked fixture-device kid-ada
python3 lib/transaction.py validate "$TRANSACTIONS_DIR" kid-ada
[[ "$(luks_transaction_field kid-ada state)" == added ]]
[[ "$(luks_transaction_field kid-ada slot)" == 3 ]]
[[ "$(luks_transaction_field kid-ada owner)" == 22222222-2222-4222-8222-222222222222 ]]

if luks_migrate_legacy_account_locked fixture-device kid-cy 2>/dev/null; then
  echo "FAIL: untagged legacy slot migrated from its map number" >&2
  exit 1
fi
[[ ! -e "$TRANSACTIONS_DIR/kid-cy.json" ]]
[[ ! -e "$scratch/kill-called" ]]
grep -qxF '4=kid-cy' "$SLOTS_FILE"

account_migrate_profile_locked kid-dot
python3 lib/transaction.py validate "$TRANSACTIONS_DIR" kid-dot
[[ "$(luks_transaction_field kid-dot luks_mode)" == none ]]
[[ -z "$(luks_transaction_field kid-dot slot)" ]]

echo "transaction-migration-test RESULT: PASS"
