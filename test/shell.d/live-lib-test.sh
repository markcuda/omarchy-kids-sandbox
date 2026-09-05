#!/bin/bash
# Tests the pure helpers in test/live/lib.sh — portal tile index/count parsing, the finalized
# journal-report parser, and the report table generator. These are the only parts of the VM
# acceptance harness (issue #31, SPEC.md R-BUILD-3) that don't need the test laptop or the VM, so
# this is the only test/live coverage that runs in `test/all`/CI; the scenarios themselves
# (test/live/NN-*.sh) are exercised by hand against the real VM per docs/live-tests.md, never here.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMP="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Point lib.sh at a scratch out dir and an obviously-fake ssh config, so sourcing it never
# touches this machine's real ~/.ssh or writes anywhere outside $TMP (AGENTS.md rule 8). None of
# the functions this file calls ever shell out to ssh/scp/qmp, so LIVE_SSH_CFG is never read.
export LIVE_OUT_DIR="$TMP/out"
export LIVE_SSH_CFG="$TMP/does-not-exist"

# shellcheck source=test/live/lib.sh
source "$DIR/test/live/lib.sh"
# shellcheck source=lib/conf.sh
source "$DIR/lib/conf.sh"
# shellcheck source=lib/posture.sh
source "$DIR/lib/posture.sh"

fail=0
check() { # got want label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else
    echo "FAIL $3 (want '$2', got '$1')"
    fail=1
  fi
}
check_status() { # got_status want_status label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else
    echo "FAIL $3 (want exit $2, got $1)"
    fail=1
  fi
}

# --- portal_kid_index / portal_kid_count -----------------------------------------------------

CSV="kid-ada:Ada Lovelace:fox,kid-cy:Cy:panda"
QUOTED_CSV="\"$CSV\""

check "$(portal_kid_index "$CSV" kid-ada)" "0" "portal_kid_index: the first kid is index 0"
check "$(portal_kid_index "$CSV" kid-cy)" "1" "portal_kid_index: the second kid is index 1"
check "$(portal_kid_count "$CSV")" "2" "portal_kid_count: two entries"
check "$(portal_kid_index "$QUOTED_CSV" kid-cy)" "1" "portal_kid_index: quoted two-kid value keeps the second kid"
check "$(portal_kid_count "$QUOTED_CSV")" "2" "portal_kid_count: quoted two-kid value has two entries"
TILES=$'kid-ada\nkid-ben\nkid-cy\nkid-vm'
check "$(portal_tile_index "$TILES" kid-cy)" "2" "portal_tile_index: sorted greeter order, third account is index 2"
check "$(portal_tile_index "$TILES" kid-vm)" "3" "portal_tile_index: the parent sorts last here"
portal_tile_index "$TILES" kid-zed >/dev/null && fail "portal_tile_index: unknown account should fail" || echo "ok   portal_tile_index: unknown account fails"

portal_kid_index "$CSV" kid-nope >/dev/null 2>&1
check_status "$?" "1" "portal_kid_index: an account not in the list fails"

check "$(portal_kid_index "kid-ada:Ada:fox" kid-ada)" "0" "portal_kid_index: a single kid is index 0"
check "$(portal_kid_count "kid-ada:Ada:fox")" "1" "portal_kid_count: one entry"

check "$(portal_kid_count "")" "0" "portal_kid_count: no kids= value yet is zero kids"
portal_kid_index "" kid-ada >/dev/null 2>&1
check_status "$?" "1" "portal_kid_index: no kids= value yet always fails"

PARENTS="kid-vm,parent-helper"
QUOTED_PARENTS="\"$PARENTS\""
check "$(portal_conf_accounts "$CSV" "$PARENTS")" \
  $'kid-ada\nkid-cy\nkid-vm\nparent-helper' \
  "portal_conf_accounts: kids precede the explicit parent allowlist"
check "$(portal_conf_accounts "kid-ada:Ada Lovelace:fox" "kid-ada,parent-helper")" \
  $'kid-ada\nparent-helper' \
  "portal_conf_accounts: duplicate kid/parent membership produces one tile"
check "$(portal_conf_tile_count "$CSV" "$PARENTS")" "4" \
  "portal_conf_tile_count: counts profiled kids plus parents"
check "$(portal_conf_accounts "$QUOTED_CSV" "$QUOTED_PARENTS")" \
  $'kid-ada\nkid-cy\nkid-vm\nparent-helper' \
  "portal_conf_accounts: quoted lists preserve every account"
check "$(portal_conf_tile_count "$QUOTED_CSV" "$QUOTED_PARENTS")" "4" \
  "portal_conf_tile_count: quoted lists keep all four tiles"
check "$(portal_conf_unquote 'already\\decoded')" 'already\\decoded' \
  "portal_conf_unquote: an already-decoded value is not unescaped twice"

