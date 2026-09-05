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
check_file_contains() {
  if grep -Fq "$2" "$1"; then pass "$3"; else
    fail_ "$3 (missing '$2')"
  fi
}

make_fixture() {
  local root="$1"
  mkdir -p "$root/scripts" "$root/test/live" "$root/docs/media"
  cp "$DIR/scripts/media-driver.sh" "$root/scripts/media-driver.sh"
  cp "$DIR/scripts/vm-driver-lock" "$root/scripts/vm-driver-lock"
  sed -i.bak "s#/tmp/omarchy-kids-vm-driver.lock#$root/vm-driver.lock#" "$root/scripts/vm-driver-lock"
  rm -f "$root/scripts/vm-driver-lock.bak"
  cat >"$root/scripts/image-contains-text" <<'EOF'
#!/bin/bash
: "${MEDIA_TEST_LOG:?}"
printf 'image-contains-text %s\n' "$*" >>"$MEDIA_TEST_LOG"
image_name="$(basename "$1")"
[[ -z "${MEDIA_TEST_NEVER_RENDER:-}" || "$*" != *"$MEDIA_TEST_NEVER_RENDER"* ]] || exit 1
[[ "${MEDIA_TEST_BAD_IMAGE:-}" != "$image_name" ]] || exit 1
[[ "${MEDIA_TEST_TIMES_UP_IMAGE:-1}" == 1 ]]
EOF
  chmod +x "$root/scripts/media-driver.sh" "$root/scripts/vm-driver-lock" \
    "$root/scripts/image-contains-text"
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
boot_with() {
  log "boot_with $*"
  if [[ -n "${MEDIA_TEST_HOLD:-}" ]]; then
    : >"$MEDIA_TEST_HOLD.ready"
    while [[ ! -e "$MEDIA_TEST_HOLD.release" ]]; do /bin/sleep 0.01; done
  fi
}
portal_login() { log "portal_login $*"; }
wait_kid_ready() { log "wait_kid_ready $*"; }
portal_reset() { log "portal_reset $*"; }
portal_clean_exit() { log "portal_clean_exit $*"; }
assert_greeter() { log "assert_greeter $*"; }
assert_no_session() { log "assert_no_session $*"; }
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
  if [[ -n "${MEDIA_TEST_FAIL_VM:-}" && "$*" == *"$MEDIA_TEST_FAIL_VM"* ]]; then
    return 1
  fi
  case "$*" in
    *omarchy-theme-current*) echo original-owner ;;
    *omarchy-kids-bar\ status*) echo enabled ;;
  esac
}
vmroot() {
  log "vmroot $*"
  if [[ -n "${MEDIA_TEST_FAIL_VMROOT_ONCE:-}" && "$*" == *"$MEDIA_TEST_FAIL_VMROOT_ONCE"* &&
    ! -e "$MEDIA_TEST_STATE_DIR/fail-once" ]]; then
    : >"$MEDIA_TEST_STATE_DIR/fail-once"
    return 1
  fi
  if [[ -n "${MEDIA_TEST_FAIL_VMROOT:-}" && "$*" == *"$MEDIA_TEST_FAIL_VMROOT"* ]]; then
    return 1
  fi
  case "$*" in
    *timesUpReady*)
      [[ "${MEDIA_TEST_TIMES_UP_READY:-1}" == 1 ]] && echo true || echo false
      ;;
    *"omarchy-kids-conf source kid-cy theme"*)
      if [[ "${MEDIA_TEST_INHERITED:-0}" == 1 ]]; then echo default; else echo override; fi
      ;;
    *"omarchy-kids-conf source kid-cy lights_out_weekend"*)
      if [[ "${MEDIA_TEST_INHERITED:-0}" == 1 ]]; then echo band; else echo override; fi
      ;;
    *"omarchy-kids-conf source kid-cy lights_out"*)
      if [[ "${MEDIA_TEST_INHERITED:-0}" == 1 ]]; then echo band; else echo override; fi
      ;;
    *"omarchy-kids-conf source kid-cy wifi"*)
      if [[ "${MEDIA_TEST_INHERITED:-0}" == 1 ]]; then echo band; else echo override; fi
      ;;
    *"omarchy-kids-conf set kid-cy lights_out_weekend 00:01"*)
      [[ -z "${MEDIA_TEST_STATE_DIR:-}" ]] || printf '00:01\n' >"$MEDIA_TEST_STATE_DIR/lights_out_weekend"
      ;;
    *"omarchy-kids-conf set kid-cy lights_out_weekend 22:00"*)
      [[ -z "${MEDIA_TEST_STATE_DIR:-}" ]] || printf '22:00\n' >"$MEDIA_TEST_STATE_DIR/lights_out_weekend"
      ;;
    *"omarchy-kids-conf set kid-cy lights_out 00:01"*)
      [[ -z "${MEDIA_TEST_STATE_DIR:-}" ]] || printf '00:01\n' >"$MEDIA_TEST_STATE_DIR/lights_out"
      ;;
    *"omarchy-kids-conf set kid-cy lights_out 21:00"*)
      [[ -z "${MEDIA_TEST_STATE_DIR:-}" ]] || printf '21:00\n' >"$MEDIA_TEST_STATE_DIR/lights_out"
      ;;
    *"omarchy-kids-conf get kid-cy lights_out_weekend"*)
      if [[ -n "${MEDIA_TEST_STATE_DIR:-}" ]]; then cat "$MEDIA_TEST_STATE_DIR/lights_out_weekend"; else echo 22:00; fi
      ;;
    *"omarchy-kids-conf get kid-cy theme"*) echo original-kid ;;
    *"omarchy-kids-conf get kid-cy lights_out"*)
      if [[ -n "${MEDIA_TEST_STATE_DIR:-}" ]]; then cat "$MEDIA_TEST_STATE_DIR/lights_out"; else echo 21:00; fi
      ;;
    *"omarchy-kids-conf get kid-cy wifi"*) echo parent ;;
    *"omarchy-kids-conf get kid-cy band"*) echo 6-8 ;;
    *"omarchy-kids-conf get kid-cy name"*) echo Cy ;;
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
check "$(find "$ROOT1/docs/media" -name '*.png' | wc -l | tr -d ' ')" "18" \
  "default run writes nine honest surfaces under two themes"
