#!/bin/bash
# V4 (in the test VM): per-kid LUKS2 key slots can be added, changed, tested and removed, using
# the existing passphrase only. Run inside the VM as a sudo-capable user. The boot-with-a-kid-password
# half of V4 is driven from the host with scripts/vm-qmp.sh (type <password>, enter).
set -uo pipefail
DEV="${1:-$(lsblk -no PATH,FSTYPE | awk '$2=="crypto_LUKS"{print $1; exit}')}"
OWNER_PASS="${OWNER_PASS:-omarchy}"
# sudo closes extra fds, which kills process-substitution key files; run as root instead of via sudo.
if [[ $(id -u) -ne 0 ]]; then exec sudo -E OWNER_PASS="$OWNER_PASS" bash "$0" "$@"; fi
pass(){ echo "PASS  $*"; }; fail(){ echo "FAIL  $*"; rc=1; }; rc=0
slots(){ cryptsetup luksDump "$DEV" | grep -cE '^\s+[0-9]+: luks2'; }
echo "device: $DEV  slots before: $(slots)"
add(){ cryptsetup luksAddKey --key-file=<(printf '%s' "$OWNER_PASS") "$DEV" <(printf '%s' "$1") 2>&1; }
test_pw(){ cryptsetup open --test-passphrase --key-file=<(printf '%s' "$1") "$DEV" 2>/dev/null; }
for k in kidpass-ada kidpass-ben kidpass-cy; do add "$k" >/dev/null && test_pw "$k" && pass "slot added for '$k'" || fail "add '$k'"; done
[[ $(slots) -eq 4 ]] && pass "four slots present (owner + 3 kids)" || fail "expected 4 slots, have $(slots)"
# change one kid's password: add the new one authorized by the OLD one, then remove the old one
cryptsetup luksAddKey --key-file=<(printf '%s' kidpass-ben) "$DEV" <(printf '%s' kidpass-ben2) 2>/dev/null \
 && cryptsetup luksRemoveKey "$DEV" --key-file=<(printf '%s' kidpass-ben) 2>/dev/null \
 && test_pw kidpass-ben2 && ! test_pw kidpass-ben && pass "password change (add new, remove old) keeps slot count at $(slots)" || fail "password change"
# remove a kid
cryptsetup luksRemoveKey "$DEV" --key-file=<(printf '%s' kidpass-cy) 2>/dev/null && ! test_pw kidpass-cy && pass "kid removed, their password no longer opens the disk" || fail "remove kid"
test_pw "$OWNER_PASS" && pass "owner password still opens the disk" || fail "owner password broken!"
echo "slots after: $(slots)  (expect 3: owner, ada, ben2)"
cryptsetup luksDump "$DEV" | grep -E '^\s+[0-9]+: luks2'
echo "V4 in-VM RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"; exit $rc
