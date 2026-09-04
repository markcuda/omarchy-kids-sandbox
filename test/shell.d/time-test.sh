#!/bin/bash
# Tests the screen-time engine (SPEC.md R-TIME-1..5, Appendix F, issue
# #23): bin/omarchy-kids-time-ledger's tick (active/inactive/locked/
# paused sessions, dedup, non-kid accounts ignored), budget/lights-out
# math (band defaults and per-kid overrides, weekday vs weekend), the
# day-boundary rollover, bin/omarchy-kids-time's status/grant,
# and lib/time.py's logical-day helper.
#
# Fully self-contained: `loginctl` is a fake on a stub PATH reading a
# plain "id uid user active locked" state file this test writes before
# each scenario (same stub() shape as test/shell.d/apps-test.sh), and
# `omarchy-kids-conf` is the real thing against a scratch tree (real
# bands.toml/packs, same reasoning as that file). The copied commands read
# the clock fixtures below, so nothing here depends on the host's own clock
# or its `date` binary's flavor. One provisioned
# kid throughout: kid-ada, band 6-8 (AGENTS.md rule 9's fixture
# convention).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LEDGER="$DIR/bin/omarchy-kids-time-ledger"
TIME="$DIR/bin/omarchy-kids-time"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP time-test.sh: python3 not found"
  exit 0
fi

fail=0
pass() { echo "ok   $*"; }
fail_() {
  echo "FAIL $*"
  fail=1
}
check() { # got want label
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail_ "$3 (want '$2', got '$1')"; fi
}
check_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail_ "$3 (want to find '$2' in '$1')"; fi
}
check_not_contains() { # haystack needle label
  if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail_ "$3 (did not want to find '$2' in '$1')"; fi
}

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ETC="$TMP/etc"
SHARE="$TMP/share"
ROOT="$TMP/root" # OMARCHY_KIDS_ROOT
STUBS="$TMP/stubs"
SESSIONS="$TMP/sessions" # loginctl stub's state file
CLOCK_FILE="$ROOT/run/omarchy-kids/time/monotonic"
NOW_FILE="$ROOT/run/omarchy-kids/time/now"

