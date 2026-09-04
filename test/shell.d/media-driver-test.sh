#!/bin/bash
# Tests scripts/media-driver.sh (docs/GOAL.md item 3, SPEC.md R-BUILD-3): defaults,
# one-surface runs, failure continuation, command order, and state restoration.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail=0
pass() { echo "ok   $1"; }
fail_() {
  echo "FAIL $1"
  fail=1
}
check() {
  if [[ "$1" == "$2" ]]; then pass "$3"; else
    fail_ "$3 (want '$2', got '$1')"
  fi
}
check_contains() {
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else
    fail_ "$3 (missing '$2')"
  fi
}

make_fixture() {
  local root="$1"
  mkdir -p "$root/scripts" "$root/test/live" "$root/docs/media"
  cp "$DIR/scripts/media-driver.sh" "$root/scripts/media-driver.sh"
  chmod +x "$root/scripts/media-driver.sh"
  cat >"$root/test/live/lib.sh" <<'EOF'
LIVE_OWNER_PASSWORD=owner-password
LIVE_OWNER_ACCOUNT=kid-test
LIVE_KID1_ACCOUNT=kid-cy
LIVE_KID1_PASSWORD=kid-password
: "${MEDIA_TEST_LOG:?}"
if [[ -n "${MEDIA_TEST_WRONG_OUT:-}" ]]; then
  LIVE_OUT_DIR="$MEDIA_TEST_WRONG_OUT"
  mkdir -p "$LIVE_OUT_DIR"
fi
log() { printf '%s\n' "$*" >>"$MEDIA_TEST_LOG"; }
sleep() { :; }
boot_with() { log "boot_with $*"; }
portal_login() { log "portal_login $*"; }
wait_kid_ready() { log "wait_kid_ready $*"; }
portal_reset() { log "portal_reset $*"; }
portal_clean_exit() { log "portal_clean_exit $*"; }
assert_greeter() { log "assert_greeter $*"; }
qmp() { log "qmp $*"; }
shot() {
  local name="$1"
  log "shot $name"
  [[ "${MEDIA_TEST_FAIL_SHOT:-}" != "$name" ]] || return 1
  printf 'png\n' >"$LIVE_OUT_DIR/$name.png"
  echo "$name.png"
}
vm() {
  log "vm $*"
  case "$*" in
    *omarchy-theme-current*) echo original-owner ;;
    *omarchy-kids-bar\ status*) echo enabled ;;
  esac
}
vmroot() {
  log "vmroot $*"
  if [[ -n "${MEDIA_TEST_FAIL_VMROOT:-}" && "$*" == *"$MEDIA_TEST_FAIL_VMROOT"* ]]; then
    return 1
  fi
  case "$*" in
    *"omarchy-kids-conf get kid-cy lights_out_weekend"*) echo 22:00 ;;
    *"omarchy-kids-conf get kid-cy theme"*) echo original-kid ;;
    *"omarchy-kids-conf get kid-cy lights_out"*) echo 21:00 ;;
    *"omarchy-kids-conf get kid-cy wifi"*) echo parent ;;
    *"omarchy-kids-conf get kid-cy band"*) echo 6-8 ;;
  esac
}
EOF
}

ROOT1="$TMP/default"
make_fixture "$ROOT1"
LOG1="$TMP/default.log"
WRONG_OUT="$TMP/configured-live-out"
MEDIA_TEST_LOG="$LOG1" MEDIA_TEST_WRONG_OUT="$WRONG_OUT" \
  "$ROOT1/scripts/media-driver.sh" >"$TMP/default.out" 2>&1
status=$?
check "$status" "0" "default run exits 0"
check "$(find "$ROOT1/docs/media" -name '*.png' | wc -l | tr -d ' ')" "20" \
  "default run writes ten surfaces under two themes"
check "$(find "$WRONG_OUT" -name '*.png' | wc -l | tr -d ' ')" "0" \
  "config.env's acceptance output cannot divert release pictures"
for theme in tokyo-night catppuccin-latte; do
  for surface in portal launcher exit-modal ask times-up wifi-picker plugins-shelf wizard panel bar-module; do
    [[ -s "$ROOT1/docs/media/$surface-$theme.png" ]] &&
      pass "$surface is captured under $theme" || fail_ "$surface is missing under $theme"
  done
done
log1="$(cat "$LOG1")"
check_contains "$log1" "boot_with owner-password kid-test" "driver starts from a known owner boot"
check_contains "$log1" "export OMARCHY_PATH=/usr/share/omarchy; /usr/bin/omarchy-theme-set tokyo-night" \
  "parent theme uses omarchy-theme-set with OMARCHY_PATH"
check_contains "$log1" "omarchy-kids-conf set kid-cy theme tokyo-night" \
  "kid theme follows the requested theme"
