#!/bin/bash
# Tests bin/omarchy-kids-remove (SPEC.md R-TRUST-1, R-TRUST-4, R-FND-6):
# every lock it reverses, the kept-vs-deleted home, the plan/confirm/dry-run
# contract, and the "running it twice is safe" idempotence claim.
#
# Builds a fully-provisioned scratch tree the same way
# test/shell.d/assert-test.sh does -- seeding every lock directly through
# lib/posture.sh's own writers, plus the same verbatim real
# /etc/pam.d/sddm and /etc/pam.d/omarchy-lock-password fixtures -- rather
# than shelling out to omarchy-kids-provision add (this file is about
# remove reversing state, not about provisioning it). Every system
# command that would touch the real machine (userdel, cryptsetup,
# systemctl, mkinitcpio, snapper, tar, findmnt, mount, umount, id) is a
# fake on a stub PATH that only logs its argv and fakes just enough state
# for the script under test to react to, same shape as
# test/shell.d/provision-test.sh's and assert-test.sh's stub() helper.
# Never touches the real /etc, /var, or /home (AGENTS.md rule 8). One
# provisioned kid throughout: kid-ada, band 6-8 (AGENTS.md rule 9).
# shellcheck disable=SC2015 # "A && B || C" below is always used with B, C that can't fail
set -uo pipefail

# shellcheck source=test/shell.d/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT_DIR/bin/omarchy-kids-remove"
APP="$ROOT_DIR/bin/omarchy-kids"

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
line_status() { # OUTPUT DESC -> status word for the LAST line "STATUS DESC"
  # (a real run prints the plan pass, then the real pass; every check
  # this file makes about the real pass's outcome wants the second one)
  local out="$1" desc="$2" line
  line="$(grep -E "^[A-Za-z-]+ +${desc}\$" <<<"$out" | tail -n1 || true)"
  [[ -n "$line" ]] && awk '{print $1}' <<<"$line"
}
check_status() { # OUTPUT DESC WANT LABEL
  local got
  got="$(line_status "$1" "$2")"
  check_eq "$got" "$3" "$4"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- scratch tree --------------------------------------------------------

ETC="$TMP/etc/omarchy-kids"
SHARE="$TMP/share/omarchy-kids" # fixture-seeding only; omarchy-kids-remove never reads OMARCHY_KIDS_SHARE
SCRATCH_ROOT="$TMP/root"        # OMARCHY_KIDS_ROOT
HOMEROOT="$TMP/homeroot"        # OMARCHY_KIDS_HOME_ROOT
STUBS="$TMP/stubs"
LOG="$TMP/log"
ARGV_LOG="$LOG/argv.log"

mkdir -p "$ETC/kids" "$SHARE/avatars" "$SCRATCH_ROOT/usr/lib/pam.d" "$HOMEROOT" "$STUBS" "$LOG"
cp "$ROOT_DIR"/share/avatars/fox.svg "$SHARE/avatars/"
touch "$ARGV_LOG"

cat >"$ETC/machine.conf" <<'EOF'
parent=mark
EOF

cat >"$ETC/kids/kid-ada.conf" <<'EOF'
name=Ada Lovelace
avatar=fox
band=6-8
password=set
onboarded=no
EOF

cat >"$ETC/luks-slots" <<'EOF'
0=mark:omarchy.desktop
3=kid-ada
EOF
chmod 0600 "$ETC/luks-slots"

# --- stub PATH -------------------------------------------------------------

stub() {
  local name="$1" extra="${2:-}" f="$STUBS/$1"
  cat >"$f" <<'EOF'
#!/bin/bash
{ printf '%s' "__NAME__"; printf ' %s' "$@"; printf '\n'; } >> "__ARGVLOG__"
EOF
  [[ -n "$extra" ]] && printf '%s\n' "$extra" >>"$f"
  echo 'exit 0' >>"$f"
  sed -i.bak -e "s#__NAME__#$name#g" -e "s#__ARGVLOG__#$ARGV_LOG#g" -e "s#__LOG__#$LOG#g" "$f"
  rm -f "$f.bak"
  chmod +x "$f"
}

# findmnt: reports noexec while "$LOG/mounted-<acct>" exists (same
# convention as test/shell.d/assert-test.sh).
# shellcheck disable=SC2016
stub findmnt '
target="${@: -1}"; acct="$(basename "$target")"
[[ -f "__LOG__/mounted-$acct" ]] && { echo "rw,nosuid,nodev,noexec,relatime"; exit 0; }
exit 1
'
# umount: drops the mounted marker so a second call reports not mounted.
# shellcheck disable=SC2016
stub umount '
acct="$(basename "${@: -1}")"
rm -f "__LOG__/mounted-$acct"
'
# id <acct>: succeeds while "$LOG/account-<acct>" exists (userdel below
# removes it), fails otherwise -- exactly how a real "id" behaves once an
# account is gone. id -nG <acct>: prints "staff omarchy-parents" while
# "$LOG/parent-group-<acct>" exists (gpasswd -d below removes it), same
# marker-file shape, so the new parent-group step (issue #45 item 3) has
# something real to check and remove.
# shellcheck disable=SC2016
stub id '
if [[ "${1:-}" == "-nG" ]]; then
    acct="$2"
    [[ -f "__LOG__/parent-group-$acct" ]] && echo "staff omarchy-parents"
    exit 0
fi
acct="${@: -1}"
[[ -f "__LOG__/account-$acct" ]] && exit 0
exit 1
'
# userdel [-r] <acct>: drops the account marker; -r also wipes the home,
# matching real userdel -r semantics -- home_present (the script under
# test) sees it gone afterward, same as a real machine would.
# shellcheck disable=SC2016
stub userdel '
delr=0
for a in "$@"; do [[ "$a" == "-r" ]] && delr=1; done
acct="${@: -1}"
rm -f "__LOG__/account-$acct"
[[ "$delr" == 1 ]] && rm -rf "$OMARCHY_KIDS_HOME_ROOT/home/$acct"
true
'
# cryptsetup luksKillSlot [--batch-mode] [--key-file=PATH] DEVICE SLOT:
# captures whatever key-file content was given (if any) so the test can
# confirm --parent-password-stdin actually reaches cryptsetup -- never via
# argv (a path only), matching every other password test in this repo.
# shellcheck disable=SC2016
stub cryptsetup '
if [[ "$1" == "luksKillSlot" ]]; then
    shift
    for a in "$@"; do
        case "$a" in
            --key-file=*) cat "${a#--key-file=}" >> "__LOG__/luks-keyfile-used" 2>/dev/null ;;
        esac
    done
