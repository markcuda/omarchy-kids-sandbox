#!/bin/bash
# Tests lib/posture.sh's parent-unlock PAM writers (SPEC.md R-SEC-2,
# R-SEC-3; docs/authd.md): posture_ensure_parent_unlock_line,
# posture_remove_parent_unlock_line, and posture_parent_unlock_lock_stack.
#
# Both fixtures below are verbatim /etc/pam.d/sddm and
# /etc/pam.d/omarchy-lock-password from a real Omarchy 4.0.2 box
# (there is no /etc/pam.d/hyprlock on that box). They exercise the two
# real placement shapes lib/posture.sh's own header comment documents:
#
#   - sddm: the first non-comment "auth" line ("auth include
#     system-login") is NOT a pam_faillock preauth line, so the
#     parent-unlock line is inserted directly BEFORE it.
#   - omarchy-lock-password: the first non-comment "auth" line IS a
#     leading "pam_faillock.so ... preauth" line, so the parent-unlock
#     line is inserted directly AFTER it instead.
#
# Neither real fixture has a pam_unix.so line worth anchoring on in the
# first place (sddm has none of its own at all; omarchy-lock-password's
# is three lines below the actual anchor), which is exactly why
# placement is anchor-based on the first "auth" line, not
# pam_unix.so-based -- an earlier version of this function computed a
# jump number off pam_unix's own [success=N ...] control; that didn't
# match either real file and was replaced with the fixed
# "[success=done default=ignore]" control this version writes.
#
# Fully self-contained: every file lives under a scratch OMARCHY_KIDS_ROOT,
# never the real /etc (AGENTS.md rule 8).
# shellcheck disable=SC2015 # "A && B || C" below is always used with B, C that can't fail
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() { echo "PASS  $*"; }
fail() {
  echo "FAIL  $*"
  rc=1
}
rc=0

check_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (want to find '$2')"; fi
}
check_not_contains() { # haystack needle label
  if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail "$3 (did not want to find '$2')"; fi
}
check_eq() { # got want label
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want '$2', got '$1')"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SCRATCH_ROOT="$TMP/root"
mkdir -p "$SCRATCH_ROOT/etc/pam.d"
export OMARCHY_KIDS_ROOT="$SCRATCH_ROOT"

# shellcheck source=lib/conf.sh
source "$ROOT_DIR/lib/conf.sh"
# shellcheck source=lib/posture.sh
source "$ROOT_DIR/lib/posture.sh"

MARKER="# omarchy-kids: parent-unlock verifier (R-SEC-2, R-SEC-3)"
PAM_EXEC_LINE="pam_exec.so quiet expose_authtok /usr/bin/omarchy-kids-parent-auth"
OUR_LINE="auth       [success=done default=ignore]  $PAM_EXEC_LINE"

# --- sddm: insert BEFORE the first auth line (no leading preauth line) ---

SDDM="$SCRATCH_ROOT/etc/pam.d/sddm"
cat >"$SDDM" <<'EOF'
#%PAM-1.0
auth        include     system-login
-auth       optional    pam_kwallet5.so
account     include     system-login
password    include     system-login
session     optional    pam_keyinit.so          force revoke
session     include     system-login
-session    optional    pam_gnome_keyring.so    auto_start
-session    optional    pam_kwallet5.so         auto_start
EOF

posture_ensure_parent_unlock_line sddm
out="$(cat "$SDDM")"

check_eq "$(grep -cxF "$MARKER" "$SDDM")" "1" "sddm: marker inserted exactly once"
check_eq "$(grep -cxF "$OUR_LINE" "$SDDM")" "1" "sddm: parent-unlock line uses the fixed success=done control"

expected_sddm=$'#%PAM-1.0\n'"$MARKER"$'\n'"$OUR_LINE"$'\nauth        include     system-login\n-auth       optional    pam_kwallet5.so\naccount     include     system-login\npassword    include     system-login\nsession     optional    pam_keyinit.so          force revoke\nsession     include     system-login\n-session    optional    pam_gnome_keyring.so    auto_start\n-session    optional    pam_kwallet5.so         auto_start'
check_eq "$out" "$expected_sddm" "sddm: exact resulting file content (inserted before the first auth line)"

# idempotence: a second call changes nothing.
posture_ensure_parent_unlock_line sddm
check_eq "$(grep -cxF "$MARKER" "$SDDM")" "1" "sddm: still exactly one marker after a second call"
check_eq "$(cat "$SDDM")" "$out" "sddm: file content unchanged by the second call"

# --- omarchy-lock-password: insert AFTER the leading preauth line ---------