check_contains "$log1" "omarchy-kids-assert" "portal producer is refreshed"
check_contains "$log1" "systemctl restart sddm" "SDDM restarts before portal capture"
assert_line="$(grep -n 'omarchy-kids-assert' "$LOG1" | head -1 | cut -d: -f1)"
restart_line="$(grep -n 'systemctl restart sddm' "$LOG1" | head -1 | cut -d: -f1)"
portal_line="$(grep -n 'shot portal-tokyo-night' "$LOG1" | head -1 | cut -d: -f1)"
if [[ -n "$assert_line" && -n "$restart_line" && -n "$portal_line" ]] &&
  ((assert_line < restart_line && restart_line < portal_line)); then
  pass "portal config is produced, SDDM restarted, then the portal is captured"
else
  fail_ "portal producer/restart/capture order"
fi
check_contains "$log1" "omarchy-theme-set original-owner" "parent theme is restored"
check_contains "$log1" "omarchy-kids-conf set kid-cy theme original-kid" "kid theme is restored"
check_contains "$log1" "portal_clean_exit kid-cy" "bar capture uses the shared clean-exit helper"
bad_root_calls="$(grep '^vmroot ' "$LOG1" | grep -v '^vmroot env -i PATH=/usr/bin:/bin' || true)"
check "$bad_root_calls" "" "driver-owned root commands work without inherited environment or HOME"
if [[ "$log1" != *"omarchy-kids-bar enable"* ]]; then
  pass "driver never enables or rewrites the parent's bar"
else
  fail_ "driver changed the parent's bar"
fi

ROOT2="$TMP/single"
make_fixture "$ROOT2"
LOG2="$TMP/single.log"
MEDIA_TEST_LOG="$LOG2" "$ROOT2/scripts/media-driver.sh" --surface ask nord >"$TMP/single.out" 2>&1
status=$?
check "$status" "0" "single-surface run exits 0"
check "$(find "$ROOT2/docs/media" -name '*.png' | wc -l | tr -d ' ')" "1" \
  "--surface captures only one requested picture"
[[ -s "$ROOT2/docs/media/ask-nord.png" ]] && pass "positional theme argument is used" ||
  fail_ "positional theme argument was not used"

ROOT3="$TMP/failure"
make_fixture "$ROOT3"
LOG3="$TMP/failure.log"
MEDIA_TEST_LOG="$LOG3" MEDIA_TEST_FAIL_SHOT=ask-tokyo-night \
  "$ROOT3/scripts/media-driver.sh" tokyo-night >"$TMP/failure.out" 2>&1
status=$?
check "$status" "1" "a failed surface makes the run fail"
[[ ! -e "$ROOT3/docs/media/ask-tokyo-night.png" ]] &&
  pass "a failed copy does not land a partial image" || fail_ "failed copy landed an image"
[[ -s "$ROOT3/docs/media/times-up-tokyo-night.png" ]] &&
  pass "the run continues after one surface fails" || fail_ "run stopped after one surface failed"
log3="$(cat "$LOG3")"
check_contains "$log3" "omarchy-theme-set original-owner" "failure path restores the parent theme"
check_contains "$log3" "omarchy-kids-conf set kid-cy theme original-kid" \
  "failure path restores the kid theme"

ROOT4="$TMP/partial"
make_fixture "$ROOT4"
LOG4="$TMP/partial.log"
MEDIA_TEST_LOG="$LOG4" MEDIA_TEST_FAIL_VMROOT="lights_out_weekend 00:01" \
  "$ROOT4/scripts/media-driver.sh" --surface times-up tokyo-night >"$TMP/partial.out" 2>&1
status=$?
check "$status" "1" "a partial Time's Up setup makes the run fail"
log4="$(cat "$LOG4")"
check_contains "$log4" "omarchy-kids-conf set kid-cy lights_out 21:00" \
  "a partial Time's Up setup restores the weekday setting"
check_contains "$log4" "omarchy-kids-conf set kid-cy lights_out_weekend 22:00" \
  "a partial Time's Up setup restores the weekend setting"

ROOT5="$TMP/timer"
make_fixture "$ROOT5"
LOG5="$TMP/timer.log"
MEDIA_TEST_LOG="$LOG5" MEDIA_TEST_FAIL_VMROOT="omarchy-kids-time-ledger tick" \
  "$ROOT5/scripts/media-driver.sh" --surface bar-module tokyo-night >"$TMP/timer.out" 2>&1
status=$?
check "$status" "1" "a bar status-tick failure makes the run fail"
check_contains "$(cat "$LOG5")" "systemctl start omarchy-kids-time.timer" \
  "a failed bar capture restarts a timer it stopped"

ROOT6="$TMP/reject"
make_fixture "$ROOT6"
LOG6="$TMP/reject.log"
: >"$LOG6"
MEDIA_TEST_LOG="$LOG6" "$ROOT6/scripts/media-driver.sh" 'bad;theme' >"$TMP/reject.out" 2>&1
status=$?
check "$status" "2" "unsafe theme names are rejected before driving the VM"
check "$(wc -l <"$LOG6" | tr -d ' ')" "0" "rejected input calls no VM helper"

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning "$DIR/scripts/media-driver.sh" "$DIR/test/shell.d/media-driver-test.sh"; then
    pass "shellcheck -S warning is clean on the driver and its test"
  else
    fail_ "shellcheck -S warning found something in the driver or its test"
  fi
else
  echo "SKIP shellcheck: not installed"
fi

exit $fail