fi
'
# systemctl: unmask drops the getty symlink; disable [--now] drops
# whichever *.target.wants symlink(s) a unit has (a unit with none, like
# the authd *service* -- only its socket is ever enabled -- is a no-op);
# --root=R is parsed the same way test/shell.d/assert-test.sh's stub does.
# shellcheck disable=SC2016
stub systemctl '
root=""
newargs=()
for a in "$@"; do
    case "$a" in
        --root=*) root="${a#--root=}" ;;
        *) newargs+=("$a") ;;
    esac
done
set -- "${newargs[@]}"
case "${1:-}" in
    unmask)
        shift
        for u in "$@"; do rm -f "$root/etc/systemd/system/$u"; done
        ;;
    disable)
        shift
        [[ "${1:-}" == "--now" ]] && shift
        for u in "$@"; do
            rm -f "$root/etc/systemd/system/multi-user.target.wants/$u"
            rm -f "$root/etc/systemd/system/sockets.target.wants/$u"
            rm -f "$root/etc/systemd/system/timers.target.wants/$u"
        done
        ;;
esac
'
# mkinitcpio -P: just logged (argv is asserted directly).
stub mkinitcpio ''
# snapper -c root create --print-number -d "...": prints a fake snapshot
# number on stdout when --print-number is given, same as a real snapper --
# lets the test confirm omarchy-kids-remove prints it back out (issue #45).
# shellcheck disable=SC2016
stub snapper '
for a in "$@"; do [[ "$a" == "--print-number" ]] && { echo "42"; break; }; done
'
# chown -R <parent:group> <dest>: just logged -- a real chown to another
# account fails outright unprivileged (this test never runs as root, per
# AGENTS.md rule 8), same reasoning docs/assert.md already gives for the
# Chromium policy lock's own best-effort chown.
stub chown ''
# gpasswd -d <acct> <group>: drops the parent-group marker (issue #45 item
# 3), the mirror image of the "id -nG" stub above.
# shellcheck disable=SC2016
stub gpasswd '
if [[ "${1:-}" == "-d" ]]; then
    rm -f "__LOG__/parent-group-$2"
fi
'
# tar: a spy, not a stub -- argv is logged like every other fake here, but
# the archive itself is real (delegates to the real /usr/bin/tar), so this
# file can inspect luks-slots' content as it stood the moment it was
# archived, right before the run's own final step deletes it.
cat >"$STUBS/tar" <<'EOF'
#!/bin/bash
{ printf '%s' "tar"; printf ' %s' "$@"; printf '\n'; } >> "__ARGVLOG__"
exec /usr/bin/tar "$@"
EOF
sed -i.bak -e "s#__ARGVLOG__#$ARGV_LOG#g" "$STUBS/tar"
rm -f "$STUBS/tar.bak"
chmod +x "$STUBS/tar"

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_ROOT="$SCRATCH_ROOT"
export OMARCHY_KIDS_HOME_ROOT="$HOMEROOT"
export OMARCHY_KIDS_LUKS_DEVICE=/dev/fake0