LOCKPW="$SCRATCH_ROOT/etc/pam.d/omarchy-lock-password"
cat >"$LOCKPW" <<'EOF'
#%PAM-1.0
auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120
-auth      [success=2 default=ignore]  pam_systemd_home.so
auth       [success=1 default=bad]     pam_unix.so try_first_pass nullok
auth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120
auth       optional                    pam_permit.so
auth       required                    pam_env.so
auth       required                    pam_faillock.so authsucc
account    include                     system-local-login
EOF

posture_ensure_parent_unlock_line omarchy-lock-password
out2="$(cat "$LOCKPW")"

check_eq "$(grep -cxF "$MARKER" "$LOCKPW")" "1" "omarchy-lock-password: marker inserted exactly once"
check_eq "$(grep -cxF "$OUR_LINE" "$LOCKPW")" "1" "omarchy-lock-password: parent-unlock line uses the fixed success=done control"
check_contains "$out2" $'auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120\n'"$MARKER"$'\n'"$OUR_LINE"$'\n-auth      [success=2 default=ignore]  pam_systemd_home.so' \
  "omarchy-lock-password: inserted directly after the leading preauth line, before pam_systemd_home"

expected_lockpw=$'#%PAM-1.0\nauth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120\n'"$MARKER"$'\n'"$OUR_LINE"$'\n-auth      [success=2 default=ignore]  pam_systemd_home.so\nauth       [success=1 default=bad]     pam_unix.so try_first_pass nullok\nauth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120\nauth       optional                    pam_permit.so\nauth       required                    pam_env.so\nauth       required                    pam_faillock.so authsucc\naccount    include                     system-local-login'
check_eq "$out2" "$expected_lockpw" "omarchy-lock-password: exact resulting file content"

# idempotence
posture_ensure_parent_unlock_line omarchy-lock-password
check_eq "$(grep -cxF "$MARKER" "$LOCKPW")" "1" "omarchy-lock-password: still exactly one marker after a second call"
check_eq "$(cat "$LOCKPW")" "$out2" "omarchy-lock-password: file content unchanged by the second call"

# --- posture_parent_unlock_lock_stack: always omarchy-lock-password ------
#
# An earlier version of this function fell back to a guessed "hyprlock"
# PAM service when omarchy-lock-password didn't exist; confirmed wrong
# against a real Omarchy 4.0.2 box (no such file exists there) and
# removed. It's a fixed answer now, not a file-existence probe.

check_eq "$(posture_parent_unlock_lock_stack)" "omarchy-lock-password" \
  "lock_stack: always omarchy-lock-password"
rm -f "$LOCKPW"
check_eq "$(posture_parent_unlock_lock_stack)" "omarchy-lock-password" \
  "lock_stack: still omarchy-lock-password even if the file doesn't exist yet (nothing to probe)"

# --- removal reverses both shapes, leaving everything else untouched -----

before_removal="$(cat "$SDDM")"
posture_remove_parent_unlock_line sddm
check_not_contains "$(cat "$SDDM")" "$MARKER" "sddm: removal drops the marker"
check_not_contains "$(cat "$SDDM")" "$PAM_EXEC_LINE" "sddm: removal drops the pam_exec line"
check_contains "$(cat "$SDDM")" "auth        include     system-login" "sddm: removal leaves the real auth chain untouched"
check_contains "$(cat "$SDDM")" "-session    optional    pam_kwallet5.so         auto_start" \
  "sddm: removal leaves the rest of the file untouched"
[[ "$(cat "$SDDM")" != "$before_removal" ]] && pass "sddm: removal actually changed the file" ||
  fail "sddm: removal was a no-op (should have removed something)"

# removal is idempotent too: a second call on an already-clean file is a no-op.
after_first_removal="$(cat "$SDDM")"
posture_remove_parent_unlock_line sddm
check_eq "$(cat "$SDDM")" "$after_first_removal" "sddm: a second removal is a no-op"

# --- error paths: no auth line at all, missing file ------------------------

NOAUTH="$SCRATCH_ROOT/etc/pam.d/no-auth-line"
cat >"$NOAUTH" <<'EOF'
#%PAM-1.0
account    include    system-login
session    include    system-login
EOF
if posture_ensure_parent_unlock_line no-auth-line 2>/tmp/parent-unlock-test.stderr; then
  fail "a stack with no non-comment 'auth' line should be refused"
else
  pass "a stack with no non-comment 'auth' line is refused (exit non-zero)"
fi
check_not_contains "$(cat "$NOAUTH")" "$MARKER" "a stack with no 'auth' line is left untouched"

if posture_ensure_parent_unlock_line does-not-exist 2>/dev/null; then
  fail "a missing PAM stack should be refused"
else
  pass "a missing PAM stack is refused (exit non-zero)"
fi

echo "parent-unlock-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
