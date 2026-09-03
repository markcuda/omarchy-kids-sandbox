#!/bin/bash
# Tests bin/omarchy-kids-provision and lib/posture.sh (SPEC.md R-FND-2..6,
# R-SEC-3..5, R-LOGIN-3, R-DESK-1, Appendix B) and issue #10's three
# findings: (a) luks-slots is a full rewrite after every slot change, (b)
# omarchy-provision-user runs when present, else migration markers are
# written, (c) pam_namespace lands on both sddm and systemd-user.
#
# Fully self-contained: every system command that would write outside this
# test's own scratch dir (useradd, usermod, chpasswd, mount, umount,
# systemctl, userdel, cryptsetup, omarchy-provision-user) is a fake on a
# stub PATH that only logs its argv (and, for a couple, fakes just enough
# behavior -- creating a home dir, printing cryptsetup's "Key slot N
# unlocked." line -- for the script under test to react to). Never touches
# the real /etc, /var, or /home (AGENTS.md rule 8).
# shellcheck disable=SC2015 # "A && B || C" below is always used with B, C that can't fail
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT_DIR/bin/omarchy-kids-provision"
CONFBIN="$ROOT_DIR/bin/omarchy-kids-conf"

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP provision-test.sh: python3 not found (needed by omarchy-kids-conf)"
    exit 0