# --- seed every lock as "already provisioned" -----------------------------

# shellcheck source=lib/conf.sh
source "$ROOT_DIR/lib/conf.sh"
# shellcheck source=lib/posture.sh
source "$ROOT_DIR/lib/posture.sh"

posture_add_fstab_line kid-ada
posture_add_namespace_lines kid-ada
posture_write_polkit_admin_rule mark
posture_write_polkit_deny_rule
posture_write_sddm_theme_dropin
posture_write_accountsservice kid-ada fox
posture_write_face_icon "$SHARE/avatars/fox.svg" kid-ada
posture_write_portal_conf mark "$(printf 'kid-ada\tAda Lovelace\tfox')"

# Verbatim real /etc/pam.d/sddm and /etc/pam.d/omarchy-lock-password (see
# test/shell.d/assert-test.sh for the full provenance note).
mkdir -p "$SCRATCH_ROOT/etc/pam.d"
cat >"$SCRATCH_ROOT/etc/pam.d/sddm" <<'EOF'
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
cat >"$SCRATCH_ROOT/etc/pam.d/omarchy-lock-password" <<'EOF'
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
posture_ensure_parent_unlock_line sddm
posture_ensure_parent_unlock_line omarchy-lock-password

# mount: mounted noexec right now
mkdir -p "$HOMEROOT/home/kid-ada"
echo "a drawing" >"$HOMEROOT/home/kid-ada/drawing.txt"
touch "$LOG/mounted-kid-ada"
touch "$LOG/account-kid-ada"

# the parent's own home -- no real `getent` in a plain bash script (even
# on this macOS dev box: confirmed it's a zsh-only shell function, not on
# PATH for a script run with `bash`), so parent_home_dir() falls back to
# this same $HOMEROOT prefix every other path in this file already uses.
mkdir -p "$HOMEROOT/home/mark"

# mark is a member of omarchy-parents already (issue #45 item 3's
# parent-group step has something to remove).
touch "$LOG/parent-group-mark"

# getty@tty2..6 masked
mkdir -p "$SCRATCH_ROOT/etc/systemd/system"
for n in 2 3 4 5 6; do ln -sf /dev/null "$SCRATCH_ROOT/etc/systemd/system/getty@tty$n.service"; done

# package units enabled: the full lib/kids.sh list (issue #45 item 5 --
# omarchy-kids-wifid.socket and omarchy-kids-ask-collect.timer included,
# so this test would catch either one being left out again).
mkdir -p "$SCRATCH_ROOT/etc/systemd/system/multi-user.target.wants" \
  "$SCRATCH_ROOT/etc/systemd/system/sockets.target.wants" \
  "$SCRATCH_ROOT/etc/systemd/system/timers.target.wants"
for u in omarchy-kids-boot-login.service omarchy-kids-boot-login-cleanup.service omarchy-kids-assert.service; do
  ln -sf "/usr/lib/systemd/system/$u" "$SCRATCH_ROOT/etc/systemd/system/multi-user.target.wants/$u"
done
for u in omarchy-kids-authd.socket omarchy-kids-wifid.socket; do
  ln -sf "/usr/lib/systemd/system/$u" "$SCRATCH_ROOT/etc/systemd/system/sockets.target.wants/$u"
done
for u in omarchy-kids-time.timer omarchy-kids-ask-collect.timer; do
  ln -sf "/usr/lib/systemd/system/$u" "$SCRATCH_ROOT/etc/systemd/system/timers.target.wants/$u"
done

# chromium policy: one band's file
mkdir -p "$SCRATCH_ROOT/etc/chromium/policies/managed"
echo '{}' >"$SCRATCH_ROOT/etc/chromium/policies/managed/omarchy-kids-6-8.json"

# mkinitcpio drop-in
mkdir -p "$SCRATCH_ROOT/etc/mkinitcpio.conf.d"
echo "# omarchy-kids hook insertion" >"$SCRATCH_ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"

# per-boot SDDM autologin drop-in (present this boot)
mkdir -p "$SCRATCH_ROOT/etc/sddm.conf.d"
echo "[Autologin]" >"$SCRATCH_ROOT/etc/sddm.conf.d/zz-omarchy-kids-autologin.conf"

