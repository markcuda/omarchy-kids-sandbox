#!/bin/bash
# Tests lib/posture.sh's parent-unlock PAM writers (SPEC.md R-SEC-2,
# R-SEC-3; docs/authd.md): posture_ensure_parent_unlock_line,
# posture_remove_parent_unlock_line, and posture_parent_unlock_lock_stack.
#
# Two stack shapes are exercised, both taken verbatim from
# scratchpad/pr9750.diff's bin/omarchy-apply-lock hunk (see that file's
# own "lock_password_stack" function):
#
#   - "sddm" here stands in for the general case: the pam_unix.so line
#     carries "[success=2 default=ignore]" (the diff's *child-profile*
#     branch, one line before where our own pam_exec line would go), so
#     the N-1 formula applies: our line gets "[success=1 default=ignore]".
#   - "omarchy-lock-password" stands in for the special case: the
#     pam_unix.so line carries exactly "[success=1 default=bad]" (the
#     diff's *default-profile* branch -- what bin/omarchy-apply-lock
#     writes today), where N-1 would be 0 (wrong -- see lib/posture.sh's
#     own comment), so our line is hardcoded to "[success=1
#     default=ignore]" instead.
#
# Fully self-contained: every file lives under a scratch OMARCHY_KIDS_ROOT,
# never the real /etc (AGENTS.md rule 8).
# shellcheck disable=SC2015 # "A && B || C" below is always used with B, C that can't fail
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; rc=1; }
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

# --- shape 1: general "[success=N ...]" (N=2) --> ours gets N-1=1 --------

SDDM="$SCRATCH_ROOT/etc/pam.d/sddm"
cat > "$SDDM" <<'EOF'
#%PAM-1.0
auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120
-auth      [success=3 default=ignore]  pam_systemd_home.so
auth       [success=2 default=ignore]  pam_unix.so try_first_pass nullok
auth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120
auth       optional                    pam_permit.so
auth       required                    pam_env.so
auth       required                    pam_faillock.so authsucc
account    include                     system-login
EOF

posture_ensure_parent_unlock_line sddm
out="$(cat "$SDDM")"

check_eq "$(grep -c "$MARKER" "$SDDM")" "1" "sddm: marker inserted exactly once"
check_eq "$(grep -c "auth       \[success=1 default=ignore\]  $PAM_EXEC_LINE" "$SDDM")" "1" \
    "sddm: N-1 formula gives success=1 (pam_unix had success=2)"

expected_sddm=$'#%PAM-1.0\nauth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120\n-auth      [success=3 default=ignore]  pam_systemd_home.so\nauth       [success=2 default=ignore]  pam_unix.so try_first_pass nullok\n'"$MARKER"$'\nauth       [success=1 default=ignore]  '"$PAM_EXEC_LINE"$'\nauth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120\nauth       optional                    pam_permit.so\nauth       required                    pam_env.so\nauth       required                    pam_faillock.so authsucc\naccount    include                     system-login'
check_eq "$out" "$expected_sddm" "sddm: exact resulting file content"

# idempotence: a second call changes nothing.
posture_ensure_parent_unlock_line sddm
check_eq "$(grep -c "$MARKER" "$SDDM")" "1" "sddm: still exactly one marker after a second call"
check_eq "$(cat "$SDDM")" "$out" "sddm: file content unchanged by the second call"

# --- shape 2: the special "[success=1 default=bad]" case ------------------

LOCKPW="$SCRATCH_ROOT/etc/pam.d/omarchy-lock-password"
cat > "$LOCKPW" <<'EOF'
#%PAM-1.0
auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120
-auth      [success=2 default=ignore]  pam_systemd_home.so
auth       [success=1 default=bad]     pam_unix.so try_first_pass nullok
auth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120
auth       optional                    pam_permit.so
auth       required                    pam_env.so
auth       required                    pam_faillock.so authsucc
account    include system-login
EOF

posture_ensure_parent_unlock_line omarchy-lock-password
out2="$(cat "$LOCKPW")"

check_eq "$(grep -c "$MARKER" "$LOCKPW")" "1" "omarchy-lock-password: marker inserted exactly once"
check_eq "$(grep -c "auth       \[success=1 default=ignore\]  $PAM_EXEC_LINE" "$LOCKPW")" "1" \
    "omarchy-lock-password: special case gives success=1, not N-1=0"
check_contains "$out2" $'auth       [success=1 default=bad]     pam_unix.so try_first_pass nullok\n'"$MARKER"$'\nauth       [success=1 default=ignore]  '"$PAM_EXEC_LINE"$'\nauth       [default=die]' \
    "omarchy-lock-password: inserted directly between pam_unix and the authfail line"
check_not_contains "$out2" "success=0" "omarchy-lock-password: never writes a success=0 (would be a no-op jump)"

# idempotence
posture_ensure_parent_unlock_line omarchy-lock-password
check_eq "$(grep -c "$MARKER" "$LOCKPW")" "1" "omarchy-lock-password: still exactly one marker after a second call"
check_eq "$(cat "$LOCKPW")" "$out2" "omarchy-lock-password: file content unchanged by the second call"

# --- posture_parent_unlock_lock_stack: picks omarchy-lock-password when
#     present, else falls back to hyprlock -----------------------------

check_eq "$(posture_parent_unlock_lock_stack)" "omarchy-lock-password" \
    "lock_stack: omarchy-lock-password wins when it exists"

rm -f "$LOCKPW"
check_eq "$(posture_parent_unlock_lock_stack)" "hyprlock" \
    "lock_stack: falls back to hyprlock when omarchy-lock-password doesn't exist"

# --- removal reverses both shapes, leaving everything else untouched -----

before_removal="$(cat "$SDDM")"
posture_remove_parent_unlock_line sddm
check_not_contains "$(cat "$SDDM")" "$MARKER" "sddm: removal drops the marker"
check_not_contains "$(cat "$SDDM")" "$PAM_EXEC_LINE" "sddm: removal drops the pam_exec line"
check_contains "$(cat "$SDDM")" "pam_unix.so try_first_pass nullok" "sddm: removal leaves pam_unix untouched"
check_contains "$(cat "$SDDM")" "account    include                     system-login" \
    "sddm: removal leaves the rest of the file untouched"
[[ "$(cat "$SDDM")" != "$before_removal" ]] && pass "sddm: removal actually changed the file" \
    || fail "sddm: removal was a no-op (should have removed something)"

# removal is idempotent too: a second call on an already-clean file is a no-op.
after_first_removal="$(cat "$SDDM")"
posture_remove_parent_unlock_line sddm
check_eq "$(cat "$SDDM")" "$after_first_removal" "sddm: a second removal is a no-op"

# --- error paths: no pam_unix.so line, missing file ------------------------

NOUNIX="$SCRATCH_ROOT/etc/pam.d/no-unix-line"
cat > "$NOUNIX" <<'EOF'
#%PAM-1.0
auth       required   pam_env.so
account    include    system-login
EOF
if posture_ensure_parent_unlock_line no-unix-line 2>/tmp/parent-unlock-test.stderr; then
    fail "a stack with no pam_unix.so line should be refused"
else
    pass "a stack with no pam_unix.so line is refused (exit non-zero)"
fi
check_not_contains "$(cat "$NOUNIX")" "$MARKER" "a stack with no pam_unix.so line is left untouched"

if posture_ensure_parent_unlock_line does-not-exist 2>/dev/null; then
    fail "a missing PAM stack should be refused"
else
    pass "a missing PAM stack is refused (exit non-zero)"
fi

echo "parent-unlock-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