PORTAL_CONF="$TMP/theme.conf.user"
cat >"$PORTAL_CONF" <<'EOF'
[General]
parent=kid-vm
parents="kid-vm"
kids="kid-ada:Ada Lovelace:fox,kid-cy:Cy:panda"
EOF
conf="$(cat "$PORTAL_CONF")"
kids="$(portal_conf_field "$conf" kids)"
parents="$(portal_conf_field "$conf" parents)"
check "$kids" "$CSV" "theme.conf.user: reads back the complete two-kid list"
check "$(portal_conf_accounts "$kids" "$parents")" $'kid-ada\nkid-cy\nkid-vm' \
  "theme.conf.user: both written kids and the parent survive readback"

OMARCHY_KIDS_ROOT="$TMP/roundtrip-root"
OMARCHY_KIDS_HOME_ROOT="$TMP/roundtrip-home"
export OMARCHY_KIDS_ROOT OMARCHY_KIDS_HOME_ROOT
ROUNDTRIP_NAMES=(
  'Ada, Jr'
  'Ada: Cy'
  'Ada "Cy" \kid'
  $'Ada\rCy'
  $'Ada%2C, Cy: "kid" \\ \r'
)
for ROUNDTRIP_NAME in "${ROUNDTRIP_NAMES[@]}"; do
  posture_write_portal_conf kid-vm \
    "$(printf 'kid-ada\t%s\tfox' "$ROUNDTRIP_NAME")" \
    "$(printf 'kid-cy\tCy\towl')"
  ROUNDTRIP_CONF="$OMARCHY_KIDS_ROOT/usr/share/sddm/themes/omarchy-kids/theme.conf.user"
  conf="$(cat "$ROUNDTRIP_CONF")"
  kids="$(portal_conf_field "$conf" kids)"
  check "$(portal_kid_name "$kids" kid-ada)" "$ROUNDTRIP_NAME" \
    "theme.conf.user: adversarial display name survives writer-reader round trip"
  check "$(portal_kid_name "$kids" kid-cy)" "Cy" \
    "theme.conf.user: second kid survives adversarial-name readback"
  check "$(portal_kid_count "$kids")" "2" \
    "theme.conf.user: adversarial display name preserves both kids"
done
check "$(grep '^kids=' "$ROUNDTRIP_CONF")" \
  'kids="kid-ada:Ada%252C%2C Cy%3A \"kid\" \\ \r:fox,kid-cy:Cy:owl"' \
  "theme.conf.user: payload encoding precedes exact QSettings escaping"
unset OMARCHY_KIDS_ROOT OMARCHY_KIDS_HOME_ROOT
check "$(portal_parse_tile_report 'qrc:/Main.qml: portal: 3 tiles (kids=2 parents=1)')" "3 2 1" \
  "portal_parse_tile_report: extracts the greeter's observed finalized counts"
portal_parse_tile_report "portal: malformed" >/dev/null 2>&1
check_status "$?" "1" "portal_parse_tile_report: malformed journal output fails"

# --- report_header / report_row ---------------------------------------------------------------

expected_header="| Scenario | Result | Screenshots |
| --- | --- | --- |"
check "$(report_header)" "$expected_header" "report_header: the fixed Markdown table header"

check "$(report_row 10-cold-boot-kid PASS 10-cold-boot-kid.png)" \
  "| 10-cold-boot-kid | PASS | 10-cold-boot-kid.png |" \
  "report_row: name, result, one screenshot"

check "$(report_row 30-portal-login-and-finish PASS 30-launcher.png,30-after-finish.png)" \
  "| 30-portal-login-and-finish | PASS | 30-launcher.png,30-after-finish.png |" \
  "report_row: multiple screenshots stay comma-joined"

check "$(report_row 90-remove FAIL "")" \
  "| 90-remove | FAIL | — |" \
  "report_row: no screenshots falls back to an em dash"

# --- ok / fail / scenario_result's PASS/FAIL line contract -------------------------------------
# (scenario_result itself calls `exit`, so it's exercised as a subshell here rather than called
# directly — the same reason test/shell.d never calls a command's own `exit` inline either.)

out="$(
  LIVE_FAIL=0
  ok "a check"
  scenario_result some-scenario
)"
status=$?
check "$out" "ok   a check
PASS some-scenario" "scenario_result: an all-ok run prints PASS"
check_status "$status" "0" "scenario_result: an all-ok run exits 0"

out="$(
  LIVE_FAIL=0
  ok "a check"
  fail "a broken check"
  scenario_result some-scenario
)"
status=$?
check "$out" "ok   a check
FAIL a broken check
FAIL some-scenario" "scenario_result: any fail prints FAIL"
check_status "$status" "1" "scenario_result: any fail exits 1"

exit $fail