# limine: hidden snapshot entries, remembering the old value (10)
mkdir -p "$SCRATCH_ROOT/etc/default"
printf 'KERNEL_CMDLINE[default]="quiet"\n# omarchy-kids: was MAX_SNAPSHOT_ENTRIES=10\nMAX_SNAPSHOT_ENTRIES=0\n' >"$SCRATCH_ROOT/etc/default/limine"

# /var/lib/omarchy-kids: some recorded usage state
mkdir -p "$SCRATCH_ROOT/var/lib/omarchy-kids/kid-ada/usage"
echo "2026-09-01 45" >"$SCRATCH_ROOT/var/lib/omarchy-kids/kid-ada/usage/day.log"

# --- --help --------------------------------------------------------------

"$BIN" --help >/dev/null 2>&1
check_eq "$?" 0 "--help exits 0"
"$BIN" --nonsense >/dev/null 2>&1
check_eq "$?" 2 "an unknown flag exits 2"

# --- --dry-run: prints the plan, writes nothing ---------------------------

out="$("$BIN" --dry-run 2>&1)"
st=$?
check_eq "$st" 0 "--dry-run exits 0"
check_contains "$out" "Plan:" "--dry-run prints a plan"
for desc in "mount:kid-ada" "fstab:kid-ada" "luks:kid-ada" "namespace:kid-ada" \
  "accountsservice:kid-ada" "face:kid-ada" "account:kid-ada" "profile:kid-ada" "home:kid-ada" \
  "polkit-admin" "polkit-deny" "getty:tty2" "sddm-theme" \
  "parent-unlock:sddm" "parent-unlock:omarchy-lock-password" \
  "chromium-policy:6-8" "limine-snapshots" "mkinitcpio-hook" "sddm-autologin" \
  "units" "parent-group" "etc-and-varlib"; do
  check_status "$out" "$desc" "would-remove" "--dry-run: $desc would be removed"
done
# portal-conf's own check is content-based (does theme.conf.user match
# what it should hold for whatever's *actually* still under $KIDS_DIR),
# not presence-based like every lock above -- a --dry-run pass never
# removes kid-ada's profile first, so at the moment this check runs the
# file is still correctly in sync with a kid-ada that (in this preview
# pass) hasn't gone anywhere yet. It only shows would-remove/removed once
# the profile itself is actually gone -- exercised below, in the real run.
check_status "$out" "portal-conf" "skipped" "--dry-run: portal-conf has nothing to resync yet (kid-ada's profile is still on disk during the plan pass)"
# Read-only check functions (findmnt, id) do run for real even under
# --dry-run, same as every check function in bin/omarchy-kids-assert --
# only the destructive fix side is skipped. Assert those never ran.
dryrun_argv="$(cat "$ARGV_LOG")"
for cmd in userdel cryptsetup mkinitcpio snapper tar systemctl umount chown gpasswd; do
  check_not_contains "$dryrun_argv" "$cmd " "--dry-run: $cmd was never invoked"
done
[[ -e "$ETC/kids/kid-ada.conf" ]] && pass "--dry-run left the profile in place" || fail "--dry-run must not remove the profile"
[[ -d "$HOMEROOT/home/kid-ada" ]] && pass "--dry-run left the home in place" || fail "--dry-run must not touch the home"

# --- no --yes, decline: cancels, changes nothing --------------------------

out="$(printf 'no\n' | "$BIN" 2>&1)"
st=$?
check_eq "$st" 1 "declining the confirmation exits 1"
check_contains "$out" "cancelled" "declining names the cancellation"
[[ -e "$ETC/kids/kid-ada.conf" ]] && pass "declining left the profile in place" || fail "declining must not remove the profile"

# --- real run: --yes, --parent-password-stdin ------------------------------

: >"$ARGV_LOG"
out="$(printf 'parentpass1\n' | "$BIN" --yes --parent-password-stdin 2>&1)"
st=$?
argv="$(cat "$ARGV_LOG")"

check_eq "$st" 0 "real run exits 0"
check_contains "$out" "Plan:" "real run still prints the plan first"
check_contains "$out" "Removing:" "real run prints a Removing section after the plan"

check_status "$out" "mount:kid-ada" "removed" "mount:kid-ada removed"
check_contains "$argv" "umount $HOMEROOT/home/kid-ada" "mount: unmounted the home"

check_status "$out" "fstab:kid-ada" "removed" "fstab:kid-ada removed"
check_eq "$(grep -c "kid-ada" "$SCRATCH_ROOT/etc/fstab" 2>/dev/null)" "0" "fstab: the line for kid-ada is gone"