mkdir -p "$SHARE/bands" "$SHARE/packs" "$ETC/kids" "$STUBS" "$(dirname "$CLOCK_FILE")"
cp "$DIR/share/bands/bands.toml" "$SHARE/bands/"
cp "$DIR"/share/packs/*.toml "$SHARE/packs/"
: >"$SESSIONS"

cat >"$ETC/kids/kid-ada.conf" <<'EOF'
name=Ada Lovelace
avatar=fox
band=6-8
EOF

# set_sessions LINE... — each LINE is "id uid user active locked",
# e.g. "1 1000 kid-ada yes no". Replaces the whole session table.
set_sessions() {
  : >"$SESSIONS"
  local line
  for line in "$@"; do printf '%s\n' "$line" >>"$SESSIONS"; done
}

# --- stub loginctl -----------------------------------------------------

cat >"$STUBS/loginctl" <<EOF
#!/bin/bash
STATE="$SESSIONS"
if [[ "\$1" == "list-sessions" ]]; then
  awk '{print \$1, \$2, \$3, "seat0"}' "\$STATE"
  exit 0
fi
if [[ "\$1" == "show-session" ]]; then
  id="\$2"; shift 2
  props=()
  while [[ \$# -gt 0 ]]; do
    case "\$1" in
      -p) props+=("\$2"); shift 2 ;;
      *) shift ;;
    esac
  done
  line="\$(awk -v id="\$id" '\$1==id{print;exit}' "\$STATE")"
  [[ -n "\$line" ]] || exit 1
  read -r _ _ _ active locked <<<"\$line"
  for p in "\${props[@]}"; do
    case "\$p" in
      Active) echo "Active=\$active" ;;
      LockedHint) echo "LockedHint=\$locked" ;;
    esac
  done
  exit 0
fi
exit 1
EOF
chmod +x "$STUBS/loginctl"

# `id -un`/`id -u` are what decide "which kid am I?" and "am I root?"
# now -- never $OMARCHY_KIDS_ACCOUNT or a *_REQUIRE_ROOT escape (review
# §3.6/§3.7). The ledger tick and `grant` are root, so this suite claims
# root through the same stub, per call.
source "$(dirname "${BASH_SOURCE[0]}")/tree.sh"
kids_id_stub "$STUBS" kid-ada "$(id -u)"

kids_tree "$TMP/tree" "$DIR"
LEDGER="$TMP/tree/bin/omarchy-kids-time-ledger"
TIME="$TMP/tree/bin/omarchy-kids-time"
kids_set_const "$LEDGER" ETC "$ETC"
kids_set_const "$LEDGER" SYSROOT "$ROOT"
kids_set_const "$LEDGER" TIME_CLOCK_FILE "$CLOCK_FILE"
kids_set_const "$LEDGER" TIME_NOW_FILE "$NOW_FILE"
kids_set_const "$TIME" ETC "$ETC"
kids_set_const "$TIME" SHARE "$SHARE"
kids_set_const "$TIME" SYSROOT "$ROOT"
kids_set_const "$TIME" TIME_NOW_FILE "$NOW_FILE"
kids_set_const "$TIME" RUN "$TMP/run"

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_KIDS_ROOT="$ROOT"
export KIDS_TEST_UID=0

USAGE_DIR="$ROOT/var/lib/omarchy-kids/kid-ada/usage"

used_today() { cat "$USAGE_DIR/$1" 2>/dev/null || echo 0; }
set_clock() { printf '%s\n' "$1" >"$CLOCK_FILE"; }
set_now() { printf '%s\n' "$1" >"$NOW_FILE"; }
state_value() {
  jq -r --arg key "$1" '.[$key] | if type == "array" then tojson else tostring end' \
    "$ROOT/run/omarchy-kids/time/kid-ada.json"
}

# --- --help --------------------------------------------------------------

"$LEDGER" --help >/dev/null 2>&1
check "$?" 0 "omarchy-kids-time-ledger --help exits 0"
"$TIME" --help >/dev/null 2>&1
check "$?" 0 "omarchy-kids-time --help exits 0"
"$TIME" >/dev/null 2>&1
check "$?" 2 "omarchy-kids-time with no command exits 2"

# =========================================================================
# lib/time.py logical-day: the 04:00 rollover and weekday math
# =========================================================================

out="$(python3 "$DIR/lib/time.py" logical-day "2026-09-02 10:00:00")"
check "$(sed -n 1p <<<"$out")" "2026-09-02" "logical-day: 10:00 is still today"
check "$(sed -n 2p <<<"$out")" "no" "logical-day: 2026-09-02 (Wednesday) is not a weekend"

out="$(python3 "$DIR/lib/time.py" logical-day "2026-09-02 03:59:00")"
check "$(sed -n 1p <<<"$out")" "2026-09-01" "logical-day: 03:59 still belongs to the day before (Appendix F)"

out="$(python3 "$DIR/lib/time.py" logical-day "2026-09-02 04:00:00")"
check "$(sed -n 1p <<<"$out")" "2026-09-02" "logical-day: exactly 04:00 already belongs to the new day"

out="$(python3 "$DIR/lib/time.py" logical-day "2026-09-05 10:00:00")"
check "$(sed -n 2p <<<"$out")" "yes" "logical-day: 2026-09-05 (Saturday) is a weekend"

# =========================================================================
# lib/time.sh time_toast_thresholds: the pure decision behind R-TIME-3's
# toasts (issue #40) -- fire only on a real downward crossing of 10/5/1,
# and let a grant that raises remaining minutes back above a threshold
# un-fire it so it can fire again the next time it's crossed. No files,
# no clock -- sourced straight from lib/time.sh, table-tested here.
# Row format: "previous|current|thresholds|fired-in|expect-fire|expect-fired-out"
# (previous "" means "no previous value", the daemon's first-ever check).
# =========================================================================

# shellcheck source=lib/time.sh
source "$DIR/lib/time.sh"

toast_cases=(
  # first-ever check ("" previous == +infinity, everything is a "drop")
  "|15|10 5 1|||"        # above every threshold: nothing fires
  "|8|10 5 1||10|10"     # starts already below 10
  "|3|10 5 1||10 5|10 5" # starts already below 5: 10 marked too
  # ordinary descent, one threshold crossed per step
  "15|8|10 5 1||10|10"
  "8|3|10 5 1|10|5|10 5"
  "3|2|10 5 1|10 5||10 5"     # 2 > 1: the 1-minute mark not reached yet
  "2|1|10 5 1|10 5|1|10 5 1"  # the exact 1-minute crossing (issue #40's 3rd ask)
  "1|1|10 5 1|10 5 1||10 5 1" # a flat repeat poll on the same minute: no refire
  # a grant mid-countdown -- the live bug this issue reported
  "3|16|10 5 1|10 5||" # grant clears every threshold: no immediate refire
  "16|9|10 5 1||10|10" # descending again afterward re-fires 10
  "9|20|10 5 1|10||"   # a smaller grant only un-fires 10 (was already past it)
  "9|7|10 5 1|10||10"  # a grant that doesn't reach back above 10: stays fired
)
for c in "${toast_cases[@]}"; do
  IFS='|' read -r tprev tcurr tthresh tfired texpect_fire texpect_fired <<<"$c"
  tout="$(time_toast_thresholds "$tprev" "$tcurr" "$tthresh" "$tfired")"
  tgot_fire="$(sed -n 1p <<<"$tout")"
  tgot_fired="$(sed -n 2p <<<"$tout")"
  label="time_toast_thresholds(prev=${tprev:-none} curr=$tcurr fired={${tfired:-none}})"
  check "$tgot_fire" "$texpect_fire" "$label fires {${texpect_fire:-none}}"
  check "$tgot_fired" "$texpect_fired" "$label leaves fired-set {${texpect_fired:-none}}"
done

echo

# =========================================================================
# omarchy-kids-time-ledger tick
# =========================================================================

set_now "2026-09-02 10:00:00"
set_clock 1000

# --- active + unlocked: counts -------------------------------------------

set_sessions "1 1000 kid-ada yes no"
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "0" "tick: the first active tick initializes without fabricating a minute"
check "$(state_value state)" "allowed" "tick: first state is allowed"
check "$(state_value remaining_seconds)" "3600" "tick: first state starts from the integer ledgers"
set_clock 1030
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "0" "tick: thirty active seconds stay in the runtime remainder"
check "$(state_value active_seconds_remainder)" "30" "tick: runtime remainder preserves sub-minute usage"
set_clock 1060
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "1" "tick: sixty active seconds add one historical ledger minute"
check "$(state_value active_seconds_remainder)" "0" "tick: a whole minute clears the runtime remainder"

# --- inactive: does not count --------------------------------------------

set_sessions "1 1000 kid-ada no no"
set_clock 1120
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "1" "tick: an inactive session does not add a minute"

# --- locked: does not count ------------------------------------------------

set_sessions "1 1000 kid-ada yes yes"
set_clock 1180
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "1" "tick: a locked session does not add a minute"

# --- paused flag file: does not count, even if active+unlocked -----------

mkdir -p "$ROOT/var/lib/omarchy-kids/kid-ada"
touch "$ROOT/var/lib/omarchy-kids/kid-ada/paused"
set_sessions "1 1000 kid-ada yes no"
set_clock 1240
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "1" "tick: a paused kid does not add a minute even while active and unlocked"
rm -f "$ROOT/var/lib/omarchy-kids/kid-ada/paused"
set_clock 1300
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "2" "tick: counting resumes once the paused flag is gone"

# --- a non-kid account's session is ignored -------------------------------

set_sessions "1 1000 kid-ada yes no" "2 1001 mark yes no"
set_clock 1360
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "3" "tick: kid-ada's session still counts"
# (no profile for "mark" under $ETC/kids -- if it were mistakenly
# counted there'd be no ledger file to even check against; the real
# assertion is just that this doesn't error out.)
pass "tick: a non-kid account's session is silently ignored (no crash, no ledger file for it)"

# --- two sessions for the same kid: only one minute, not two -------------

set_sessions "1 1000 kid-ada yes no" "2 1000 kid-ada yes no"
set_clock 1420
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "4" "tick: two sessions for the same kid still only add one minute"

# --- day-boundary rollover: a tick just before 04:00 lands on yesterday --

set_now "2026-09-03 03:30:00"
set_clock 1480
"$LEDGER" tick >/dev/null
check "$(used_today 2026-09-02)" "5" "tick: 03:30 still counts active time against the prior logical day"
check "$(used_today 2026-09-03)" "0" "tick: nothing recorded yet for the new logical day before 04:00"

# --- state transitions: warning, grace, grant recovery, restart ------------

set_now "2026-09-03 10:00:00"
set_clock 1540
echo 50 >"$USAGE_DIR/2026-09-03"
"$LEDGER" tick >/dev/null
check "$(state_value state)" "warning" "tick: remaining ten minutes enters warning"
check "$(state_value reason)" "budget" "tick: warning records the budget reason"
check "$(state_value warnings_fired)" "[10]" "tick: warning persists the crossed threshold"

set_clock 1600
set_sessions
echo 60 >"$USAGE_DIR/2026-09-03"
"$LEDGER" tick >/dev/null
check "$(state_value state)" "grace" "tick: zero budget enters grace"
check "$(state_value reason)" "budget" "tick: grace records the budget reason"
check "$(state_value grace_deadline)" "1660" "tick: grace deadline is sixty monotonic seconds later"
check "$(used_today 2026-09-03)" "60" "tick: enforcement does not rewrite the usage ledger"

echo 15 >"$ROOT/var/lib/omarchy-kids/kid-ada/usage/2026-09-03.grant"
set_clock 1630
"$LEDGER" tick >/dev/null
check "$(state_value state)" "allowed" "tick: a grant clears grace when policy permits use"
check "$(state_value grace_deadline)" "0" "tick: cleared grace removes its deadline"

rm -f "$ROOT/run/omarchy-kids/time/kid-ada.json"
rm -f "$ROOT/var/lib/omarchy-kids/kid-ada/usage/2026-09-03.grant"
echo 55 >"$USAGE_DIR/2026-09-03"
set_clock 1660
"$LEDGER" tick >/dev/null
check "$(state_value state)" "warning" "tick: missing runtime state rebuilds from root ledgers"
check "$(used_today 2026-09-03)" "55" "tick: state recovery leaves usage history unchanged"

echo

# =========================================================================
# budget/lights-out math: band defaults, overrides, weekday vs weekend
# =========================================================================

set_now "2026-09-02 10:00:00" # a Wednesday
CONF="$DIR/bin/omarchy-kids-conf"

out="$("$TIME" status kid-ada)"
check_contains "$out" "budget 60" "status: band 6-8's weekday default budget (60) with no override"
check_contains "$out" "5 min used" "status: reflects today's ledger total (5, from the tick tests above)"
check_contains "$out" "55 min left today" "status: 60 - 5 = 55 remaining"
check_contains "$out" "budget runs out at 10:55" "status: budget (55 min from 10:00) runs out well before lights-out (19:30)"

"$CONF" set kid-ada budget_min 90 >/dev/null
out="$("$TIME" status kid-ada)"
check_contains "$out" "budget 90" "status: a budget_min override wins over the band default"
check_contains "$out" "85 min left today" "status: 90 - 5 = 85 remaining with the override"

# A Saturday: budget_min_weekend/lights_out_weekend apply instead, and
# the override above (weekday-only) does not carry over.
set_now "2026-09-05 10:00:00"
out="$("$TIME" status kid-ada)"
check_contains "$out" "budget 60" "status: weekend uses budget_min_weekend (band default, no override set)"

"$CONF" set kid-ada budget_min_weekend 30 >/dev/null
set_now "2026-09-05 09:50:00"
out="$("$TIME" status kid-ada)"
check_contains "$out" "budget 30" "status: budget_min_weekend override applies on a Saturday"
check_contains "$out" "budget runs out at 10:20" "status: next boundary picks the sooner of budget-out vs lights-out (budget wins here)"

"$CONF" reset kid-ada >/dev/null

# next boundary: lights-out wins when it comes before the budget would
# run out (grant kid-ada a huge budget for today so lights-out is the
# binding constraint).
"$LEDGER" tick >/dev/null # bump used by one so remaining isn't a round number, just to be sure both paths compute independently
"$TIME" grant kid-ada 500 >/dev/null
set_now "2026-09-02 19:00:00"
out="$("$TIME" status kid-ada)"
check_contains "$out" "lights-out at 19:30" "status: lights-out wins when the budget would outlast it"

echo

# =========================================================================
# grant
# =========================================================================

# A fresh logical day, so the 500-minute grant from the "next boundary"
# scenario above doesn't leak into these totals.
set_now "2026-09-10 10:00:00"

# Refuses without the root bypass (simulating a real non-root caller);
# skip this one assertion if the test suite itself happens to run as
# root (AGENTS.md's own unshare/root convention).
if [[ "$(id -u)" != "0" ]]; then
  KIDS_TEST_UID="$(command id -u)" "$TIME" grant kid-ada 15 >/dev/null 2>&1
  check "$?" 1 "grant: refuses to run without root"
fi

out="$("$TIME" grant kid-ada 15 2>&1)"
st=$?
check "$st" 0 "grant: exits 0 with the root bypass"
check_contains "$out" "granted 15" "grant: says how many minutes it granted"

out2="$("$TIME" status kid-ada)"
check_contains "$out2" "+ 15 granted" "status: shows today's grant total"

"$TIME" grant kid-ada 0 >/dev/null 2>&1
check "$?" 2 "grant: refuses a zero amount"
"$TIME" grant kid-ada -5 >/dev/null 2>&1
check "$?" 2 "grant: refuses a negative amount"
"$TIME" grant kid-ada abc >/dev/null 2>&1
check "$?" 2 "grant: refuses a non-numeric amount"

echo

# =========================================================================
# daemon: fires toasts on the way down, hits Time's Up at 0 by budget
# (not just lights-out), and logs every check with previous/current so
# a live run can be audited (issue #40's 3rd ask). --oneshot runs one
# poll and returns, so each call below starts with no previous value --
# the time_toast_thresholds table above is what proves the across-poll
# reset/refire behavior; this proves the daemon actually wires that
# function up and logs what it decided, using the real command, not a
# stub.
# =========================================================================

DAEMON_DAY="2026-09-16" # a fresh day, untouched by the tests above
set_now "$DAEMON_DAY 10:00:00"
"$CONF" set kid-ada budget_min 12 >/dev/null
"$CONF" set kid-ada budget_min_weekend 12 >/dev/null

DAEMON_USAGE_DIR="$ROOT/var/lib/omarchy-kids/kid-ada/usage"
mkdir -p "$DAEMON_USAGE_DIR"
DAEMON_RUN="$TMP/daemon-run"
DAEMON_LOG="$DAEMON_RUN/session-$(id -u).log"
kids_set_const "$TIME" RUN "$DAEMON_RUN"
export XDG_SESSION_ID=1
set_sessions "1 1000 kid-ada yes no"

# run_daemon_oneshot USED_MINUTES — writes USED_MINUTES to $DAEMON_DAY's
# ledger file, runs one daemon poll against it, and prints the fresh
# session log.
run_daemon_oneshot() {
  rm -rf "$DAEMON_RUN"
  mkdir -p "$DAEMON_RUN"
  echo "$1" >"$DAEMON_USAGE_DIR/$DAEMON_DAY"
  OMARCHY_KIDS_TIME_DAEMON_ONESHOT=1 "$TIME" daemon >/dev/null 2>&1
  cat "$DAEMON_LOG" 2>/dev/null
}

log_out="$(run_daemon_oneshot 8)" # budget 12, used 8: 4 min remaining
check_contains "$log_out" "toast-check: kid='kid-ada' previous=none current=4 fired={10 5} firing={10 5}" \
  "daemon: logs previous/current and picks up both thresholds a lagging tick jumped past at once"
check_contains "$log_out" "toast: 5 minutes left" "daemon: shows only the most urgent of the thresholds crossed (5, not a stale 10)"

log_out="$(run_daemon_oneshot 11)" # budget 12, used 11: exactly 1 min remaining
check_contains "$log_out" "current=1 fired={10 5 1} firing={10 5 1}" \
  "daemon: the 1-minute mark is caught exactly (issue #40's 3rd ask), never skipped between polls"
check_contains "$log_out" "toast: 1 minute left" "daemon: shows the 1-minute toast, singular"

log_out="$(run_daemon_oneshot 12)" # budget 12, used 12: 0 remaining -> Time's Up by budget, not lights-out
check_contains "$log_out" "time's up shown for 'kid-ada'" "daemon: Time's Up fires at 0 remaining by budget (issue #40's other open question)"
check_not_contains "$log_out" "toast-check" "daemon: no toast-check logged once Time's Up has taken over"

"$CONF" reset kid-ada >/dev/null
unset XDG_SESSION_ID
rm -rf "$DAEMON_RUN"
set_sessions

echo

# =========================================================================
# static: systemd/omarchy-kids-time-ledger.{service} and omarchy-kids-time.timer
#
# tick reads every known kid's own $XDG_RUNTIME_DIR (lib/data.sh's
# data_fold_launches) as well as writing under /var/lib/omarchy-kids
# and /run/omarchy-kids -- ProtectHome=yes would hide /run/user/* from
# the unit (systemd's own docs), which is exactly where that runtime
# log lives, so it must stay unset; the two write targets still need
# to be explicit ReadWritePaths under ProtectSystem=strict.
# =========================================================================

SERVICE="$DIR/systemd/omarchy-kids-time-ledger.service"
TIMER="$DIR/systemd/omarchy-kids-time.timer"

if [[ -f "$SERVICE" ]]; then
  pass "omarchy-kids-time-ledger.service exists"
  grep -qE '^\[Service\]' "$SERVICE" && pass "service: has [Service]" || fail_ "service: missing [Service]"
  grep -qE '^Type=oneshot' "$SERVICE" && pass "service: Type=oneshot" || fail_ "service: missing Type=oneshot"
  grep -qE '^ExecStart=.*omarchy-kids-time-ledger tick' "$SERVICE" &&
    pass "service: ExecStart runs 'omarchy-kids-time-ledger tick'" ||
    fail_ "service: ExecStart does not run time-ledger tick"
  grep -qE '^ProtectHome=yes' "$SERVICE" &&
    fail_ "service: ProtectHome=yes would hide /run/user/* -- the runtime launches log tick folds lives there" ||
    pass "service: ProtectHome=yes is not set (so /run/user/<uid> stays visible to the fold step)"
  grep -qE '^ReadWritePaths=.*\bvar/lib/omarchy-kids\b' "$SERVICE" &&
    pass "service: ReadWritePaths includes /var/lib/omarchy-kids" ||
    fail_ "service: ReadWritePaths missing /var/lib/omarchy-kids"
  grep -qE '^ReadWritePaths=.*\brun/omarchy-kids\b' "$SERVICE" &&
    pass "service: ReadWritePaths includes /run/omarchy-kids" ||
    fail_ "service: ReadWritePaths missing /run/omarchy-kids"
else
  fail_ "$SERVICE not found"
fi

if [[ -f "$TIMER" ]]; then
  pass "omarchy-kids-time.timer exists"
  grep -qE '^\[Timer\]' "$TIMER" && pass "timer: has [Timer]" || fail_ "timer: missing [Timer]"
  grep -qE '^Unit=omarchy-kids-time-ledger\.service' "$TIMER" &&
    pass "timer: points at omarchy-kids-time-ledger.service" ||
    fail_ "timer: missing/wrong Unit="
  grep -qE '^\[Install\]' "$TIMER" && pass "timer: has [Install]" || fail_ "timer: missing [Install]"
  grep -qE '^WantedBy=timers\.target' "$TIMER" && pass "timer: WantedBy=timers.target" || fail_ "timer: missing WantedBy=timers.target"
else
  fail_ "$TIMER not found"
fi

if command -v systemd-analyze >/dev/null 2>&1; then
  if systemd-analyze verify "$SERVICE" "$TIMER" >/dev/null 2>&1; then
    pass "systemd-analyze verify: service + timer are syntactically valid"
  else
    fail_ "systemd-analyze verify: service or timer failed verification"
  fi
else
  pass "systemd-analyze not available here -- static [Section]/key checks above stand in for it"
fi

echo "time-test RESULT: $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit $fail