check "$(find "$WRONG_OUT" -name '*.png' | wc -l | tr -d ' ')" "0" \
  "config.env's acceptance output cannot divert release pictures"
for theme in tokyo-night catppuccin-latte; do
  for surface in portal launcher exit-modal ask times-up wifi-picker plugins-shelf wizard panel; do
    [[ -s "$ROOT1/docs/media/$surface-$theme.png" ]] &&
      pass "$surface is captured under $theme" || fail_ "$surface is missing under $theme"
  done
done
log1="$(cat "$LOG1")"
while IFS='|' read -r surface required; do
  for theme in tokyo-night catppuccin-latte; do
    check_file_contains "$LOG1" "/media-ready-$surface-$theme.png $required" \
      "$surface waits for rendered text under $theme"
    check_file_contains "$LOG1" "/$surface-$theme.png $required" \
      "$surface verifies required text in the release PNG under $theme"
  done
done <<'EOF'
portal|Cy
launcher|GCompris
exit-modal|Finish for Cy
ask|Ask a grown-up 15 more minutes
times-up|Time's up Finishing in
wifi-picker|Wi-Fi Enter join
plugins-shelf|More apps Pick one
wizard|Welcome Begin
panel|Kids Mode Add a kid
EOF
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
bad_root_calls="$(grep '^vmroot ' "$LOG1" | grep -v '^vmroot env -i PATH=/usr/bin:/bin' || true)"
check "$bad_root_calls" "" "driver-owned root commands work without inherited environment or HOME"
if [[ "$log1" != *"omarchy-kids-bar enable"* ]]; then
  pass "driver never enables or rewrites the parent's bar"
else
  fail_ "driver changed the parent's bar"
fi
if [[ "$log1" != *"systemctl stop omarchy-kids-time.timer"* ]]; then
  pass "driver never freezes the live-status producer for a screenshot"
else
  fail_ "driver froze the live-status producer"
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

ROOT5="$TMP/bar-rejected"
make_fixture "$ROOT5"
LOG5="$TMP/bar-rejected.log"
: >"$LOG5"
MEDIA_TEST_LOG="$LOG5" \
  "$ROOT5/scripts/media-driver.sh" --surface bar-module tokyo-night >"$TMP/bar-rejected.out" 2>&1
status=$?
check "$status" "2" "the fabricated bar-module surface is rejected"
check "$(wc -l <"$LOG5" | tr -d ' ')" "0" \
  "a rejected bar capture calls no VM helper"

ROOT6="$TMP/reject"
make_fixture "$ROOT6"
LOG6="$TMP/reject.log"
: >"$LOG6"
MEDIA_TEST_LOG="$LOG6" "$ROOT6/scripts/media-driver.sh" 'bad;theme' >"$TMP/reject.out" 2>&1
status=$?
check "$status" "2" "unsafe theme names are rejected before driving the VM"
check "$(wc -l <"$LOG6" | tr -d ' ')" "0" "rejected input calls no VM helper"

