#!/bin/bash
# R-SEC-4, R-FND-2, R-FND-6: durable per-account ownership and lifecycle transactions.
set -u

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
source test/shell.d/lib.sh

pass=0
fail=0
check() {
  if "$@"; then
    pass=$((pass + 1))
  else
    echo "FAIL: $*" >&2
    fail=$((fail + 1))
  fi
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -m 700 "$scratch/state"
transactions="$scratch/state/transactions"
manager="lib/transaction.py"
account=kid-ada
device=18ea1ae2-ae5d-4012-9ff4-f071ccccdd01

display='Ada, the "quoted"'
python3 "$manager" create "$transactions" "$account" add "$device" 3 set "$display" 6-8 fox >/dev/null
record="$transactions/$account.json"
check test -f "$record"
check test "$(kids_file_mode "$record")" = 600
check python3 "$manager" validate "$transactions" "$account"
check test "$(python3 "$manager" field "$transactions" "$account" state)" = reserved
check test "$(python3 "$manager" field "$transactions" "$account" account_state)" = planned

check python3 "$manager" create "$transactions" "$account" add "$device" 3 set "$display" 6-8 fox
if python3 "$manager" create "$transactions" "$account" add "$device" 4 set "$display" 6-8 fox >/dev/null 2>&1; then
  echo "FAIL: mismatched idempotent create accepted a different slot" >&2
  fail=$((fail + 1))
else
  pass=$((pass + 1))
fi

owner="$(python3 "$manager" field "$transactions" "$account" owner)"
transaction="$(python3 "$manager" field "$transactions" "$account" transaction)"
check test "${#owner}" = 36
check test "${#transaction}" = 36

check python3 "$manager" transition "$transactions" "$account" reserved adding
check python3 "$manager" transition "$transactions" "$account" adding added
check test "$(python3 "$manager" field "$transactions" "$account" state)" = added

if python3 "$manager" transition "$transactions" "$account" added adding >/dev/null 2>&1; then
  echo "FAIL: invalid reverse transition succeeded" >&2
  fail=$((fail + 1))
else
  pass=$((pass + 1))
fi

token="$(python3 "$manager" token "$transactions" "$account")"
check jq -e --arg a "$account" --arg o "$owner" --arg t "$transaction" \
  '.type == "omarchy-kids" and .schema == 1 and .account == $a and .owner == $o and .transaction == $t and .keyslots == ["3"]' \
  >/dev/null <<<"$token"

python3 "$manager" lifecycle "$transactions" "$account" planned creating >/dev/null
python3 "$manager" lifecycle "$transactions" "$account" creating created >/dev/null
dest="$scratch/Kids Mode/A quote, a backslash \\ and comma"
python3 "$manager" destination "$transactions" "$account" "$dest" >/dev/null
check test "$(python3 "$manager" field "$transactions" "$account" destination)" = "$dest"

cp "$record" "$record.bad"
chmod 666 "$record"
if python3 "$manager" validate "$transactions" "$account" >/dev/null 2>&1; then
  echo "FAIL: writable record accepted" >&2
  fail=$((fail + 1))
else
  pass=$((pass + 1))
fi
mv "$record.bad" "$record"
chmod 600 "$record"

jq '.schema = true' "$record" >"$record.bool"
mv "$record.bool" "$record"
chmod 600 "$record"
if python3 "$manager" validate "$transactions" "$account" >/dev/null 2>&1; then
  echo "FAIL: boolean schema accepted as integer 1" >&2
  fail=$((fail + 1))
else
  pass=$((pass + 1))
fi
jq '.schema = 1' "$record" >"$record.fixed"
mv "$record.fixed" "$record"
chmod 600 "$record"

ln -s "$record" "$transactions/kid-cy.json"
if python3 "$manager" validate "$transactions" kid-cy >/dev/null 2>&1; then
  echo "FAIL: symlink record accepted" >&2
  fail=$((fail + 1))
else
  pass=$((pass + 1))
fi
rm "$transactions/kid-cy.json"

jq '.account = "kid-cy"' "$record" >"$transactions/kid-cy.json"
chmod 600 "$transactions/kid-cy.json"
if python3 "$manager" list "$transactions" >/dev/null 2>&1; then
  echo "FAIL: duplicate transaction and owner identities were accepted" >&2
  fail=$((fail + 1))
else
  pass=$((pass + 1))
fi

echo "$pass passed, $fail failed"
((fail == 0))
