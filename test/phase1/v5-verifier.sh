#!/bin/bash
# V5 on real hardware: the parent-password verifier behind a PAM line, kid password first.
# Test accounts only: kid-test plays the "parent" (verifier target), kid-ada plays the kid.
# Installs the daemon units temporarily; removes the scratch PAM service at the end.
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARENT=kid-test
PPASS="v5-parent-pass"
KID=kid-ada
KPASS="v5-kid-pass"
rc=0
pass() { echo "PASS  $*"; }
fail() {
  echo "FAIL  $*"
  rc=1
}
id $KID >/dev/null 2>&1 || sudo useradd -m -G omarchy-kids -s /bin/bash $KID
printf '%s:%s\n' $PARENT "$PPASS" | sudo chpasswd
printf '%s:%s\n' $KID "$KPASS" | sudo chpasswd
sudo install -m 755 $R/bin/omarchy-kids-authd /usr/bin/omarchy-kids-authd
sudo install -m 755 $R/bin/omarchy-kids-parent-auth /usr/bin/omarchy-kids-parent-auth
sudo install -m 644 $R/systemd/omarchy-kids-authd.socket /etc/systemd/system/
sudo sed "s|^ExecStart=.*|ExecStart=/usr/bin/omarchy-kids-authd --parent $PARENT|" $R/systemd/omarchy-kids-authd.service | sudo tee /etc/systemd/system/omarchy-kids-authd.service >/dev/null
sudo systemctl daemon-reload && sudo systemctl restart omarchy-kids-authd.socket && sudo systemctl stop omarchy-kids-authd.service 2>/dev/null
ls -l /run/omarchy-kids/auth.sock | awk '{print "socket:", $1, $NF}'
sudo tee /etc/pam.d/omarchy-kids-v5test >/dev/null <<'PAM'
#%PAM-1.0
auth       [success=2 default=ignore]  pam_unix.so try_first_pass nullok
auth       [success=1 default=ignore]  pam_exec.so quiet expose_authtok /usr/bin/omarchy-kids-parent-auth
auth       [default=die]               pam_deny.so
auth       optional                    pam_permit.so
account    required                    pam_permit.so
PAM
try() { sudo -H -u "$1" python3 $R/test/phase1/pam-try.py omarchy-kids-v5test "$2" "$3" 2>&1 | tail -1; }
r=$(try $KID $KID "$KPASS")
[[ $r == PAM_SUCCESS ]] && pass "kid's own password opens the kid's stack (pam_unix)" || fail "kid own password: $r"
r=$(try $KID $KID "$PPASS")
[[ $r == PAM_SUCCESS ]] && pass "parent password opens the kid's stack (verifier), stack run as the kid" || fail "parent pw as kid: $r"
r=$(try root $KID "$PPASS")
[[ $r == PAM_SUCCESS ]] && pass "parent password opens the kid's stack, stack run as root (SDDM case)" || fail "parent pw as root: $r"
r=$(try root $KID "nope-1")
r2=$(try root $KID "nope-2")
r3=$(try root $KID "nope-3")
[[ $r3 != PAM_SUCCESS ]] && pass "wrong password denied ($r3)" || fail "wrong accepted"
r=$(try $KID $KID "$PPASS")
[[ $r != PAM_SUCCESS ]] && pass "after 3 misses the parent path is rate-limited (30 s)" || fail "rate limit missing"
r=$(try $KID $KID "$KPASS")
[[ $r == PAM_SUCCESS ]] && pass "kid's own password still works while the parent path is limited" || fail "kid pw during limit: $r"
echo "verifier service: $(systemctl is-active omarchy-kids-authd.service)  journal candidates leaked: $(sudo journalctl -u omarchy-kids-authd.service --since '10 min ago' 2>/dev/null | grep -c "$PPASS")"
sudo rm -f /etc/pam.d/omarchy-kids-v5test
echo "V5 RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