ROOT7="$TMP/locked"
make_fixture "$ROOT7"
LOG7="$TMP/locked.log"
HOLD7="$TMP/driver-lock"
MEDIA_TEST_LOG="$LOG7" MEDIA_TEST_HOLD="$HOLD7" \
  "$ROOT7/scripts/media-driver.sh" --surface ask nord >"$TMP/holder.out" 2>&1 &
holder_pid=$!
for _ in {1..100}; do
  [[ -e "$HOLD7.ready" ]] && break
  /bin/sleep 0.01
done
MEDIA_TEST_LOG="$LOG7" "$ROOT7/scripts/media-driver.sh" --surface ask nord >"$TMP/contender.out" 2>&1
status=$?
check "$status" "75" "a second VM driver is refused while the shared lock is held"
check_contains "$(cat "$TMP/contender.out")" "media-driver.sh" \
  "the lock refusal identifies the run holding the VM"
if [[ "$(cat "$TMP/contender.out")" != *"nord"* ]]; then
  pass "the lock refusal does not disclose driver arguments"
else
  fail_ "the lock refusal disclosed driver arguments"
fi
: >"$HOLD7.release"
wait "$holder_pid"
check "$(grep -c '^boot_with ' "$LOG7")" "1" "the refused driver never reaches boot_with"
for driver in v1-two-sessions.sh v6-limine.sh; do
  if grep -q 'exec .*vm-driver-lock' "$DIR/scripts/$driver"; then
    pass "$driver takes the shared VM lock"
  else
    fail_ "$driver can bypass the shared VM lock"
  fi
done

ROOT8="$TMP/theme-read-failure"
make_fixture "$ROOT8"
LOG8="$TMP/theme-read-failure.log"
MEDIA_TEST_LOG="$LOG8" MEDIA_TEST_FAIL_VM="omarchy-theme-current" \
  "$ROOT8/scripts/media-driver.sh" --surface ask nord >"$TMP/theme-read-failure.out" 2>&1
status=$?
check "$status" "1" "an owner-theme read failure makes the run fail"
log8="$(cat "$LOG8")"
check_contains "$log8" "systemctl restart sddm" \
  "a theme-read failure still restarts SDDM during cleanup"
check_contains "$log8" "assert_no_session kid-cy" \
  "cleanup confirms the kid session is closed"
check_contains "$log8" "assert_no_session kid-test" \
  "cleanup confirms the owner session is closed"
check_contains "$log8" "assert_greeter 60" \
  "cleanup confirms the greeter after a theme-read failure"

ROOT9="$TMP/assert-failure"
make_fixture "$ROOT9"
LOG9="$TMP/assert-failure.log"
MEDIA_TEST_LOG="$LOG9" MEDIA_TEST_FAIL_VMROOT="omarchy-kids-assert" \
  "$ROOT9/scripts/media-driver.sh" --surface portal nord >"$TMP/assert-failure.out" 2>&1
status=$?
check "$status" "1" "an assert failure makes the run fail"
log9="$(cat "$LOG9")"
assert_line="$(grep -n 'omarchy-kids-assert' "$LOG9" | tail -1 | cut -d: -f1)"
restart_line="$(grep -n 'systemctl restart sddm' "$LOG9" | tail -1 | cut -d: -f1)"
if [[ -n "$assert_line" && -n "$restart_line" ]] && ((assert_line < restart_line)); then
  pass "cleanup restarts SDDM even when the preceding assert fails"
else
  fail_ "assert failure prevented the cleanup SDDM restart"
fi
check_contains "$log9" "assert_no_session kid-cy" \
  "assert-failure cleanup confirms the kid session is closed"
check_contains "$log9" "assert_no_session kid-test" \
  "assert-failure cleanup confirms the owner session is closed"

ROOT10="$TMP/inherited"
make_fixture "$ROOT10"
LOG10="$TMP/inherited.log"
MEDIA_TEST_LOG="$LOG10" MEDIA_TEST_INHERITED=1 \
  "$ROOT10/scripts/media-driver.sh" tokyo-night >"$TMP/inherited.out" 2>&1
status=$?
check "$status" "0" "a run with inherited kid settings exits 0"
log10="$(cat "$LOG10")"
for key in theme lights_out lights_out_weekend wifi; do
  check_contains "$log10" "omarchy-kids-conf unset kid-cy $key" \
    "an inherited $key value is restored by clearing its temporary override"
