#!/bin/bash
# omarchy-kids-boot-login (R-BOOT-3): mapped slot writes User=/Session=,
# unmapped slot writes an empty User= (portal), --cleanup removes the
# drop-in. Runs entirely against a scratch tree via the OMARCHY_KIDS_*
# path overrides — no root, no real /etc or /run touched.
set -uo pipefail
pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; rc=1; }
rc=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/bin/omarchy-kids-boot-login"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

export OMARCHY_KIDS_RUN_DIR="$SCRATCH/run"
export OMARCHY_KIDS_SLOTS_FILE="$SCRATCH/luks-slots"
export OMARCHY_KIDS_SDDM_DIR="$SCRATCH/sddm.conf.d"
export OMARCHY_KIDS_ETC="$SCRATCH/etc"

# The profile registry decides kid vs owner, never the account name
# (review §1.6). kid-ada is provisioned; kid-vm deliberately is not.
mkdir -p "$OMARCHY_KIDS_ETC/kids"
printf 'band=6-8\n' > "$OMARCHY_KIDS_ETC/kids/kid-ada.conf"
DROPIN="$OMARCHY_KIDS_SDDM_DIR/zz-omarchy-kids-autologin.conf"

mkdir -p "$OMARCHY_KIDS_RUN_DIR"
cat > "$OMARCHY_KIDS_SLOTS_FILE" <<'EOF'
# comment line, and a blank line below should be ignored

0=mark
2=kid-ada
3=kid-ben:omarchy
4=kid-vm
EOF
chmod 600 "$OMARCHY_KIDS_SLOTS_FILE"

# --- mapped kid slot: a provisioned kid gets the kid session ---
echo 2 > "$OMARCHY_KIDS_RUN_DIR/boot-slot"
"$BIN"
if [[ -f "$DROPIN" ]]; then
    if grep -qx 'User=kid-ada' "$DROPIN" && grep -qx 'Session=omarchy-kids.desktop' "$DROPIN"; then
        pass "mapped kid slot -> User=kid-ada, Session=omarchy-kids.desktop"
    else
        fail "mapped kid slot wrote unexpected content: $(tr '\n' ' ' < "$DROPIN")"
    fi
else
    fail "mapped kid slot did not write a drop-in"
fi

# --- review §1.6: an OWNER whose name starts with kid- is not a kid -------
#
# lib/posture.sh already documents this failing live on a VM whose owner
# was named "kid-vm". Here it would autologin the machine's owner into a
# root-owned kiosk session. There is no kid-vm.conf, so it must not.
echo 4 > "$OMARCHY_KIDS_RUN_DIR/boot-slot"
"$BIN"
if grep -qx 'User=kid-vm' "$DROPIN" 2>/dev/null && grep -qx 'Session=omarchy.desktop' "$DROPIN" 2>/dev/null; then
    pass "an unprovisioned kid-* owner gets the stock session, not the kid session"
else
    fail "unprovisioned kid-vm was misclassified: $(tr '\n' ' ' < "$DROPIN" 2>/dev/null)"
fi

# ...and the mirror image: a kid whose name has no kid- prefix at all.
printf 'band=6-8\n' > "$OMARCHY_KIDS_ETC/kids/mark.conf"
echo 0 > "$OMARCHY_KIDS_RUN_DIR/boot-slot"
"$BIN"
if grep -qx 'Session=omarchy-kids.desktop' "$DROPIN" 2>/dev/null; then
    pass "a provisioned account with no kid- prefix still gets the kid session"
else
    fail "prefix-free kid account was misclassified: $(tr '\n' ' ' < "$DROPIN" 2>/dev/null)"
fi
rm -f "$OMARCHY_KIDS_ETC/kids/mark.conf"

# --- mapped parent slot: session not in file, decided by the registry -----
echo 0 > "$OMARCHY_KIDS_RUN_DIR/boot-slot"
"$BIN"
if grep -qx 'User=mark' "$DROPIN" 2>/dev/null && grep -qx 'Session=omarchy.desktop' "$DROPIN" 2>/dev/null; then
    pass "mapped parent slot -> User=mark, Session=omarchy.desktop (default)"
else
    fail "mapped parent slot wrote unexpected content: $(tr '\n' ' ' < "$DROPIN" 2>/dev/null)"
fi

# --- mapped slot with an explicit session column ---
echo 3 > "$OMARCHY_KIDS_RUN_DIR/boot-slot"
"$BIN"
if grep -qx 'User=kid-ben' "$DROPIN" 2>/dev/null && grep -qx 'Session=omarchy.desktop' "$DROPIN" 2>/dev/null; then
    pass "explicit slot=account:session column honored"
else
    fail "explicit session column not honored: $(tr '\n' ' ' < "$DROPIN" 2>/dev/null)"
fi

# --- unmapped slot: empty User=, no Session= line, portal shows ---
echo 9 > "$OMARCHY_KIDS_RUN_DIR/boot-slot"
"$BIN"
if [[ -f "$DROPIN" ]]; then
    if grep -qx 'User=' "$DROPIN" && ! grep -q '^Session=' "$DROPIN"; then
        pass "unmapped slot -> empty User= (portal)"
    else
        fail "unmapped slot wrote unexpected content: $(tr '\n' ' ' < "$DROPIN")"
    fi
else
    fail "unmapped slot did not write a drop-in"
fi

# --- no boot-slot file at all: fails safe to empty User=, doesn't error ---
rm -f "$OMARCHY_KIDS_RUN_DIR/boot-slot"
if "$BIN"; then
    if grep -qx 'User=' "$DROPIN" 2>/dev/null; then
        pass "missing boot-slot file -> empty User=, no error"
    else
        fail "missing boot-slot file wrote unexpected content"
    fi
else
    fail "missing boot-slot file made omarchy-kids-boot-login exit non-zero"
fi

# --- cleanup removes the drop-in ---
"$BIN" --cleanup
if [[ ! -e "$DROPIN" ]]; then
    pass "--cleanup removes the drop-in"
else
    fail "--cleanup left the drop-in in place"
fi

# --- cleanup on an already-clean tree is a harmless no-op ---
if "$BIN" --cleanup; then
    pass "--cleanup is idempotent"
else
    fail "--cleanup failed on an already-clean tree"
fi

echo "boot-login-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