fi

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
count_occurrences() { # haystack needle -> count
    local needle="$2" n=0 rest="$1"
    while [[ "$rest" == *"$needle"* ]]; do
        n=$((n + 1))
        rest="${rest#*"$needle"}"
    done
    printf '%s' "$n"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- scratch tree ------------------------------------------------------

ETC="$TMP/etc/omarchy-kids"
SHARE="$TMP/share/omarchy-kids"
SCRATCH_ROOT="$TMP/root"       # OMARCHY_KIDS_ROOT
mkdir -p "$SCRATCH_ROOT/usr/lib/pam.d"
mkdir -p "$SCRATCH_ROOT/usr/lib/pam.d"; printf 'account include system-login\nsession include system-login\n' > "$SCRATCH_ROOT/usr/lib/pam.d/systemd-user"
HOMEROOT="$TMP/homeroot"       # OMARCHY_KIDS_HOME_ROOT
STUBS="$TMP/stubs"
LOG="$TMP/log"
ARGV_LOG="$LOG/argv.log"

mkdir -p "$ETC/kids" "$SHARE/bands" "$SHARE/packs" "$SHARE/avatars" "$SHARE/policy" "$SCRATCH_ROOT" "$HOMEROOT" "$STUBS" "$LOG"
cp "$ROOT_DIR/share/bands/bands.toml" "$SHARE/bands/"
cp "$ROOT_DIR"/share/packs/*.toml "$SHARE/packs/"
cp "$ROOT_DIR"/share/avatars/*.svg "$SHARE/avatars/"
# issue #44: install_kids_chromium_flags's source file.
cp "$ROOT_DIR/share/policy/chromium-flags.conf" "$SHARE/policy/"
touch "$ARGV_LOG"

# The machine's owner (SPEC.md's "parent"); machine setup writes this
# before any kid is ever provisioned, and slot 0 in luks-slots, both
# preconditions omarchy-kids-provision assumes are already in place.
cat > "$ETC/machine.conf" <<'EOF'
parent=mark
EOF
mkdir -p "$HOMEROOT/home/mark"
echo "0=mark:omarchy.desktop" > "$ETC/luks-slots"

# Real SDDM stacks ship with a real auth chain already in them (issue
# #15, R-SEC-2): "add" inserts the parent-unlock pam_exec line right
# before the first non-comment "auth" line, since sddm's own first auth
# line isn't a leading pam_faillock preauth line (lib/posture.sh's
# posture_ensure_parent_unlock_line documents the placement rule in
# full). This is the verbatim /etc/pam.d/sddm from a real Omarchy 4.0.2
# box -- it has no pam_unix.so line of its own at all, which is exactly
# why the anchor is "the first auth line", not "the pam_unix.so line".
# No omarchy-lock-password file is seeded here on purpose: that stack
# legitimately might not exist yet at kid-provisioning time (the lock
# screen hasn't been configured), which "add" must tolerate (a warning,
# not a failure) -- see test/shell.d/parent-unlock-test.sh for that
# stack's own shape (the verbatim real /etc/pam.d/omarchy-lock-password)
# and test/shell.d/assert-test.sh for the break/fix cycle on it.
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

# --- stub PATH -----------------------------------------------------------

# stub NAME EXTRA — writes an executable $STUBS/NAME that appends its own
# argv (space-joined, one line -- none of this suite's arguments carry a
# space, so plain %s stays diffable; %q would escape commas for brace-
# expansion safety and make every assertion below have to know that) to
# $ARGV_LOG, then runs EXTRA (literal shell text; write it single-quoted
# at the call site, using __LOG__ for $LOG, so nothing in it is expanded
# until the stub itself runs), then exits 0.
stub() {
    local name="$1" extra="${2:-}" f="$STUBS/$1"
    cat > "$f" <<'EOF'
#!/bin/bash
{ printf '%s' "__NAME__"; printf ' %s' "$@"; printf '\n'; } >> "__ARGVLOG__"
EOF
    [[ -n "$extra" ]] && printf '%s\n' "$extra" >> "$f"
    echo 'exit 0' >> "$f"
    sed -i.bak -e "s#__NAME__#$name#g" -e "s#__ARGVLOG__#$ARGV_LOG#g" -e "s#__LOG__#$LOG#g" "$f"
    rm -f "$f.bak"
    chmod +x "$f"
}

# shellcheck disable=SC2016 # single-quoted on purpose: expands later, inside the stub script
stub useradd 'acct="${@: -1}"; mkdir -p "$OMARCHY_KIDS_HOME_ROOT/home/$acct"'
stub usermod
stub userdel
stub mount
stub umount
stub systemctl
stub gpasswd
# shellcheck disable=SC2016
stub chpasswd 'cat >> "__LOG__/chpasswd.stdin"'
# shellcheck disable=SC2016
stub cryptsetup '
case "$1" in
    open)
        n=$(( $(cat "__LOG__/luks-slot-counter" 2>/dev/null || echo 2) + 1 ))
        echo "$n" > "__LOG__/luks-slot-counter"
        echo "Key slot $n unlocked."
        ;;
esac
'
stub omarchy-provision-user
stub groupadd
stub runuser

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_KIDS_ROOT="$SCRATCH_ROOT"
export OMARCHY_KIDS_HOME_ROOT="$HOMEROOT"
export DRY_RUN=0

SLUG="$("$CONFBIN" slug "Ada Lovelace")"

# --- add: refuses --no-password outside 3-5 -------------------------------

out="$("$BIN" add "Nope" --band 6-8 --no-password 2>&1)"; st=$?
check_eq "$st" 2 "add --no-password outside 3-5 exits 2"
check_contains "$out" "only allowed for band 3-5" "add --no-password outside 3-5 names the reason"
[[ -e "$ETC/kids/kid-nope.conf" ]] && fail "add --no-password outside 3-5 must not create a profile" \
    || pass "add --no-password outside 3-5 created no profile"

# --- add: needs --password-stdin or --no-password -------------------------

out="$("$BIN" add "Nothing" --band 6-8 2>&1)"; st=$?
check_eq "$st" 2 "add with neither password option exits 2"

# --- add: default DRY_RUN=1 writes nothing --------------------------------

: > "$ARGV_LOG"
out="$(printf 'somepassword\n' | DRY_RUN=1 "$BIN" add "Dry Kid" --band 6-8 --avatar fox --password-stdin 2>&1)"
check_contains "$out" "[dry-run]" "default DRY_RUN=1 prints dry-run lines"
[[ -e "$ETC/kids/kid-drykid.conf" ]] && fail "DRY_RUN=1 must not write a profile" || pass "DRY_RUN=1 wrote no profile"
[[ -s "$ARGV_LOG" ]] && fail "DRY_RUN=1 must not invoke useradd/chpasswd/etc" || pass "DRY_RUN=1 invoked no real commands"

# --- add: kid-ada, band 6-8, password + LUKS slot -------------------------

: > "$ARGV_LOG"
out="$(printf 'kidpass1\nparentpass1\n' | "$BIN" add "Ada Lovelace" --band 6-8 --avatar fox \
    --password-stdin --parent-password-stdin --luks-device /dev/fake0 2>&1)"; st=$?
argv="$(cat "$ARGV_LOG")"

check_eq "$st" 0 "add kid-ada exits 0"
check_contains "$out" "Adding kid 'Ada Lovelace' as $SLUG" "add kid-ada announces the account name"

check_contains "$argv" "useradd -m -s /bin/bash -G omarchy-kids,omarchy-kids-6-8 $SLUG" "add: useradd argv is exact"
check_contains "$argv" "chpasswd" "add: chpasswd was invoked"
check_contains "$(cat "$LOG/chpasswd.stdin")" "$SLUG:kidpass1" "add: chpasswd got 'account:password' on stdin, never argv"
check_not_contains "$argv" "kidpass1" "add: the kid password never appears in any command's argv"
check_not_contains "$argv" "parentpass1" "add: the parent password never appears in any command's argv"

check_eq "$(grep -c '^name=Ada Lovelace$' "$ETC/kids/$SLUG.conf")" "1" "profile: name=Ada Lovelace"
check_eq "$(grep -c '^avatar=fox$' "$ETC/kids/$SLUG.conf")" "1" "profile: avatar=fox"
check_eq "$(grep -c '^band=6-8$' "$ETC/kids/$SLUG.conf")" "1" "profile: band=6-8"
check_eq "$(grep -c '^password=set$' "$ETC/kids/$SLUG.conf")" "1" "profile: password=set"
check_eq "$(grep -c '^onboarded=no$' "$ETC/kids/$SLUG.conf")" "1" "profile: onboarded=no"

FSTAB="$SCRATCH_ROOT/etc/fstab"
check_eq "$(grep -c "^/home/$SLUG /home/$SLUG none bind,nosuid,nodev,noexec 0 0\$" "$FSTAB")" "1" \
    "fstab: exact bind-mount line for $SLUG"
check_contains "$argv" "mount -o remount,bind,nosuid,nodev,noexec $HOMEROOT/home/$SLUG" \
    "add: remount happened with the right options"

ADMIN_RULE="$SCRATCH_ROOT/etc/polkit-1/rules.d/40-omarchy-kids.rules"
DENY_RULE="$SCRATCH_ROOT/etc/polkit-1/rules.d/41-omarchy-kids-deny.rules"
check_contains "$(cat "$ADMIN_RULE" 2>/dev/null)" '["unix-user:mark"]' "polkit admin rule names the parent, not root"
check_contains "$(cat "$DENY_RULE" 2>/dev/null)" "polkit.Result.NO" "polkit deny rule denies"
check_contains "$(cat "$DENY_RULE" 2>/dev/null)" "org.freedesktop.systemd1.manage-units" "polkit deny rule covers systemd manage-units"
check_contains "$(cat "$DENY_RULE" 2>/dev/null)" "org.omarchy." "polkit deny rule covers org.omarchy.*"

for n in 2 3 4 5 6; do
    check_contains "$argv" "systemctl --root=$SCRATCH_ROOT mask getty@tty$n.service" "add masks getty@tty$n"
done

NSCONF="$SCRATCH_ROOT/etc/security/namespace.conf"
check_eq "$(grep -c "^/tmp /tmp/kids-inst/ tmpfs:mntopts=nosuid,nodev,noexec $SLUG\$" "$NSCONF")" "1" \
    "namespace.conf: exact /tmp line for $SLUG"
check_eq "$(grep -c "^/dev/shm /dev/shm/kids-inst/ tmpfs:mntopts=nosuid,nodev,noexec $SLUG\$" "$NSCONF")" "1" \
    "namespace.conf: exact /dev/shm line for $SLUG"

for stack in sddm systemd-user; do
    PAMFILE="$SCRATCH_ROOT/etc/pam.d/$stack"
    check_eq "$(grep -c '^session required pam_namespace.so$' "$PAMFILE" 2>/dev/null)" "1" \
        "pam.d/$stack has exactly one pam_namespace.so line"
    [[ $stack == systemd-user ]] && check_eq "$(grep -c 'include system-login' "$PAMFILE")" "2" "pam.d/systemd-user was seeded from the vendor file"
done

# --- add: R-SEC-2 parent-unlock line inserted into pam.d/sddm ------------
#
# sddm's real first "auth" line isn't a leading pam_faillock preauth
# line, so lib/posture.sh's placement rule inserts right BEFORE it --
# ahead of the whole "include system-login" chain -- rather than after
# it (see lib/posture.sh's own comment on why the rule is anchor-based,
# not pam_unix.so-based: this real fixture has no pam_unix.so line at
# all to jump around).
SDDM_PAMFILE="$SCRATCH_ROOT/etc/pam.d/sddm"
MARKER="# omarchy-kids: parent-unlock verifier (R-SEC-2, R-SEC-3)"
PAM_EXEC_LINE="pam_exec.so quiet expose_authtok /usr/bin/omarchy-kids-parent-auth"
check_eq "$(grep -c "^$MARKER\$" "$SDDM_PAMFILE")" "1" "pam.d/sddm: parent-unlock marker inserted exactly once"
check_eq "$(grep -c "^auth       \[success=done default=ignore\]  $PAM_EXEC_LINE\$" "$SDDM_PAMFILE")" "1" \
    "pam.d/sddm: parent-unlock line uses the fixed success=done control"
expected_sddm=$'#%PAM-1.0\n'"$MARKER"$'\nauth       [success=done default=ignore]  '"$PAM_EXEC_LINE"$'\nauth        include     system-login\n-auth       optional    pam_kwallet5.so\naccount     include     system-login\npassword    include     system-login\nsession     optional    pam_keyinit.so          force revoke\nsession     include     system-login\n-session    optional    pam_gnome_keyring.so    auto_start\n-session    optional    pam_kwallet5.so         auto_start\n# omarchy-kids: pam_namespace for kid sessions (R-FND-2a)\nsession required pam_namespace.so'
check_eq "$(cat "$SDDM_PAMFILE")" "$expected_sddm" "pam.d/sddm: exact resulting file content after add"
check_contains "$out" "warning: could not add the parent-unlock line to pam.d/omarchy-lock-password" \
    "add: warns (does not fail) when the lock-screen PAM stack doesn't exist yet"

check_contains "$argv" "cryptsetup luksAddKey --batch-mode --key-file=" "add: cryptsetup luksAddKey called"
check_contains "$argv" "/dev/fake0" "add: cryptsetup ran against the given --luks-device"
check_contains "$argv" "cryptsetup open --test-passphrase --verbose --key-file=" "add: cryptsetup open --test-passphrase called"
check_contains "$out" "LUKS slot 3 added for $SLUG" "add: the discovered slot (3) is reported"
check_eq "$(grep -c "^3=$SLUG\$" "$ETC/luks-slots")" "1" "luks-slots: slot 3 mapped to $SLUG"
check_eq "$(grep -c '^0=mark:omarchy.desktop$' "$ETC/luks-slots")" "1" "luks-slots: the parent's slot 0 line survives the rewrite"

ASFILE="$SCRATCH_ROOT/var/lib/AccountsService/users/$SLUG"
check_contains "$(cat "$ASFILE" 2>/dev/null)" "Session=omarchy-kids" "AccountsService pins the kid session"
check_contains "$(cat "$ASFILE" 2>/dev/null)" "Icon=/usr/share/omarchy-kids/avatars/fox.svg" "AccountsService icon path"

THEME_DROPIN="$SCRATCH_ROOT/etc/sddm.conf.d/zz-omarchy-kids-theme.conf"
check_contains "$(cat "$THEME_DROPIN" 2>/dev/null)" "Current=omarchy-kids" "add: SDDM portal theme selected (R-LOGIN)"

# --- add: issue #39 -- GECOS display name, the face icon, theme.conf.user --

check_contains "$argv" "usermod -c Ada Lovelace $SLUG" "add: GECOS set via usermod -c with the display name"

FACE_ICON="$SCRATCH_ROOT/usr/share/sddm/faces/$SLUG.face.icon"
if [[ -f "$FACE_ICON" ]] && cmp -s "$SHARE/avatars/fox.svg" "$FACE_ICON"; then
    pass "add: the SDDM face icon is written, matching the fox avatar"
else
    fail "add: the SDDM face icon was not written at $FACE_ICON"
fi

PORTAL_CONF="$SCRATCH_ROOT/usr/share/sddm/themes/omarchy-kids/theme.conf.user"
check_contains "$(cat "$PORTAL_CONF" 2>/dev/null)" "parent=mark" "theme.conf.user: parent is the machine owner"
check_contains "$(cat "$PORTAL_CONF" 2>/dev/null)" "kids=$SLUG:Ada Lovelace:fox" "theme.conf.user: $SLUG's name and avatar"

check_contains "$argv" "mount --bind $OMARCHY_KIDS_HOME_ROOT/home/$SLUG $OMARCHY_KIDS_HOME_ROOT/home/$SLUG" "add: bind mount created before the noexec remount"
check_contains "$argv" "runuser -l $SLUG -c omarchy-provision-user --first-install" "add: omarchy-provision-user --first-install runs as the kid via runuser"
check_contains "$argv" "groupadd -f omarchy-kids" "add: groups are created defensively"

# --- issue #44: the kid's own chromium-flags.conf is overridden -----------
# Whatever ~/.config/chromium-flags.conf omarchy-provision-user (or its
# fallback) left, "add" writes over it with Kids Mode's own copy so a kid
# running `chromium` from a terminal never hits the "disabled by the
# administrator" modal Omarchy's --load-extension flag produces under
# the kids policy.

FLAGS_FILE="$HOMEROOT/home/$SLUG/.config/chromium-flags.conf"
if [[ -f "$FLAGS_FILE" ]]; then
    pass "add: wrote $SLUG's own chromium-flags.conf"
    flags_content="$(cat "$FLAGS_FILE")"
    check_contains "$flags_content" "--ozone-platform=wayland" "chromium-flags.conf: keeps Omarchy's Wayland flag"
    check_not_contains "$flags_content" "--load-extension" "chromium-flags.conf: strips --load-extension (issue #44)"
    mode="$(stat -f '%Lp' "$FLAGS_FILE" 2>/dev/null || stat -c '%a' "$FLAGS_FILE" 2>/dev/null)"
    check_eq "$mode" "644" "chromium-flags.conf: mode is 0644"
else
    fail "add: no chromium-flags.conf written for $SLUG"
fi

# --- add: slug collision gets -2 ------------------------------------------

: > "$ARGV_LOG"
out2="$(printf 'kidpass2\n' | "$BIN" add "Ada Lovelace" --band 6-8 --avatar bear --password-stdin 2>&1)"
check_contains "$out2" "as $SLUG-2" "second kid with the same name gets the -2 suffix"
[[ -e "$ETC/kids/$SLUG-2.conf" ]] && pass "profile written for $SLUG-2" || fail "no profile for $SLUG-2"

# --- idempotence: polkit/pam edits are not duplicated by a second add -----

check_eq "$(count_occurrences "$(cat "$ADMIN_RULE")" 'polkit.addAdminRule')" "1" \
    "polkit admin rule still has exactly one rule block after a second add"
check_eq "$(grep -c '^session required pam_namespace.so$' "$SCRATCH_ROOT/etc/pam.d/sddm")" "1" \
    "pam.d/sddm still has exactly one pam_namespace.so line after a second add"
check_eq "$(grep -c "^$MARKER\$" "$SCRATCH_ROOT/etc/pam.d/sddm")" "1" \
    "pam.d/sddm still has exactly one parent-unlock marker after a second add"
check_eq "$(grep -c "$SLUG-2\$" "$NSCONF")" "2" "namespace.conf gained exactly 2 lines (not more) for the second kid"
check_eq "$(grep -c "^0=mark:omarchy.desktop\$" "$ETC/luks-slots")" "1" \
    "luks-slots still has exactly one slot-0 line after a second add"

check_contains "$(cat "$PORTAL_CONF" 2>/dev/null)" "$SLUG:Ada Lovelace:fox" \
    "theme.conf.user: gained the second kid too ($SLUG's entry still present)"
check_contains "$(cat "$PORTAL_CONF" 2>/dev/null)" "$SLUG-2:Ada Lovelace:bear" \
    "theme.conf.user: $SLUG-2's name and avatar"

# --- add: --no-password only for band 3-5 --------------------------------

: > "$ARGV_LOG"
"$BIN" add "Sam" --band 3-5 --avatar bear --no-password --luks-device /dev/fake0 >/dev/null 2>&1; st=$?
SLUG_SAM="$("$CONFBIN" slug "Sam")"
check_eq "$st" 0 "add --no-password for band 3-5 succeeds"
check_contains "$(cat "$ARGV_LOG")" "usermod -L $SLUG_SAM" "add --no-password locks the account with usermod -L"
check_not_contains "$(cat "$ARGV_LOG")" "chpasswd" "add --no-password never calls chpasswd"
check_eq "$(grep -c '^password=none$' "$ETC/kids/$SLUG_SAM.conf")" "1" "profile: password=none for a locked account"
check_not_contains "$(cat "$ARGV_LOG")" "luksAddKey" "add --no-password never touches LUKS, even with a device given"

# --- add: password below the band minimum is refused -----------------------

out4="$(printf 'ab\n' | "$BIN" add "Shorty" --band 6-8 --password-stdin 2>&1)"; st=$?
check_eq "$st" 2 "add refuses a password shorter than the band minimum"
check_contains "$out4" "too short" "add: short-password message names the reason"

# --- omarchy-provision-user missing: migration markers are written --------

rm -f "$STUBS/omarchy-provision-user"
out5="$(printf 'kidpass3\n' | "$BIN" add "Ben" --band 6-8 --avatar fox --password-stdin 2>&1)"
SLUG_BEN="$("$CONFBIN" slug "Ben")"
MARKER="$HOMEROOT/home/$SLUG_BEN/.local/state/omarchy/migrations.log"
check_not_contains "$out5" "omarchy-provision-user" "add without omarchy-provision-user on PATH doesn't try to run it"
[[ -f "$MARKER" ]] && pass "migration marker file written when omarchy-provision-user is absent" \
    || fail "no migration marker at $MARKER"
stub omarchy-provision-user  # restore for the rest of the test

# --- list ------------------------------------------------------------------

list_out="$("$BIN" list)"
check_contains "$list_out" "$SLUG" "list shows $SLUG"
check_contains "$list_out" "$SLUG-2" "list shows $SLUG-2"

# --- --help / no args --------------------------------------------------

"$BIN" --help >/dev/null 2>&1; check_eq "$?" 0 "--help exits 0"
"$BIN" >/dev/null 2>&1; check_eq "$?" 2 "no arguments exits 2"

# --- remove: reverses kid-ada (has a LUKS slot, home moved) -----------------

: > "$ARGV_LOG"
export OMARCHY_KIDS_LUKS_DEVICE=/dev/fake0  # remove has no --luks-device flag
"$BIN" remove "$SLUG" >/dev/null 2>&1; st=$?
argv6="$(cat "$ARGV_LOG")"

check_eq "$st" 0 "remove $SLUG exits 0"
check_contains "$argv6" "cryptsetup luksKillSlot --batch-mode /dev/fake0 3" "remove: killed the exact LUKS slot (3)"
check_eq "$(grep -c "^3=$SLUG\$" "$ETC/luks-slots")" "0" "luks-slots: $SLUG's slot is gone"
check_eq "$(grep -c '^0=mark:omarchy.desktop$' "$ETC/luks-slots")" "1" "luks-slots: the parent's slot 0 survives remove's rewrite"
check_eq "$(grep -c "$SLUG-2\$" "$ETC/luks-slots")" "0" "luks-slots: never had an entry for $SLUG-2 (no LUKS device was given for it)"

check_eq "$(grep -c "$SLUG\$" "$NSCONF")" "0" "namespace.conf lines for $SLUG are gone (only $SLUG-2's remain)"
[[ -e "$ASFILE" ]] && fail "AccountsService file for $SLUG should be removed" || pass "AccountsService file for $SLUG removed"
check_eq "$(grep -c "^/home/$SLUG /home/$SLUG " "$FSTAB")" "0" "fstab line for $SLUG removed"
check_contains "$argv6" "umount $HOMEROOT/home/$SLUG" "remove: unmounted the home"
[[ -e "$ETC/kids/$SLUG.conf" ]] && fail "profile for $SLUG should be removed" || pass "profile for $SLUG removed"
check_contains "$argv6" "userdel $SLUG" "remove: userdel called"
[[ -d "$HOMEROOT/home/mark/Kids Mode/Ada Lovelace" ]] && pass "home moved to <parent home>/Kids Mode/<name>" \
    || fail "home was not moved to $HOMEROOT/home/mark/Kids Mode/Ada Lovelace"

check_not_contains "$(cat "$PORTAL_CONF" 2>/dev/null)" "$SLUG:Ada Lovelace" \
    "theme.conf.user: $SLUG's entry is gone after remove"
check_contains "$(cat "$PORTAL_CONF" 2>/dev/null)" "$SLUG-2:Ada Lovelace:bear" \
    "theme.conf.user: $SLUG-2's entry survives $SLUG's removal"

[[ -e "$FACE_ICON" ]] && fail "SDDM face icon for $SLUG should be removed" \
    || pass "SDDM face icon for $SLUG removed"

# --- remove --keep-home: home stays put -------------------------------------

: > "$ARGV_LOG"
"$BIN" remove "$SLUG-2" --keep-home >/dev/null 2>&1; st=$?
check_eq "$st" 0 "remove --keep-home exits 0"
check_contains "$(cat "$ARGV_LOG")" "userdel $SLUG-2" "remove --keep-home still removes the account"
[[ -d "$HOMEROOT/home/$SLUG-2" ]] && pass "remove --keep-home left the home in place" \
    || fail "remove --keep-home should not have moved/removed the home"

# --- remove: unknown account is refused -------------------------------------

out8="$("$BIN" remove kid-nosuchkid 2>&1)"; st=$?
check_eq "$st" 2 "remove of an unknown account exits 2"
check_contains "$out8" "no such kid account" "remove: unknown-account message names the problem"

echo "provision-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
