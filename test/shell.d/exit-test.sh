#!/bin/bash
# Tests bin/omarchy-kids-exit and bin/omarchy-kids-super-tap (SPEC.md
# R-EXIT-1..6). This is the shell half of issue #16 -- share/exit-modal/
# shell.qml is UNTESTED (no Quickshell here at all; see that file's own
# header) and has no test in this suite.
#
# Fully self-contained: quickshell, hyprctl, loginctl, pgrep, and
# omarchy-kids-conf are fakes on a stub PATH that only log their argv
# (same shape as test/shell.d/provision-test.sh's stub() helper), never
# touching a real Hyprland/Quickshell/systemd session.
# shellcheck disable=SC2015 # "A && B || C" below is always used with B, C that can't fail
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXIT_BIN="$ROOT_DIR/bin/omarchy-kids-exit"
TAP_BIN="$ROOT_DIR/bin/omarchy-kids-super-tap"

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; rc=1; }
rc=0

check_contains() { # haystack needle label
    if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (want to find '$2', got '$1')"; fi
}
check_eq() { # got want label
    if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want '$2', got '$1')"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STUBS="$TMP/stubs"
LOG="$TMP/argv.log"
SHARE="$TMP/share"
mkdir -p "$STUBS" "$SHARE/exit-modal" "$SHARE/avatars"
touch "$LOG"
touch "$SHARE/exit-modal/shell.qml"

# stub NAME EXTRA — see provision-test.sh for the full rationale; same
# helper, copied rather than shared (each test/shell.d file is
# self-contained).
stub() {
    local name="$1" extra="${2:-}" f="$STUBS/$1"
    cat > "$f" <<'EOF'
#!/bin/bash
{ printf '%s' "__NAME__"; printf ' %s' "$@"; printf '\n'; } >> "__ARGVLOG__"
EOF
    [[ -n "$extra" ]] && printf '%s\n' "$extra" >> "$f"
    echo 'exit 0' >> "$f"
    sed -i.bak -e "s#__NAME__#$name#g" -e "s#__ARGVLOG__#$LOG#g" "$f"
    rm -f "$f.bak"
    chmod +x "$f"
}

stub quickshell
stub hyprctl
stub loginctl
# pgrep "not found" by default (exit 1: no modal already up); flipped to
# "found" (exit 0) for the one test that needs it.
stub pgrep 'exit 1'
# shellcheck disable=SC2016
stub omarchy-kids-conf '
case "$3" in
  name) echo "Ada Lovelace" ;;
  avatar) echo "fox" ;;
esac
'

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_KIDS_CONF_BIN="$STUBS/omarchy-kids-conf"
export OMARCHY_KIDS_ACCOUNT="kid-ada"

# --- --help / bad args ------------------------------------------------

"$EXIT_BIN" --help >/dev/null 2>&1; check_eq "$?" 0 "--help exits 0"
"$EXIT_BIN" --nonsense >/dev/null 2>&1; check_eq "$?" 2 "an unknown flag exits 2"

# --- --open: execs quickshell with the env from omarchy-kids-conf --------

: > "$LOG"
env -u OMARCHY_KIDS_NAME -u OMARCHY_KIDS_AVATAR "$EXIT_BIN" --open >/dev/null 2>&1; st=$?
argv="$(cat "$LOG")"
check_eq "$st" 0 "--open exits 0"
check_contains "$argv" "quickshell -p $SHARE/exit-modal/shell.qml" "--open execs quickshell with the exit-modal path"
check_contains "$argv" "omarchy-kids-conf get kid-ada name" "--open reads the kid's name from omarchy-kids-conf"
check_contains "$argv" "omarchy-kids-conf get kid-ada avatar" "--open reads the kid's avatar id from omarchy-kids-conf"

# A no-args invocation defaults to --open too (this is what Super+Shift+K
# and the triple-tap actually bind, per share/hyprland/L1.lua etc.)
: > "$LOG"
"$EXIT_BIN" >/dev/null 2>&1; st=$?
check_eq "$st" 0 "no arguments defaults to --open and exits 0"
check_contains "$(cat "$LOG")" "quickshell -p $SHARE/exit-modal/shell.qml" "no-args --open still execs quickshell"