check_status "$out" "luks:kid-ada" "removed" "luks:kid-ada removed"
check_contains "$argv" "cryptsetup luksKillSlot --batch-mode --key-file=" "luks: cryptsetup luksKillSlot called with a key-file"
check_contains "$argv" "/dev/fake0 3" "luks: killed the exact slot (3) on the right device"
check_eq "$(cat "$LOG/luks-keyfile-used" 2>/dev/null)" "parentpass1" "luks: the parent password reached cryptsetup via its key-file"
check_not_contains "$argv" "parentpass1" "luks: the parent password never appears in any command's argv"
# luks-slots itself is checked below, before the run's own final
# "etc-and-varlib" step deletes the whole $ETC tree it lives under.

check_status "$out" "namespace:kid-ada" "removed" "namespace:kid-ada removed"
check_eq "$(grep -c "kid-ada\$" "$SCRATCH_ROOT/etc/security/namespace.conf")" "0" "namespace.conf: kid-ada's lines are gone"

check_status "$out" "accountsservice:kid-ada" "removed" "accountsservice:kid-ada removed"
[[ -e "$SCRATCH_ROOT/var/lib/AccountsService/users/kid-ada" ]] && fail "AccountsService file should be removed" ||
  pass "AccountsService file removed"

check_status "$out" "face:kid-ada" "removed" "face:kid-ada removed"
[[ -e "$SCRATCH_ROOT/usr/share/sddm/faces/kid-ada.face.icon" ]] && fail "face icon should be removed" ||
  pass "face icon removed"

check_status "$out" "account:kid-ada" "removed" "account:kid-ada removed"
check_contains "$argv" "userdel kid-ada" "account: userdel called, no -r"
check_not_contains "$argv" "userdel -r kid-ada" "account: userdel never got -r without --delete-homes"

check_status "$out" "profile:kid-ada" "removed" "profile:kid-ada removed"
[[ -e "$ETC/kids/kid-ada.conf" ]] && fail "profile should be removed" || pass "profile removed"

# R-FND-6 / omarchy-kids-provision remove's own convention: kept under
# the parent's home, not as a /home sibling of the (now-gone) account.
KIDS_MODE_DIR="$HOMEROOT/home/mark/Kids Mode"
check_status "$out" "home:kid-ada" "removed" "home:kid-ada removed"
[[ -d "$KIDS_MODE_DIR/Ada Lovelace" ]] && pass "home kept, moved to <parent home>/Kids Mode/<name>" ||
  fail "home should have been moved to $KIDS_MODE_DIR/Ada Lovelace"
check_eq "$(cat "$KIDS_MODE_DIR/Ada Lovelace/drawing.txt" 2>/dev/null)" "a drawing" \
  "home: the kid's own file survived the move"
[[ -d "$HOMEROOT/home/kid-ada" ]] && fail "the old home path should be gone" || pass "old home path gone"
mode="$(kids_file_mode "$KIDS_MODE_DIR")"
check_eq "$mode" "700" "home: the parent's Kids Mode folder is 0700"
check_contains "$argv" "chown -R mark:mark $KIDS_MODE_DIR/Ada Lovelace" "home: chowned parent:parent recursively (issue #45 item 2)"

check_status "$out" "polkit-admin" "removed" "polkit-admin removed"
[[ -e "$SCRATCH_ROOT/etc/polkit-1/rules.d/40-omarchy-kids.rules" ]] && fail "polkit admin rule should be removed" ||
  pass "polkit admin rule removed"
check_status "$out" "polkit-deny" "removed" "polkit-deny removed"
[[ -e "$SCRATCH_ROOT/etc/polkit-1/rules.d/41-omarchy-kids-deny.rules" ]] && fail "polkit deny rule should be removed" ||
  pass "polkit deny rule removed"

for n in 2 3 4 5 6; do
  check_status "$out" "getty:tty$n" "removed" "getty:tty$n removed"
  check_contains "$argv" "systemctl --root=$SCRATCH_ROOT unmask getty@tty$n.service" "getty:tty$n: unmask was called"
  [[ -e "$SCRATCH_ROOT/etc/systemd/system/getty@tty$n.service" ]] && fail "getty@tty$n mask symlink should be gone" ||
    pass "getty@tty$n mask symlink gone"
done

check_status "$out" "sddm-theme" "removed" "sddm-theme removed"
[[ -e "$SCRATCH_ROOT/etc/sddm.conf.d/zz-omarchy-kids-theme.conf" ]] && fail "sddm theme drop-in should be removed" ||
  pass "sddm theme drop-in removed"