done
if [[ "$log10" != *"omarchy-kids-conf set kid-cy theme original-kid"* &&
  "$log10" != *"omarchy-kids-conf set kid-cy lights_out 21:00"* &&
  "$log10" != *"omarchy-kids-conf set kid-cy lights_out_weekend 22:00"* &&
  "$log10" != *"omarchy-kids-conf set kid-cy wifi parent"* ]]; then
  pass "inherited values are never pinned as explicit overrides"
else
  fail_ "an inherited value was pinned as an explicit override"
fi

ROOT11="$TMP/restore-retry"
make_fixture "$ROOT11"
LOG11="$TMP/restore-retry.log"
STATE11="$TMP/restore-retry-state"
mkdir -p "$STATE11"
printf '21:00\n' >"$STATE11/lights_out"
printf '22:00\n' >"$STATE11/lights_out_weekend"
MEDIA_TEST_LOG="$LOG11" MEDIA_TEST_STATE_DIR="$STATE11" \
  MEDIA_TEST_FAIL_VMROOT_ONCE="lights_out 21:00" \
  "$ROOT11/scripts/media-driver.sh" --surface times-up tokyo-night nord >"$TMP/restore-retry.out" 2>&1
status=$?
check "$status" "1" "a transient restoration failure remains visible in the run status"
check "$(cat "$STATE11/lights_out")" "21:00" \
  "a later theme restores the true original weekday value"
check "$(cat "$STATE11/lights_out_weekend")" "22:00" \
  "a later theme keeps the true original weekend value"

ROOT12="$TMP/times-up-not-ready"
make_fixture "$ROOT12"
LOG12="$TMP/times-up-not-ready.log"
MEDIA_TEST_LOG="$LOG12" MEDIA_TEST_TIMES_UP_READY=0 \
  "$ROOT12/scripts/media-driver.sh" --surface times-up tokyo-night >"$TMP/times-up-not-ready.out" 2>&1
status=$?
check "$status" "1" "a Time's Up card that never renders makes the run fail"
log12="$(cat "$LOG12")"
if [[ "$log12" != *"shot times-up-tokyo-night"* ]]; then
  pass "an unready Time's Up card is never photographed"
else
  fail_ "the driver photographed Time's Up without a rendered-card signal"
fi
check_contains "$(cat "$DIR/share/time/timesup.qml")" "function timesUpReady(): bool" \
  "Time's Up exposes its rendered card and countdown readiness"

ROOT13="$TMP/times-up-wrong-frame"
make_fixture "$ROOT13"
LOG13="$TMP/times-up-wrong-frame.log"
MEDIA_TEST_LOG="$LOG13" MEDIA_TEST_TIMES_UP_IMAGE=0 \
  "$ROOT13/scripts/media-driver.sh" --surface times-up tokyo-night >"$TMP/times-up-wrong-frame.out" 2>&1
status=$?
check "$status" "1" "a Time's Up frame without the card makes the run fail"
[[ ! -e "$ROOT13/docs/media/times-up-tokyo-night.png" ]] &&
  pass "an unverified Time's Up frame is never released" ||
  fail_ "the driver released a Time's Up frame whose pixels were not verified"
check_contains "$(cat "$LOG13")" "image-contains-text" \
  "the captured Time's Up PNG is checked for the card and countdown text"

ROOT14="$TMP/ask-not-ready"
make_fixture "$ROOT14"
LOG14="$TMP/ask-not-ready.log"
MEDIA_TEST_LOG="$LOG14" MEDIA_TEST_NEVER_RENDER="Ask a grown-up" \
  "$ROOT14/scripts/media-driver.sh" --surface ask tokyo-night >"$TMP/ask-not-ready.out" 2>&1
status=$?
check "$status" "1" "an Ask card that never renders makes the run fail"
[[ ! -e "$ROOT14/docs/media/ask-tokyo-night.png" ]] &&
  pass "an unready Ask card is never released" || fail_ "the driver released an unready Ask card"

ROOT15="$TMP/ask-wrong-frame"
make_fixture "$ROOT15"
LOG15="$TMP/ask-wrong-frame.log"
MEDIA_TEST_LOG="$LOG15" MEDIA_TEST_BAD_IMAGE="ask-tokyo-night.png" \
  "$ROOT15/scripts/media-driver.sh" --surface ask tokyo-night >"$TMP/ask-wrong-frame.out" 2>&1
status=$?
check "$status" "1" "an Ask release frame without the card makes the run fail"
[[ ! -e "$ROOT15/docs/media/ask-tokyo-night.png" ]] &&
  pass "an unverified Ask frame is never released" || fail_ "the driver released an unverified Ask frame"

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