# Confirm the exact env quickshell would see (a wrapper script that dumps
# env, dropped in as "quickshell" for one call): this is the only way to
# check exec'd env vars, since the stub's own argv log can't see them.
cat > "$STUBS/quickshell" <<'EOF'
#!/bin/bash
{
  echo "OMARCHY_KIDS_ACCOUNT=$OMARCHY_KIDS_ACCOUNT"
  echo "OMARCHY_KIDS_NAME=$OMARCHY_KIDS_NAME"
  echo "OMARCHY_KIDS_AVATAR=$OMARCHY_KIDS_AVATAR"
} > "$OMARCHY_KIDS_TEST_ENV_DUMP"
EOF
chmod +x "$STUBS/quickshell"
ENV_DUMP="$TMP/env-dump"
OMARCHY_KIDS_TEST_ENV_DUMP="$ENV_DUMP" "$EXIT_BIN" --open >/dev/null 2>&1
env_out="$(cat "$ENV_DUMP" 2>/dev/null || true)"
check_contains "$env_out" "OMARCHY_KIDS_ACCOUNT=kid-ada" "--open exports OMARCHY_KIDS_ACCOUNT"
check_contains "$env_out" "OMARCHY_KIDS_NAME=Ada Lovelace" "--open exports OMARCHY_KIDS_NAME from omarchy-kids-conf"
check_contains "$env_out" "OMARCHY_KIDS_AVATAR=$SHARE/avatars/fox.svg" "--open exports OMARCHY_KIDS_AVATAR as a path under \$SHARE/avatars"
stub quickshell  # restore the plain argv-logging stub for the rest of the suite

# --- --open: a no-op if a modal already looks open ------------------------

stub pgrep 'exit 0'  # "found" -- a modal is already up
: > "$LOG"
"$EXIT_BIN" --open >/dev/null 2>&1; st=$?
check_eq "$st" 0 "--open with a modal already up still exits 0"
# (pgrep's own argv still mentions "quickshell" -- it's the search
# pattern -- so check for a line the quickshell *stub itself* would
# have logged, not just the substring anywhere in the log.)
if grep -qE '^quickshell ' "$LOG"; then
    fail "--open never execs quickshell when one is already up (it did)"
else
    pass "--open never execs quickshell when one is already up"
fi
stub pgrep 'exit 1'  # restore "not found" for the rest of the suite

# --- --finish: hyprctl dispatch exit, then loginctl terminate-session -----

: > "$LOG"
export XDG_SESSION_ID="c7"
OMARCHY_KIDS_EXIT_WAIT=0 "$EXIT_BIN" --finish >/dev/null 2>&1; st=$?
argv2="$(cat "$LOG")"
check_eq "$st" 0 "--finish exits 0"
check_contains "$argv2" "hyprctl dispatch hl.dsp.exit()" "--finish asks Hyprland to exit with the Lua dispatcher"
check_contains "$argv2" "loginctl terminate-session c7" "--finish calls loginctl terminate-session with \$XDG_SESSION_ID"
# hyprctl's line must come first: Hyprland has to actually be asked to
# exit before the session it belongs to is torn down.
hyprctl_line="$(grep -n hyprctl <<<"$argv2" | cut -d: -f1)"
loginctl_line="$(grep -n loginctl <<<"$argv2" | cut -d: -f1)"
[[ "$hyprctl_line" -lt "$loginctl_line" ]] && pass "--finish: hyprctl runs before loginctl" \
    || fail "--finish: hyprctl should run before loginctl (got hyprctl on line $hyprctl_line, loginctl on $loginctl_line)"

# --- --finish: the compositor left on its own -> no terminate-session ----

: > "$LOG"
OMARCHY_KIDS_EXIT_WAIT=2 "$EXIT_BIN" --finish >/dev/null 2>&1; st=$?
argv3="$(cat "$LOG")"
check_eq "$st" 0 "--finish exits 0 once Hyprland is gone"
grep -q "loginctl terminate-session" <<<"$argv3" \
    && fail "--finish must not terminate the session when Hyprland already exited" \
    || pass "--finish leaves loginctl alone when Hyprland already exited"

# --- --finish: hyprctl missing is best-effort, loginctl still runs --------

rm -f "$STUBS/hyprctl"
: > "$LOG"
OMARCHY_KIDS_EXIT_WAIT=0 "$EXIT_BIN" --finish >/dev/null 2>&1; st=$?
check_eq "$st" 0 "--finish without hyprctl on PATH still exits 0"
check_contains "$(cat "$LOG")" "loginctl terminate-session c7" "--finish without hyprctl still calls loginctl"
stub hyprctl  # restore