check_status "$out" "portal-conf" "removed" "portal-conf removed"
check_not_contains "$(cat "$SCRATCH_ROOT/usr/share/sddm/themes/omarchy-kids/theme.conf.user" 2>/dev/null)" "kid-ada" \
  "portal-conf: theme.conf.user no longer names kid-ada"
check_contains "$(cat "$SCRATCH_ROOT/usr/share/sddm/themes/omarchy-kids/theme.conf.user" 2>/dev/null)" "parent=mark" \
  "portal-conf: theme.conf.user still names the parent"

check_status "$out" "parent-unlock:sddm" "removed" "parent-unlock:sddm removed"
check_eq "$(grep -c 'parent-unlock verifier' "$SCRATCH_ROOT/etc/pam.d/sddm")" "0" "pam.d/sddm: parent-unlock marker gone"
check_contains "$(cat "$SCRATCH_ROOT/etc/pam.d/sddm")" "auth        include     system-login" \
  "pam.d/sddm: the vendor stack's own line survives"
check_status "$out" "parent-unlock:omarchy-lock-password" "removed" "parent-unlock:omarchy-lock-password removed"
check_eq "$(grep -c 'parent-unlock verifier' "$SCRATCH_ROOT/etc/pam.d/omarchy-lock-password")" "0" \
  "pam.d/omarchy-lock-password: parent-unlock marker gone"

check_status "$out" "chromium-policy:6-8" "removed" "chromium-policy:6-8 removed"
[[ -e "$SCRATCH_ROOT/etc/chromium/policies/managed/omarchy-kids-6-8.json" ]] && fail "chromium policy file should be removed" ||
  pass "chromium policy file removed"

check_status "$out" "limine-snapshots" "removed" "limine-snapshots removed"
check_eq "$(grep -c '^MAX_SNAPSHOT_ENTRIES=10$' "$SCRATCH_ROOT/etc/default/limine")" "1" "limine: old value (10) restored"
check_eq "$(grep -c 'omarchy-kids: was' "$SCRATCH_ROOT/etc/default/limine")" "0" "limine: our marker comment is gone"
check_contains "$(cat "$SCRATCH_ROOT/etc/default/limine")" 'KERNEL_CMDLINE[default]="quiet"' "limine: unrelated lines survive"

check_status "$out" "mkinitcpio-hook" "removed" "mkinitcpio-hook removed"
[[ -e "$SCRATCH_ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf" ]] && fail "mkinitcpio drop-in should be removed" ||
  pass "mkinitcpio drop-in removed"
check_contains "$argv" "mkinitcpio -P" "mkinitcpio-hook: mkinitcpio -P was run"

check_status "$out" "sddm-autologin" "removed" "sddm-autologin removed"
[[ -e "$SCRATCH_ROOT/etc/sddm.conf.d/zz-omarchy-kids-autologin.conf" ]] && fail "autologin drop-in should be removed" ||
  pass "autologin drop-in removed"

check_status "$out" "units" "removed" "units removed"
# --now is only passed when there's a live systemd to signal (posture_root
# empty, i.e. a real run); a scratch OMARCHY_KIDS_ROOT means --root= is
# used instead, which systemctl refuses to combine with --now. The unit
# list itself comes from lib/kids.sh (issue #45 item 5) plus this
# command's own KIDS_EXTRA_UNITS, so a unit added there --
# omarchy-kids-wifid.socket, omarchy-kids-ask-collect.timer -- is torn
# down here too, with no separate list to fall out of sync.
check_contains "$argv" "systemctl --root=$SCRATCH_ROOT disable omarchy-kids-boot-login.service omarchy-kids-boot-login-cleanup.service omarchy-kids-assert.service omarchy-kids-authd.socket omarchy-kids-wifid.socket omarchy-kids-time.timer omarchy-kids-ask-collect.timer omarchy-kids-authd.service omarchy-kids-wifid.service omarchy-kids-time-ledger.service omarchy-kids-ask-collect.service" \
  "units: disable called (via --root, since this is a scratch tree) with the full lib/kids.sh list, including omarchy-kids-wifid.socket"
for u in omarchy-kids-boot-login.service omarchy-kids-boot-login-cleanup.service omarchy-kids-assert.service; do
  [[ -e "$SCRATCH_ROOT/etc/systemd/system/multi-user.target.wants/$u" ]] && fail "$u should be disabled" ||
    pass "$u disabled"
done
for u in omarchy-kids-time.timer omarchy-kids-ask-collect.timer; do
  [[ -e "$SCRATCH_ROOT/etc/systemd/system/timers.target.wants/$u" ]] && fail "$u should be disabled" ||
    pass "$u disabled"
