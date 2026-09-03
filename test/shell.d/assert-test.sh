#!/bin/bash
# Tests bin/omarchy-kids-assert (SPEC.md I-4, R-TRUST-5, R-BOOT-5, R-WEB-1,
# R-FND-2..6, §5.1): every lock it re-asserts, one at a time, plus the
# no-profiles no-op and the "second run is all ok" idempotence claim.
#
# Fully self-contained, per AGENTS.md rule 8 (never write outside a
# scratch tree; never run as root): every system command that would touch
# the real machine (findmnt, mount, id, usermod, systemctl, mkinitcpio,
# objcopy, lsinitcpio) is a fake on a stub PATH that only logs its argv
# and fakes just enough state for the script under test to react to --
# same shape as test/shell.d/provision-test.sh's stub() helper, reused
# here almost verbatim. One provisioned kid throughout: kid-ada, band
# 6-8, per AGENTS.md rule 9's fixture convention.
# shellcheck disable=SC2015 # "A && B || C" below is always used with B, C that can't fail
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT_DIR/bin/omarchy-kids-assert"

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; rc=1; }
rc=0

check_contains() { # haystack needle label
    if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (want to find '$2')"; fi
}
check_eq() { # got want label
    if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want '$2', got '$1')"; fi
}
# line_status OUTPUT LOCK — the status word ("ok"/"fixed"/"FAIL"/"" if
# absent) that OUTPUT's line for LOCK starts with.
line_status() {
    local out="$1" lock="$2" line
    line="$(grep -E "^[A-Za-z-]+ +${lock}\$" <<<"$out" || true)"
    [[ -n "$line" ]] && awk '{print $1}' <<<"$line"
}
check_status() { # OUTPUT LOCK WANT LABEL
    local got
    got="$(line_status "$1" "$2")"
    check_eq "$got" "$3" "$4"
}
# only_this_lock_changed OUTPUT LOCK LABEL — every line in OUTPUT is "ok"
# except LOCK, which must be "fixed". Confirms one broken lock doesn't
# make assert touch (or misreport) any other lock.
only_this_lock_changed() {
    local out="$1" lock="$2" label="$3" bad
    check_status "$out" "$lock" "fixed" "$label: $lock reports fixed"
    bad="$(grep -Ev "^ok " <<<"$out" | grep -v "^fixed *${lock}\$" || true)"
    [[ -z "$bad" ]] && pass "$label: no other lock line changed" \
        || fail "$label: unexpected non-ok line(s):"$'\n'"$bad"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- scratch tree ------------------------------------------------------

ETC="$TMP/etc/omarchy-kids"
SHARE="$TMP/share/omarchy-kids"
SCRATCH_ROOT="$TMP/root"       # OMARCHY_KIDS_ROOT
HOMEROOT="$TMP/homeroot"       # OMARCHY_KIDS_HOME_ROOT
STUBS="$TMP/stubs"
LOG="$TMP/log"
ARGV_LOG="$LOG/argv.log"

mkdir -p "$ETC/kids" "$SHARE/hyprland" "$SHARE/avatars" "$SCRATCH_ROOT/usr/lib/pam.d" "$HOMEROOT" "$STUBS" "$LOG/groups" "$LOG/gecos"
printf 'account include system-login\nsession include system-login\n' > "$SCRATCH_ROOT/usr/lib/pam.d/systemd-user"
touch "$ARGV_LOG"

cat > "$ETC/machine.conf" <<'EOF'
parent=mark
EOF

cat > "$ETC/kids/kid-ada.conf" <<'EOF'
name=Ada Lovelace
avatar=fox
band=6-8
theme=tokyo-night
password=set
onboarded=no
EOF

# issue #53: a scratch system themes dir for theme_apply_for's own copy.
OMARCHY_PATH="$TMP/omarchy"
mkdir -p "$OMARCHY_PATH/themes/tokyo-night"
echo 'background = "#1a1b26"' > "$OMARCHY_PATH/themes/tokyo-night/colors.toml"

cp "$ROOT_DIR"/share/hyprland/*.lua "$SHARE/hyprland/"
cp "$ROOT_DIR"/share/avatars/*.svg "$SHARE/avatars/"

# --- stub PATH -----------------------------------------------------------

# stub NAME EXTRA — see provision-test.sh for the full rationale; same
# helper, copied rather than shared (test/shell.d files are each
# self-contained, matching every other file in this directory).
stub() {
    local name="$1" extra="${2:-}" f="$STUBS/$1"
    cat > "$f" <<'EOF'
#!/bin/bash
{ printf '%s' "__NAME__"; printf ' %s' "$@"; printf '\n'; } >> "__ARGVLOG__"
EOF
    [[ -n "$extra" ]] && printf '%s\n' "$extra" >> "$f"
    echo 'exit 0' >> "$f"
    sed -i.bak -e "s#__NAME__#$name#g" -e "s#__ARGVLOG__#$ARGV_LOG#g" -e "s#__LOG__#$LOG#g" \
        -e "s#__HOMEROOT__#$HOMEROOT#g" "$f"
    rm -f "$f.bak"
    chmod +x "$f"
}

# findmnt: reports noexec,nosuid,nodev when "$LOG/mounted-<acct>" exists
# (the marker `mount`'s remount branch below writes), else "not found".
# shellcheck disable=SC2016
stub findmnt '
target="${@: -1}"; acct="$(basename "$target")"
if [[ -f "__LOG__/mounted-$acct" ]]; then
    echo "rw,nosuid,nodev,noexec,relatime"
    exit 0
fi
exit 1
'
# mount: a bare bind is a no-op (logged only); a remount sets the marker
# findmnt reads, mirroring what a real remount,noexec would leave in place.
# shellcheck disable=SC2016
stub mount '
last="${@: -1}"; acct="$(basename "$last")"
case "$*" in
    *remount*) touch "__LOG__/mounted-$acct" ;;
esac
'
# id -nG <acct>: prints the space-separated group list usermod (below)
# maintains in "$LOG/groups/<acct>"; empty (not "found") if never seeded.
# shellcheck disable=SC2016
stub id '
acct="${@: -1}"
cat "__LOG__/groups/$acct" 2>/dev/null || true
'
# usermod -aG g1,g2 <acct>: merges g1,g2 into that same per-account file,
# skipping ones already present (so a second call is a true no-op).
# usermod -c NAME <acct> (issue #39): writes NAME to
# "$LOG/gecos/<acct>", read back by the "getent" stub below -- the same
# per-account-log-file idiom the groups fixture above already uses.
# shellcheck disable=SC2016
stub usermod '
case "$1" in
    -aG)
        groups="$2"; acct="$3"
        f="__LOG__/groups/$acct"
        existing="$(cat "$f" 2>/dev/null || true)"
        IFS="," read -ra add <<< "$groups"
        for g in "${add[@]}"; do
            case " $existing " in *" $g "*) ;; *) existing="$existing $g" ;; esac
        done
        printf "%s\n" "${existing# }" > "$f"
        ;;
    -c)
        name="$2"; acct="$3"
        printf "%s" "$name" > "__LOG__/gecos/$acct"
        ;;
esac
'
# getent passwd <acct>: a minimal passwd(5) line whose GECOS field (5th
# colon-separated field) is whatever the usermod stub above last wrote
# to "$LOG/gecos/<acct>" -- empty if never seeded, matching a real
# account with no GECOS set at all. This box has no real "kid-ada" user
# account to ask (AGENTS.md rule 8: nothing here is ever a real
# system), so this is the entire NSS lookup for the gecos lock's check
# side. The home field (6th) is __HOMEROOT__-prefixed, matching this
# suite's own OMARCHY_KIDS_HOME_ROOT scratch layout -- lib/theme.sh's
# theme_account_home (issue #53) prefers this real-shaped lookup over
# its own OMARCHY_KIDS_HOME_ROOT fallback, the same as a real getent
# would on an actual machine.
# shellcheck disable=SC2016
stub getent '
if [[ "$1" == "passwd" ]]; then
    acct="$2"
    gecos="$(cat "__LOG__/gecos/$acct" 2>/dev/null || true)"
    printf "%s:x:1000:1000:%s:__HOMEROOT__/home/%s:/bin/bash\n" "$acct" "$gecos" "$acct"
    exit 0
fi
exit 1
'
# systemctl --root=R mask UNIT / --root=R enable UNIT...: the two
# subcommands this suite exercises; each is a pure filesystem operation
# under a --root, no live systemd needed, so the check side (getty_ok,
# units_ok, in the script under test) reads real symlink state, not
# anything this stub invents. mask: UNIT -> /dev/null under
# R/etc/systemd/system. enable: UNIT -> /usr/lib/systemd/system/UNIT
# under the .wants directory matching its own suffix (.service ->
# multi-user.target.wants, .socket -> sockets.target.wants, .timer ->
# timers.target.wants) -- exactly the three .wants dirs units_ok reads
# via unit_link (issue #46: the no-kids units case exercises this fix
# path for the first time in this suite).
# shellcheck disable=SC2016
stub systemctl '
root=""
for a in "$@"; do case "$a" in --root=*) root="${a#--root=}" ;; esac; done
if [[ "$1" == "--root="* ]]; then shift; fi
case "$1" in
    mask)
        unit="$2"
        mkdir -p "$root/etc/systemd/system"
        ln -sf /dev/null "$root/etc/systemd/system/$unit"
        ;;
    enable)
        shift
        for unit in "$@"; do
            case "$unit" in
                *.service) target=multi-user.target.wants ;;
                *.socket) target=sockets.target.wants ;;
                *.timer) target=timers.target.wants ;;
                *) continue ;;
            esac
            mkdir -p "$root/etc/systemd/system/$target"
            ln -sf "/usr/lib/systemd/system/$unit" "$root/etc/systemd/system/$target/$unit"
        done
        ;;
esac
'
# lsinitcpio: ignores its argument entirely and just cats a log-controlled
# fixture the test flips between "has the hook" and "does not" -- objcopy
# needs no real ELF/PE input for this since lsinitcpio never reads it.
# shellcheck disable=SC2016
stub objcopy 'exit 0'
# shellcheck disable=SC2016
stub lsinitcpio '
cat "__LOG__/lsinitcpio-output" 2>/dev/null
'
# mkinitcpio -P: "rebuilds" the image by making the next lsinitcpio call
# report the hook present, exactly what a real rebuild would cause.
# shellcheck disable=SC2016
stub mkinitcpio '
[[ "$1" == "-P" ]] && echo "usr/lib/initcpio/hooks/omarchy-kids-unlock" > "__LOG__/lsinitcpio-output"
'
# limine-snapper-sync: present on PATH throughout, purely to prove the
# limine-snapshots lock never calls it in this suite -- OMARCHY_KIDS_ROOT
# is always set here, so posture_root is never empty (see below).
stub limine-snapper-sync ''

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_KIDS_ROOT="$SCRATCH_ROOT"
export OMARCHY_KIDS_HOME_ROOT="$HOMEROOT"
export OMARCHY_PATH

# --- seed every lock as "already provisioned", using lib/posture.sh's
#     own writers directly (never omarchy-kids-provision: this test is
#     about assert re-asserting, not about provisioning) --------------

# shellcheck source=lib/conf.sh
source "$ROOT_DIR/lib/conf.sh"
# shellcheck source=lib/posture.sh
source "$ROOT_DIR/lib/posture.sh"

posture_add_fstab_line kid-ada
posture_add_namespace_lines kid-ada

# Real PAM stacks ship with an auth chain already in them (issue #15,
# R-SEC-2): posture_ensure_parent_unlock_line anchors on the first
# non-comment "auth" line, not a pam_unix.so line (real Omarchy stacks
# don't reliably have one of their own -- see lib/posture.sh's own
# comment). These two fixtures are verbatim /etc/pam.d/sddm and
# /etc/pam.d/omarchy-lock-password from a real Omarchy 4.0.2 box
# (there is no /etc/pam.d/hyprlock on that box -- an earlier version of
# this suite guessed one; confirmed wrong and replaced). Seeded before
# posture_ensure_pam_namespace so the pam_namespace session line lands
# after it, at the bottom, matching how a real stack is laid out (auth
# block, then account/session).
mkdir -p "$SCRATCH_ROOT/etc/pam.d"
cat > "$SCRATCH_ROOT/etc/pam.d/sddm" <<'EOF'
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
cat > "$SCRATCH_ROOT/etc/pam.d/omarchy-lock-password" <<'EOF'
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

cat > "$SCRATCH_ROOT/etc/pam.d/sddm-autologin" <<'EOF'
#%PAM-1.0
auth        required    pam_env.so
auth        required    pam_faillock.so preauth
-auth       [success=2 default=ignore] pam_systemd_home.so
auth        required    pam_permit.so
auth        required    pam_faillock.so authsucc
-auth       optional    pam_kwallet5.so
account     include     system-login
password    include     system-login
session     optional    pam_keyinit.so          force revoke
session     include     system-login
-session    optional    pam_gnome_keyring.so    auto_start
-session    optional    pam_kwallet5.so         auto_start
EOF
posture_ensure_pam_namespace sddm
posture_ensure_pam_namespace systemd-user
posture_ensure_pam_namespace sddm-autologin
posture_write_polkit_admin_rule mark
posture_write_polkit_deny_rule
posture_write_sddm_theme_dropin
posture_write_accountsservice kid-ada fox
posture_write_face_icon "$SHARE/avatars/fox.svg" kid-ada
posture_write_portal_conf mark "$(printf 'kid-ada\tAda Lovelace\tfox')"
printf '%s' 'Ada Lovelace' > "$LOG/gecos/kid-ada"
posture_ensure_parent_unlock_line sddm
posture_ensure_parent_unlock_line omarchy-lock-password

# mount: already mounted noexec (the findmnt stub's marker file)
mkdir -p "$HOMEROOT/home/kid-ada"
touch "$LOG/mounted-kid-ada"

# theme (issue #53): kid-ada's own current theme already matches the
# profile's theme=tokyo-night, via the same theme_apply_for the lock
# itself uses to fix drift, so the first "all ok" run below is really ok.
theme_apply_for kid-ada tokyo-night

# groups: already a member of both
echo "kid-ada omarchy-kids omarchy-kids-6-8" > "$LOG/groups/kid-ada"

# getty@tty2..6 already masked
for n in 2 3 4 5 6; do
    mkdir -p "$SCRATCH_ROOT/etc/systemd/system"
    ln -sf /dev/null "$SCRATCH_ROOT/etc/systemd/system/getty@tty$n.service"
done

# package units already enabled
for u in omarchy-kids-boot-login.service omarchy-kids-boot-login-cleanup.service omarchy-kids-assert.service; do
    mkdir -p "$SCRATCH_ROOT/etc/systemd/system/multi-user.target.wants"
    ln -sf "/usr/lib/systemd/system/$u" "$SCRATCH_ROOT/etc/systemd/system/multi-user.target.wants/$u"
done
mkdir -p "$SCRATCH_ROOT/etc/systemd/system/sockets.target.wants"
ln -sf /usr/lib/systemd/system/omarchy-kids-authd.socket "$SCRATCH_ROOT/etc/systemd/system/sockets.target.wants/omarchy-kids-authd.socket"
ln -sf /usr/lib/systemd/system/omarchy-kids-wifid.socket "$SCRATCH_ROOT/etc/systemd/system/sockets.target.wants/omarchy-kids-wifid.socket"
# omarchy-kids-ask-collect.timer already enabled too (issue #25)
mkdir -p "$SCRATCH_ROOT/etc/systemd/system/timers.target.wants"
ln -sf /usr/lib/systemd/system/omarchy-kids-ask-collect.timer "$SCRATCH_ROOT/etc/systemd/system/timers.target.wants/omarchy-kids-ask-collect.timer"
ln -sf /usr/lib/systemd/system/omarchy-kids-time.timer "$SCRATCH_ROOT/etc/systemd/system/timers.target.wants/omarchy-kids-time.timer"

# hyprland configs already installed (copied from the real share/hyprland
# fixture above, so a byte-for-byte cmp against $SHARE/hyprland passes)
mkdir -p "$ETC/hyprland"
cp "$SHARE"/hyprland/*.lua "$ETC/hyprland/"

# chromium policy: one band's file, already 0640
mkdir -p "$SCRATCH_ROOT/etc/chromium/policies/managed"
CHROMIUM_FILE="$SCRATCH_ROOT/etc/chromium/policies/managed/omarchy-kids-6-8.json"
echo '{}' > "$CHROMIUM_FILE"
chmod 0640 "$CHROMIUM_FILE"

# boot hook: the package's hook file present, a fake UKI to "check", and
# lsinitcpio's fixture already reporting the hook is in it
mkdir -p "$SCRATCH_ROOT/usr/lib/initcpio/hooks" "$SCRATCH_ROOT/boot/EFI/Linux"
touch "$SCRATCH_ROOT/usr/lib/initcpio/hooks/omarchy-kids-unlock"
# The bootloader locks are machine-level and report `warn` where the file
# they assert does not exist (review S11), so the baseline tree has both.
mkdir -p "$SCRATCH_ROOT/boot" "$SCRATCH_ROOT/etc/default"
printf 'editor_enabled: no\ndefault_entry: 2\n' > "$SCRATCH_ROOT/boot/limine.conf"
printf 'MAX_SNAPSHOT_ENTRIES=0\n' > "$SCRATCH_ROOT/etc/default/limine"
touch "$SCRATCH_ROOT/boot/EFI/Linux/arch-linux.efi"
echo "usr/lib/initcpio/hooks/omarchy-kids-unlock" > "$LOG/lsinitcpio-output"

# --- --help / bad args ------------------------------------------------

"$BIN" --help >/dev/null 2>&1; check_eq "$?" 0 "--help exits 0"
"$BIN" --nonsense >/dev/null 2>&1; check_eq "$?" 2 "an unknown flag exits 2"

# --- everything already correct: first full run is all ok -------------

out="$("$BIN")"; st=$?
check_eq "$st" 0 "a fully-provisioned, untouched tree exits 0"
for lock in "fstab:kid-ada" "mount:kid-ada" "namespace:kid-ada" \
    "accountsservice:kid-ada" "gecos:kid-ada" "face:kid-ada" "groups:kid-ada" "theme:kid-ada" "polkit-admin" "polkit-deny" \
    "sddm-theme" "portal-conf" \
    "pam:sddm" "pam:systemd-user" "pam:sddm-autologin" "parent-unlock:sddm" "parent-unlock:omarchy-lock-password" \
    "getty:tty2" "getty:tty3" "getty:tty4" \
    "getty:tty5" "getty:tty6" "units" "hyprland-configs" "chromium-policy:6-8" "boot-hook" \
    "limine-editor" "limine-snapshots"; do
    check_status "$out" "$lock" "ok" "first run: $lock is ok"
done

# --- --quiet on an all-ok tree prints nothing ---------------------------

out="$("$BIN" --quiet)"; st=$?
check_eq "$st" 0 "--quiet on an all-ok tree exits 0"
check_eq "$out" "" "--quiet on an all-ok tree prints nothing"

# --- break each lock in turn; confirm exactly that lock reports fixed,
#     the state is restored, and nothing else moves -----------------

# fstab
sed -i.bak '/kid-ada/d' "$SCRATCH_ROOT/etc/fstab"; rm -f "$SCRATCH_ROOT/etc/fstab.bak"
out="$("$BIN")"
only_this_lock_changed "$out" "fstab:kid-ada" "fstab"
check_eq "$(grep -c "^/home/kid-ada /home/kid-ada none bind,nosuid,nodev,noexec 0 0\$" "$SCRATCH_ROOT/etc/fstab")" "1" \
    "fstab: the line is back"

# mount
rm -f "$LOG/mounted-kid-ada"
out="$("$BIN")"
only_this_lock_changed "$out" "mount:kid-ada" "mount"
check_contains "$(cat "$ARGV_LOG")" "mount -o remount,bind,nosuid,nodev,noexec $HOMEROOT/home/kid-ada" \
    "mount: the remount happened with the right options"
[[ -f "$LOG/mounted-kid-ada" ]] && pass "mount: state is back (mounted noexec again)" \
    || fail "mount: state was not restored"
: > "$ARGV_LOG"

# namespace
NSCONF="$SCRATCH_ROOT/etc/security/namespace.conf"
sed -i.bak '/kid-ada/d' "$NSCONF"; rm -f "$NSCONF.bak"
out="$("$BIN")"
only_this_lock_changed "$out" "namespace:kid-ada" "namespace"
check_eq "$(grep -c "kid-ada\$" "$NSCONF")" "2" "namespace.conf: both lines are back"

# accountsservice
ASFILE="$SCRATCH_ROOT/var/lib/AccountsService/users/kid-ada"
rm -f "$ASFILE"
out="$("$BIN")"
only_this_lock_changed "$out" "accountsservice:kid-ada" "accountsservice"
check_contains "$(cat "$ASFILE" 2>/dev/null)" "Session=omarchy-kids" "accountsservice: the file is back"

# gecos (issue #39): a stray edit clears kid-ada's GECOS field entirely.
rm -f "$LOG/gecos/kid-ada"
out="$("$BIN")"
only_this_lock_changed "$out" "gecos:kid-ada" "gecos"
check_eq "$(cat "$LOG/gecos/kid-ada" 2>/dev/null)" "Ada Lovelace" "gecos: the display name is back"
check_contains "$(cat "$ARGV_LOG")" "usermod -c Ada Lovelace kid-ada" "gecos: usermod -c was called with the profile's name"
: > "$ARGV_LOG"

# face (issue #39, live VM finding): the SDDM face icon file is deleted.
FACE_ICON="$SCRATCH_ROOT/usr/share/sddm/faces/kid-ada.face.icon"
rm -f "$FACE_ICON"
out="$("$BIN")"
only_this_lock_changed "$out" "face:kid-ada" "face"
if [[ -f "$FACE_ICON" ]] && cmp -s "$SHARE/avatars/fox.svg" "$FACE_ICON"; then
    pass "face: the icon file is back, matching the fox avatar"
else
    fail "face: the icon file was not restored"
fi

# groups
echo "kid-ada omarchy-kids" > "$LOG/groups/kid-ada"  # band group missing
out="$("$BIN")"
only_this_lock_changed "$out" "groups:kid-ada" "groups"
check_contains "$(cat "$ARGV_LOG")" "usermod -aG omarchy-kids-6-8 kid-ada" \
    "groups: usermod -aG was called with only the missing group"
check_contains "$(cat "$LOG/groups/kid-ada")" "omarchy-kids-6-8" "groups: kid-ada is back in the band group"
: > "$ARGV_LOG"

# theme (issue #53): kid-ada's own theme drifts to a different one (as if
# they deleted/replaced .../current/theme themselves -- they own the
# containing directory, lib/theme.sh's theme_apply_for header has why).
KID_THEME_NAME_FILE="$HOMEROOT/home/kid-ada/.local/state/omarchy/current/theme.name"
echo "some-other-theme" > "$KID_THEME_NAME_FILE"
out="$("$BIN")"
only_this_lock_changed "$out" "theme:kid-ada" "theme"
check_eq "$(cat "$KID_THEME_NAME_FILE" 2>/dev/null)" "tokyo-night" "theme: kid-ada's theme.name is back to the profile's theme"
check_eq "$(cat "$HOMEROOT/home/kid-ada/.local/state/omarchy/current/theme/colors.toml" 2>/dev/null)" \
    "$(cat "$OMARCHY_PATH/themes/tokyo-night/colors.toml")" \
    "theme: kid-ada's colors.toml is back to tokyo-night's own"

# theme: no override at all is "ok" (nothing to fix) -- a profile written
# before issue #53, or a parent with no theme to copy at provision time.
sed -i.bak '/^theme=/d' "$ETC/kids/kid-ada.conf"; rm -f "$ETC/kids/kid-ada.conf.bak"
out="$("$BIN")"
check_status "$out" "theme:kid-ada" "ok" "theme: no override at all reports ok, not FAIL or a fix"
# restore for the rest of this file's own idempotence checks below
printf 'theme=tokyo-night\n' >> "$ETC/kids/kid-ada.conf"
theme_apply_for kid-ada tokyo-night

# polkit admin
ADMIN_RULE="$SCRATCH_ROOT/etc/polkit-1/rules.d/40-omarchy-kids.rules"
rm -f "$ADMIN_RULE"
out="$("$BIN")"
only_this_lock_changed "$out" "polkit-admin" "polkit-admin"
check_contains "$(cat "$ADMIN_RULE" 2>/dev/null)" '["unix-user:mark"]' "polkit-admin: the rule is back, naming the parent"

# polkit deny
DENY_RULE="$SCRATCH_ROOT/etc/polkit-1/rules.d/41-omarchy-kids-deny.rules"
rm -f "$DENY_RULE"
out="$("$BIN")"
only_this_lock_changed "$out" "polkit-deny" "polkit-deny"
check_contains "$(cat "$DENY_RULE" 2>/dev/null)" "polkit.Result.NO" "polkit-deny: the rule is back"

# sddm-theme
THEME_DROPIN="$SCRATCH_ROOT/etc/sddm.conf.d/zz-omarchy-kids-theme.conf"
rm -f "$THEME_DROPIN"
out="$("$BIN")"
only_this_lock_changed "$out" "sddm-theme" "sddm-theme"
check_contains "$(cat "$THEME_DROPIN" 2>/dev/null)" "Current=omarchy-kids" "sddm-theme: the drop-in is back"

# portal-conf (issue #39): replaces the earlier portal.json + sddm.service
# XHR drop-in design -- see lib/posture.sh's and Main.qml's own header
# comments for why.
PORTAL_CONF="$SCRATCH_ROOT/usr/share/sddm/themes/omarchy-kids/theme.conf.user"
rm -f "$PORTAL_CONF"
out="$("$BIN")"
only_this_lock_changed "$out" "portal-conf" "portal-conf"
check_contains "$(cat "$PORTAL_CONF" 2>/dev/null)" "parent=mark" "portal-conf: the file is back, with the parent"
check_contains "$(cat "$PORTAL_CONF" 2>/dev/null)" "kid-ada:Ada Lovelace:fox" "portal-conf: kid-ada's entry is back"

# pam:sddm
#
# Wiping the whole file also takes the leading "auth include system-login"
# line parent-unlock anchors on with it, so this run reports two non-ok
# lines, not one: "fixed pam:sddm" (pam_fix rebuilds the namespace
# marker from nothing, same as always) and "FAIL parent-unlock:sddm"
# (parent_unlock_fix has no anchor left to insert before -- see below for
# the anchor's restoration and parent-unlock:sddm's own self-heal).
PAMFILE_SDDM="$SCRATCH_ROOT/etc/pam.d/sddm"
rm -f "$PAMFILE_SDDM"
out="$("$BIN")"
check_status "$out" "pam:sddm" "fixed" "pam:sddm: reports fixed"
check_status "$out" "parent-unlock:sddm" "FAIL" "pam:sddm: wiping the file also fails parent-unlock:sddm (no anchor left)"
bad="$(grep -Ev '^ok |^fixed *pam:sddm$|^FAIL *parent-unlock:sddm$' <<<"$out" || true)"
[[ -z "$bad" ]] && pass "pam:sddm: no other lock line changed" \
    || fail "pam:sddm: unexpected non-ok line(s):"$'\n'"$bad"
check_eq "$(grep -c '^session required pam_namespace.so$' "$PAMFILE_SDDM" 2>/dev/null)" "1" "pam:sddm: the line is back"

# Wiping the whole file (above) also took the "auth include system-login"
# line parent-unlock anchors on with it -- pam_fix/posture_ensure_pam_namespace
# only ever cares about the pam_namespace session line, not the rest of a
# real vendor stack, so it doesn't restore one. That's a lock
# omarchy-kids-assert cannot repair on its own in this scenario (there's
# nothing to anchor on); simulate the vendor stack being restored the
# way a real package reinstall would, and confirm parent-unlock:sddm
# self-heals as soon as its anchor exists again.
cat >>"$PAMFILE_SDDM" <<'EOF'
auth        include     system-login
EOF
out="$("$BIN")"
only_this_lock_changed "$out" "parent-unlock:sddm" "parent-unlock:sddm (after its anchor line is restored)"
check_eq "$(grep -c '# omarchy-kids: parent-unlock verifier (R-SEC-2, R-SEC-3)' "$PAMFILE_SDDM")" "1" \
    "parent-unlock:sddm: the marker is back"

# parent-unlock:omarchy-lock-password (exact resulting text, and idempotence)
PAMFILE_LOCKPW="$SCRATCH_ROOT/etc/pam.d/omarchy-lock-password"
posture_remove_parent_unlock_line omarchy-lock-password  # break it using the writer's own inverse, not hand-rolled sed
out="$("$BIN")"
only_this_lock_changed "$out" "parent-unlock:omarchy-lock-password" "parent-unlock:omarchy-lock-password"
expected_lockpw=$'#%PAM-1.0\nauth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120\n# omarchy-kids: parent-unlock verifier (R-SEC-2, R-SEC-3)\nauth       [success=done default=ignore]  pam_exec.so quiet expose_authtok /usr/bin/omarchy-kids-parent-auth\n-auth      [success=2 default=ignore]  pam_systemd_home.so\nauth       [success=1 default=bad]     pam_unix.so try_first_pass nullok\nauth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120\nauth       optional                    pam_permit.so\nauth       required                    pam_env.so\nauth       required                    pam_faillock.so authsucc\naccount    include                     system-local-login'
check_eq "$(cat "$PAMFILE_LOCKPW")" "$expected_lockpw" \
    "parent-unlock:omarchy-lock-password: exact resulting file content (inserted after the leading preauth line)"
out="$("$BIN")"
check_status "$out" "parent-unlock:omarchy-lock-password" "ok" "parent-unlock:omarchy-lock-password: idempotent (a second run reports ok, not fixed)"
check_eq "$(cat "$PAMFILE_LOCKPW")" "$expected_lockpw" "parent-unlock:omarchy-lock-password: unchanged by the idempotent run"

# pam:systemd-user
PAMFILE_SU="$SCRATCH_ROOT/etc/pam.d/systemd-user"
rm -f "$PAMFILE_SU"
out="$("$BIN")"
only_this_lock_changed "$out" "pam:systemd-user" "pam:systemd-user"
check_eq "$(grep -c '^session required pam_namespace.so$' "$PAMFILE_SU" 2>/dev/null)" "1" "pam:systemd-user: the line is back"
check_eq "$(grep -c 'include system-login' "$PAMFILE_SU")" "2" "pam:systemd-user: re-seeded from the vendor file"

# getty@tty4 (one of five, to prove the others are untouched)
rm -f "$SCRATCH_ROOT/etc/systemd/system/getty@tty4.service"
out="$("$BIN")"
only_this_lock_changed "$out" "getty:tty4" "getty:tty4"
[[ -L "$SCRATCH_ROOT/etc/systemd/system/getty@tty4.service" ]] && pass "getty:tty4: the mask symlink is back" \
    || fail "getty:tty4: the mask symlink was not restored"

# hyprland configs (delete one of several)
rm -f "$ETC/hyprland/L2.lua"
out="$("$BIN")"
only_this_lock_changed "$out" "hyprland-configs" "hyprland-configs"
cmp -s "$SHARE/hyprland/L2.lua" "$ETC/hyprland/L2.lua" && pass "hyprland-configs: L2.lua is back, byte-for-byte" \
    || fail "hyprland-configs: L2.lua was not restored correctly"

# chromium policy (wrong mode)
chmod 0644 "$CHROMIUM_FILE"
out="$("$BIN")"
only_this_lock_changed "$out" "chromium-policy:6-8" "chromium-policy:6-8"
mode="$(stat -f '%Lp' "$CHROMIUM_FILE" 2>/dev/null || stat -c '%a' "$CHROMIUM_FILE" 2>/dev/null)"
check_eq "$mode" "640" "chromium-policy:6-8: mode is back to 0640"

# boot hook: lsinitcpio stops reporting the hook -> mkinitcpio -P is run
echo "usr/lib/initcpio/hooks/some-other-hook" > "$LOG/lsinitcpio-output"
out="$("$BIN")"
only_this_lock_changed "$out" "boot-hook" "boot-hook"
check_contains "$(cat "$ARGV_LOG")" "mkinitcpio -P" "boot-hook: mkinitcpio -P was run"
check_contains "$(cat "$LOG/lsinitcpio-output")" "omarchy-kids-unlock" "boot-hook: the rebuilt image now reports the hook"
: > "$ARGV_LOG"

# --- second run after every fix above: everything is ok again ----------

out="$("$BIN")"; st=$?
check_eq "$st" 0 "second run (everything fixed) exits 0"
still_bad="$(grep -Ev '^ok ' <<<"$out" || true)"
[[ -z "$still_bad" ]] && pass "second run: every lock reports ok" \
    || fail "second run: still non-ok line(s):"$'\n'"$still_bad"

# --- --dry-run reports without writing ----------------------------------

sed -i.bak '/kid-ada/d' "$SCRATCH_ROOT/etc/fstab"; rm -f "$SCRATCH_ROOT/etc/fstab.bak"
out="$("$BIN" --dry-run)"; st=$?
check_eq "$st" 0 "--dry-run still exits 0"
check_status "$out" "fstab:kid-ada" "would-fix" "--dry-run: fstab:kid-ada reports would-fix"
check_eq "$(grep -c "kid-ada" "$SCRATCH_ROOT/etc/fstab" 2>/dev/null)" "0" "--dry-run: fstab was not actually written"
"$BIN" >/dev/null  # restore for the no-profiles section below, which reuses this tree's stubs but not its ETC

# --- no profiles: silent no-op with --quiet -----------------------------

EMPTY_ETC="$TMP/etc-empty/omarchy-kids"
mkdir -p "$EMPTY_ETC/kids"
out="$(OMARCHY_KIDS_ETC="$EMPTY_ETC" "$BIN" --quiet)"; st=$?
check_eq "$st" 0 "no profiles: exits 0"
check_eq "$out" "" "no profiles: --quiet prints nothing"
out2="$(OMARCHY_KIDS_ETC="$EMPTY_ETC" "$BIN")"; st2=$?
check_eq "$st2" 0 "no profiles, not quiet: still exits 0"
check_contains "$out2" "nothing else to assert" "no profiles, not quiet: names why"

# --- no profiles, but the "units" lock is still asserted -- and fixed if
#     broken -- since it's machine-level, not per-kid (issue #46: a fresh
#     install before the first kid, or right after omarchy-kids-remove
#     disables them again, still needs the package's own units back) ----

check_status "$out2" "units" "ok" "no profiles: units is still checked (not skipped) with zero kids"

BOOT_LOGIN_LINK="$SCRATCH_ROOT/etc/systemd/system/multi-user.target.wants/omarchy-kids-boot-login.service"
rm -f "$BOOT_LOGIN_LINK"
out3="$(OMARCHY_KIDS_ETC="$EMPTY_ETC" "$BIN")"; st3=$?
check_eq "$st3" 0 "no profiles, units broken: still exits 0 once fixed"
check_status "$out3" "units" "fixed" "no profiles: units is fixed even though no kid is provisioned"
check_contains "$out3" "nothing else to assert" "no profiles, units broken: the no-kids line still explains why nothing else ran"
[[ -L "$BOOT_LOGIN_LINK" ]] && pass "no profiles: the boot-login unit's enable symlink is restored" \
    || fail "no profiles: the boot-login unit's enable symlink was not restored"

# idempotent: a second no-kids run with units already fixed is all ok again.
out4="$(OMARCHY_KIDS_ETC="$EMPTY_ETC" "$BIN")"
check_status "$out4" "units" "ok" "no profiles: units is idempotent after being fixed with zero kids"

# --- Limine editor lock (V6) -------------------------------------------------
mkdir -p "$SCRATCH_ROOT/boot" "$ETC/kids"
printf 'name=Ada\navatar=fox\nband=6-8\npassword=set\nonboarded=no\n' > "$ETC/kids/kid-ada.conf"  # a provisioned kid again, so machine locks run
printf 'default_entry: 2\ninterface_branding: Omarchy Bootloader\n' > "$SCRATCH_ROOT/boot/limine.conf"  # no editor_enabled line
out="$("$BIN" 2>&1)"
if grep -q "fixed *limine-editor" <<<"$out" && head -1 "$SCRATCH_ROOT/boot/limine.conf" | grep -qx 'editor_enabled: no'; then echo "PASS  limine-editor: editor_enabled: no inserted at the top"; else echo "FAIL  limine-editor fix ($out)"; exit 1; fi
out="$("$BIN" 2>&1)"
if grep -q "ok *limine-editor" <<<"$out" && [[ "$(grep -c '^editor_enabled:' "$SCRATCH_ROOT/boot/limine.conf")" == "1" ]]; then echo "PASS  limine-editor: idempotent"; else echo "FAIL  limine-editor idempotence ($out)"; exit 1; fi

# --- Limine snapshot entries lock (V6, issue #38) -----------------------

LIMINE_DEFAULT="$SCRATCH_ROOT/etc/default/limine"
mkdir -p "$SCRATCH_ROOT/etc/default"
: > "$ARGV_LOG"

# hide (the default: no boot.snapshot_entries override yet) fixes a
# pre-existing, non-zero MAX_SNAPSHOT_ENTRIES, remembering it in a comment.
printf 'KERNEL_CMDLINE[default]="quiet"\nMAX_SNAPSHOT_ENTRIES=10\n' > "$LIMINE_DEFAULT"
out="$("$BIN")"
check_status "$out" "limine-snapshots" "fixed" "limine-snapshots (hide, default): reports fixed"
check_eq "$(grep -c '^MAX_SNAPSHOT_ENTRIES=0$' "$LIMINE_DEFAULT")" "1" "limine-snapshots: MAX_SNAPSHOT_ENTRIES=0 is set"
check_eq "$(grep -c '^# omarchy-kids: was MAX_SNAPSHOT_ENTRIES=10$' "$LIMINE_DEFAULT")" "1" \
    "limine-snapshots: the old value (10) is remembered"
check_contains "$(cat "$LIMINE_DEFAULT")" 'KERNEL_CMDLINE[default]="quiet"' "limine-snapshots: unrelated lines are kept"
check_eq "$(grep -c "limine-snapper-sync" "$ARGV_LOG")" "0" \
    "limine-snapshots: limine-snapper-sync is not run against a test root"

# idempotent: a second run is ok, and nothing doubles up.
out="$("$BIN")"
check_status "$out" "limine-snapshots" "ok" "limine-snapshots (hide): idempotent"
check_eq "$(grep -c '^MAX_SNAPSHOT_ENTRIES=' "$LIMINE_DEFAULT")" "1" "limine-snapshots: still exactly one MAX_SNAPSHOT_ENTRIES line"

# show: restores the remembered value and drops our lines.
conf_set "$ETC/machine.conf" boot.snapshot_entries show
out="$("$BIN")"
check_status "$out" "limine-snapshots" "fixed" "limine-snapshots (show): reports fixed"
check_eq "$(grep -c '^MAX_SNAPSHOT_ENTRIES=10$' "$LIMINE_DEFAULT")" "1" "limine-snapshots: the old value (10) is restored"
check_eq "$(grep -c 'omarchy-kids: was MAX_SNAPSHOT_ENTRIES' "$LIMINE_DEFAULT")" "0" "limine-snapshots: the marker comment is gone"

# idempotent under show, too.
out="$("$BIN")"
check_status "$out" "limine-snapshots" "ok" "limine-snapshots (show): idempotent"

# back to hide: re-hides whatever value is there now (10), re-recording it.
conf_set "$ETC/machine.conf" boot.snapshot_entries hide
out="$("$BIN")"
check_status "$out" "limine-snapshots" "fixed" "limine-snapshots (back to hide): reports fixed"
check_eq "$(grep -c '^MAX_SNAPSHOT_ENTRIES=0$' "$LIMINE_DEFAULT")" "1" "limine-snapshots: hidden again"
check_eq "$(grep -c '^# omarchy-kids: was MAX_SNAPSHOT_ENTRIES=10$' "$LIMINE_DEFAULT")" "1" "limine-snapshots: value re-recorded"

# restore path with no remembered value at all: show just drops the line.
printf 'MAX_SNAPSHOT_ENTRIES=0\n' > "$LIMINE_DEFAULT"  # our line present, but no "was" comment (e.g. after an upgrade)
conf_set "$ETC/machine.conf" boot.snapshot_entries show
out="$("$BIN")"
check_status "$out" "limine-snapshots" "fixed" "limine-snapshots (show, no remembered value): reports fixed"
check_eq "$(grep -c 'MAX_SNAPSHOT_ENTRIES' "$LIMINE_DEFAULT")" "0" \
    "limine-snapshots: with nothing remembered, the line is simply removed"

# no /etc/default/limine at all (no Limine, or a fresh test tree): nothing to assert.
rm -f "$LIMINE_DEFAULT"
conf_del "$ETC/machine.conf" boot.snapshot_entries
out="$("$BIN")"
check_status "$out" "limine-snapshots" "warn" \
    "limine-snapshots: no /etc/default/limine reports warn, never a silent ok (review S11)"

# --- review S5: limine-editor is machine-level, NOT nested under the hook ---
#
# It used to sit inside `if [[ -f "$HOOK_FILE" ]]`, mis-indented so it read
# as though it were outside. A box with no unlock hook -- never ran
# mkinitcpio -P, hook removed, not Limine-plus-hook -- is exactly the box
# where an unlocked Limine editor hands a kid init=/bin/bash.

printf 'MAX_SNAPSHOT_ENTRIES=0\n' > "$LIMINE_DEFAULT"
printf 'default_entry: 2\n' > "$SCRATCH_ROOT/boot/limine.conf"   # editor NOT disabled
mv "$SCRATCH_ROOT/usr/lib/initcpio/hooks/omarchy-kids-unlock" "$SCRATCH_ROOT/hook.bak"

out="$("$BIN" 2>&1)"
if grep -qE '^(ok|fixed|warn|FAIL|would-fix) +boot-hook' <<<"$out"; then
    fail "no hook file: boot-hook should not be reported at all"
else
    pass "no hook file: boot-hook is correctly skipped"
fi
check_status "$out" "limine-editor" "fixed" \
    "no hook file: limine-editor is STILL asserted and fixed (review S5)"
check_eq "$(head -1 "$SCRATCH_ROOT/boot/limine.conf")" "editor_enabled: no" \
    "no hook file: editor_enabled: no was actually written"

out="$("$BIN" 2>&1)"
check_status "$out" "limine-editor" "ok" "no hook file: limine-editor stays ok on the next run"

# ...and with no limine.conf either, it warns rather than reading green.
rm -f "$SCRATCH_ROOT/boot/limine.conf"
out="$("$BIN" 2>&1)"
check_status "$out" "limine-editor" "warn" \
    "no limine.conf: limine-editor reports warn, never a silent ok (review S11)"

mv "$SCRATCH_ROOT/hook.bak" "$SCRATCH_ROOT/usr/lib/initcpio/hooks/omarchy-kids-unlock"

echo "assert-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