# --- --pause: not implemented, exits 2, names why -------------------------

out3="$("$EXIT_BIN" --pause 2>&1)"; st=$?
check_eq "$st" 2 "--pause exits 2"
check_contains "$out3" "not available" "--pause says it isn't available"
check_contains "$out3" "V1.md" "--pause points at docs/phase1/V1.md"

echo

# =====================================================================
# bin/omarchy-kids-super-tap
# =====================================================================

RUNTIME_DIR="$TMP/runtime"
export OMARCHY_KIDS_RUNTIME_DIR="$RUNTIME_DIR"
EXIT_LOG="$TMP/exit-calls.log"
touch "$EXIT_LOG"
cat > "$STUBS/omarchy-kids-exit" <<EOF
#!/bin/bash
echo "called with: \$*" >> "$EXIT_LOG"
EOF
chmod +x "$STUBS/omarchy-kids-exit"

# --help
"$TAP_BIN" --help >/dev/null 2>&1; check_eq "$?" 0 "super-tap --help exits 0"

# --- three taps within 1.5s trigger omarchy-kids-exit exactly once -------

rm -rf "$RUNTIME_DIR"; : > "$EXIT_LOG"
OMARCHY_KIDS_SUPER_TAP_NOW_MS=1000 "$TAP_BIN"
OMARCHY_KIDS_SUPER_TAP_NOW_MS=1400 "$TAP_BIN"
OMARCHY_KIDS_SUPER_TAP_NOW_MS=1900 "$TAP_BIN"
check_eq "$(wc -l < "$EXIT_LOG" | tr -d ' ')" "1" "three taps within 1.5s call omarchy-kids-exit exactly once"

# A fourth tap right after should NOT immediately fire again (the count
# was reset on the trigger, so this is only tap #1 of a fresh window).
OMARCHY_KIDS_SUPER_TAP_NOW_MS=1950 "$TAP_BIN"
check_eq "$(wc -l < "$EXIT_LOG" | tr -d ' ')" "1" "the tap right after a trigger doesn't fire again on its own"

# --- taps spaced further apart than the window never trigger --------------

rm -rf "$RUNTIME_DIR"; : > "$EXIT_LOG"
OMARCHY_KIDS_SUPER_TAP_NOW_MS=1000 "$TAP_BIN"
OMARCHY_KIDS_SUPER_TAP_NOW_MS=3000 "$TAP_BIN"  # +2000ms: outside the 1500ms window
OMARCHY_KIDS_SUPER_TAP_NOW_MS=5000 "$TAP_BIN"  # +2000ms: outside again
check_eq "$(wc -l < "$EXIT_LOG" | tr -d ' ')" "0" "three taps spread more than 1.5s apart never trigger"

# --- exactly at the edge of the window still counts (<=, not <) -----------

rm -rf "$RUNTIME_DIR"; : > "$EXIT_LOG"
OMARCHY_KIDS_SUPER_TAP_NOW_MS=1000 "$TAP_BIN"
OMARCHY_KIDS_SUPER_TAP_NOW_MS=2000 "$TAP_BIN"
OMARCHY_KIDS_SUPER_TAP_NOW_MS=2500 "$TAP_BIN"  # 1500ms after the first, inclusive
check_eq "$(wc -l < "$EXIT_LOG" | tr -d ' ')" "1" "a third tap exactly 1.5s after the first still counts"

# --- a custom window is honored -------------------------------------------

rm -rf "$RUNTIME_DIR"; : > "$EXIT_LOG"
export OMARCHY_KIDS_SUPER_TAP_WINDOW_MS=500
OMARCHY_KIDS_SUPER_TAP_NOW_MS=1000 "$TAP_BIN"
OMARCHY_KIDS_SUPER_TAP_NOW_MS=1400 "$TAP_BIN"  # +400ms: within a 500ms window
OMARCHY_KIDS_SUPER_TAP_NOW_MS=1900 "$TAP_BIN"  # +500ms from tap 2, but +900ms from tap 1: tap 1 has aged out
check_eq "$(wc -l < "$EXIT_LOG" | tr -d ' ')" "0" "a shorter custom window prunes taps that would pass the default"
unset OMARCHY_KIDS_SUPER_TAP_WINDOW_MS

echo "exit-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