done
for u in omarchy-kids-authd.socket omarchy-kids-wifid.socket; do
  [[ -e "$SCRATCH_ROOT/etc/systemd/system/sockets.target.wants/$u" ]] && fail "$u should be disabled" ||
    pass "$u disabled"
done

check_status "$out" "parent-group" "removed" "parent-group removed (issue #45 item 3)"
check_contains "$argv" "gpasswd -d mark omarchy-parents" "parent-group: gpasswd -d mark omarchy-parents was called"
[[ -e "$LOG/parent-group-mark" ]] && fail "mark should no longer be in omarchy-parents" ||
  pass "parent-group: mark's omarchy-parents membership marker is gone"

check_status "$out" "etc-and-varlib" "removed" "etc-and-varlib removed"
[[ -d "$ETC" ]] && fail "/etc/omarchy-kids should be gone" || pass "/etc/omarchy-kids removed"
[[ -d "$SCRATCH_ROOT/var/lib/omarchy-kids" ]] && fail "/var/lib/omarchy-kids should be gone" || pass "/var/lib/omarchy-kids removed"
tarball="$(find "$SCRATCH_ROOT/root" -name 'omarchy-kids-removed-*.tar.gz' 2>/dev/null | head -1)"
[[ -n "$tarball" ]] && pass "a backup tarball was written to /root" || fail "no backup tarball found under $SCRATCH_ROOT/root"
if [[ -n "$tarball" ]]; then
  # The tarball is a real archive (see the tar spy above): confirm it
  # captured luks-slots as it stood right before deletion -- kid-ada's
  # slot already gone (killed earlier in this same run), the parent's
  # slot 0 intact -- proof the backup ran after per-kid cleanup, not
  # instead of it, and that nothing was lost.
  member="${ETC#/}/luks-slots"
  slots_backed_up="$(tar xzf "$tarball" -O "$member" 2>/dev/null || true)"
  check_eq "$(grep -c '^3=kid-ada$' <<<"$slots_backed_up")" "0" "backup: luks-slots in the tarball has no entry for kid-ada"
  check_eq "$(grep -c '^0=mark:omarchy.desktop$' <<<"$slots_backed_up")" "1" "backup: luks-slots in the tarball still has the parent's slot 0"
  varlib_member="${SCRATCH_ROOT#/}/var/lib/omarchy-kids/kid-ada/usage/day.log"
  check_contains "$(tar xzf "$tarball" -O "$varlib_member" 2>/dev/null || true)" "45" \
    "backup: the tarball also captured /var/lib/omarchy-kids"
fi

check_status "$out" "snapshot" "removed" "snapshot taken (snapper is on PATH)"
check_contains "$argv" "snapper -c root create --print-number -d" "snapshot: snapper was called with --print-number"
check_contains "$argv" "Remove Kids Mode" "snapshot: the description names Remove Kids Mode"
check_contains "$out" "Snapper snapshot: #42" "snapshot: the snapshot number it created is printed (issue #45)"

check_contains "$out" "sudo pacman -R omarchy-kids" "real run prints the pacman uninstall hint, and does not run it"
check_not_contains "$argv" "pacman" "the pacman command itself is never invoked"

# --- summary: names any failed step, exit 0 when only skips happened ------
# (issue #45 item 4 -- the real run above had no failures at all)

check_contains "$out" "Summary: every step removed or skipped, nothing failed." \
  "summary: a clean run says so explicitly"

# --- idempotence: a second run (kids all gone) reports skipped -----------

: >"$ARGV_LOG"
: >"$LOG/luks-keyfile-used"
out2="$("$BIN" --yes --no-snapshot 2>&1)"
st2=$?
check_eq "$st2" 0 "second run exits 0"
still_active="$(grep -Ev '^skipped ' <<<"$out2" | grep -v '^Plan:$' | grep -v '^Removing:$' | grep -v '^$' | grep -v 'sudo pacman' | grep -v 'not removed yet' | grep -v '^Summary:' || true)"
[[ -z "$still_active" ]] && pass "second run: every remaining lock reports skipped" ||
  fail "second run: unexpected non-skipped line(s):"$'\n'"$still_active"
check_eq "$(cat "$ARGV_LOG")" "" "second run invoked no real destructive commands"

echo "remove-test RESULT (part 1): $([[ $rc == 0 ]] && echo PASS || echo FAIL)"

# --- --delete-homes: a fresh kid, home deleted rather than kept -----------
# (a full run already purged $ETC entirely in part 1, so it has to be
# rebuilt -- kids/ included -- before seeding this fixture)

mkdir -p "$ETC/kids"
cat >"$ETC/kids/kid-ben.conf" <<'EOF'
name=Ben
avatar=bear
band=6-8
password=none
onboarded=no
EOF
mkdir -p "$HOMEROOT/home/kid-ben"
echo "ben's stuff" >"$HOMEROOT/home/kid-ben/notes.txt"
touch "$LOG/mounted-kid-ben" "$LOG/account-kid-ben"
posture_add_fstab_line kid-ben
posture_add_namespace_lines kid-ben
posture_write_accountsservice kid-ben bear

: >"$ARGV_LOG"
out4="$("$BIN" --yes --no-snapshot --delete-homes 2>&1)"
st4=$?
argv4="$(cat "$ARGV_LOG")"
check_eq "$st4" 0 "--delete-homes run exits 0"
check_contains "$argv4" "userdel -r kid-ben" "--delete-homes: userdel -r called"
[[ -d "$HOMEROOT/home/kid-ben" ]] && fail "--delete-homes should have removed the home" || pass "--delete-homes: home is gone"
[[ -d "$HOMEROOT/home/mark/Kids Mode/Ben" ]] && fail "--delete-homes must not also copy it into Kids Mode" ||
  pass "--delete-homes: no Kids Mode copy left behind"
check_status "$out4" "home:kid-ben" "skipped" "--delete-homes: the home step itself has nothing left to do (userdel -r already did it)"

# --- --keep-parent-group: parent stays in omarchy-parents (issue #45 item 3)
# ($ETC itself was purged by the two real runs above -- rebuilt here)

mkdir -p "$ETC"
cat >"$ETC/machine.conf" <<'EOF'
parent=mark
EOF
touch "$LOG/parent-group-mark"

: >"$ARGV_LOG"
out7="$("$BIN" --yes --no-snapshot --keep-parent-group 2>&1)"
st7=$?
argv7="$(cat "$ARGV_LOG")"
check_eq "$st7" 0 "--keep-parent-group run exits 0"
check_status "$out7" "parent-group" "skipped" "--keep-parent-group: parent-group step is skipped"
check_not_contains "$argv7" "gpasswd" "--keep-parent-group: gpasswd was never invoked"
[[ -e "$LOG/parent-group-mark" ]] && pass "--keep-parent-group: mark is still in omarchy-parents" ||
  fail "--keep-parent-group must not touch omarchy-parents membership"

# --- summary names a FAILED step; exit 1 only for a real failure ----------
# (issue #45 item 4 -- every run above only ever skipped or removed
# cleanly; this exercises the one path that must actually fail. A fresh
# mkinitcpio stub that exits 1, standing in for a real machine where
# `mkinitcpio -P` itself errors out.)

mkdir -p "$SCRATCH_ROOT/etc/mkinitcpio.conf.d"
echo "# omarchy-kids hook insertion" >"$SCRATCH_ROOT/etc/mkinitcpio.conf.d/omarchy_kids.conf"
cat >"$STUBS/mkinitcpio" <<'EOF'
#!/bin/bash
{ printf '%s' "mkinitcpio"; printf ' %s' "$@"; printf '\n'; } >> "__ARGVLOG__"
exit 1
EOF
sed -i.bak -e "s#__ARGVLOG__#$ARGV_LOG#g" "$STUBS/mkinitcpio"
rm -f "$STUBS/mkinitcpio.bak"
chmod +x "$STUBS/mkinitcpio"

: >"$ARGV_LOG"
out8="$("$BIN" --yes --no-snapshot 2>&1)"
st8=$?
check_eq "$st8" 1 "a run with a real FAILED step exits 1"
check_status "$out8" "mkinitcpio-hook" "FAILED" "a failing fix function reports FAILED, not removed/skipped"
check_contains "$out8" "Summary: 1 step(s) FAILED: mkinitcpio-hook" \
  "summary: names the failed step by its exact description (issue #45 item 4)"

# --- remove-kids-mode dispatch through bin/omarchy-kids -------------------

out5="$("$APP" remove-kids-mode --help 2>&1)"
st5=$?
check_eq "$st5" 0 "omarchy-kids remove-kids-mode --help exits 0"
check_contains "$out5" "Remove Kids Mode" "omarchy-kids remove-kids-mode --help dispatches to omarchy-kids-remove"

out6="$("$APP" remove-kids-mode --dry-run 2>&1)"
st6=$?
check_eq "$st6" 0 "omarchy-kids remove-kids-mode --dry-run exits 0"
check_contains "$out6" "Plan:" "omarchy-kids remove-kids-mode --dry-run runs the real command (env still points at the scratch tree)"

echo "remove-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
