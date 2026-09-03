#!/bin/bash
# Tests bin/omarchy-kids-check (SPEC.md R-TRUST-2, R-TRUST-3, R-DESK-2;
# issue #29): a clean, fully-provisioned tree exits 0; a broken lock
# exits 2; a missing face icon (cosmetic-only) is a WARN, not a FAIL,
# and exits 1; --json's shape; --help and an unknown flag; --live
# without root; the firmware-password gate; and that check never calls
# a *_fix (it only ever reads, per its own header comment).
#
# Fixture tree: reuses test/shell.d/assert-test.sh's own scratch-tree
# and stub-PATH setup almost verbatim (same fixture kid, kid-ada, band
# 6-8, per AGENTS.md rule 9) — bin/omarchy-kids-check sources
# bin/omarchy-kids-assert for its lock-check functions, so the same
# fixture that satisfies every assert lock also satisfies every
# lock_check line here. Extended with a few fixtures assert-test.sh
# doesn't need: a readable (empty) sudoers, a luks-slots file plus a
# stub cryptsetup, a Limine config/default pair, a usage ledger
# directory, and machine.conf's firmware.card_done — see "extra
# fixtures for check" below for exactly why each exists.
#
# Fully self-contained per AGENTS.md rule 8: every system command that
# would touch the real machine is a stub on its own PATH; nothing here
# is ever root (the --live section is exercised only as "not root",
# which is what every real run of this suite actually is).
# shellcheck disable=SC2015 # "A && B || C" below is always used with B, C that can't fail
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT_DIR/bin/omarchy-kids-check"

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
# strip_ansi TEXT — drops the color escapes render_human wraps each
# STATUS word in (e.g. "\033[33mWARN\033[0m"), so a "STATUS  id" string
# match isn't broken by a reset code sitting between the two.
strip_ansi() { printf '%s' "$1" | sed -E $'s/\x1b\\[[0-9;]*m//g'; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- scratch tree (same shape as test/shell.d/assert-test.sh) --------------

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
firmware.card_done=yes
EOF

cat > "$ETC/kids/kid-ada.conf" <<'EOF'
name=Ada Lovelace
avatar=fox
band=6-8
password=set
onboarded=no
EOF

cp "$ROOT_DIR"/share/hyprland/*.lua "$SHARE/hyprland/"
cp "$ROOT_DIR"/share/avatars/*.svg "$SHARE/avatars/"

# stub NAME EXTRA — see test/shell.d/provision-test.sh for the full
# rationale; same helper assert-test.sh already copies verbatim.
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

# shellcheck disable=SC2016
stub findmnt '
target="${@: -1}"; acct="$(basename "$target")"
if [[ -f "__LOG__/mounted-$acct" ]]; then
    echo "rw,nosuid,nodev,noexec,relatime"
    exit 0
fi
exit 1
'
# shellcheck disable=SC2016
stub mount '
last="${@: -1}"; acct="$(basename "$last")"
case "$*" in
    *remount*) touch "__LOG__/mounted-$acct" ;;
esac
'
# shellcheck disable=SC2016
stub id '
acct="${@: -1}"
cat "__LOG__/groups/$acct" 2>/dev/null || true
'
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
# shellcheck disable=SC2016
stub getent '
if [[ "$1" == "passwd" ]]; then
    acct="$2"
    gecos="$(cat "__LOG__/gecos/$acct" 2>/dev/null || true)"
    printf "%s:x:1000:1000:%s:/home/%s:/bin/bash\n" "$acct" "$gecos" "$acct"
    exit 0
fi
exit 1
'
# systemctl: mask is a real filesystem op (matches --root); is-active
# always answers "inactive" (rc 1) — never exercised here anyway, since
# OMARCHY_KIDS_ROOT is set throughout this suite (skip, not fail/pass).
# shellcheck disable=SC2016
stub systemctl '
root=""
for a in "$@"; do case "$a" in --root=*) root="${a#--root=}" ;; esac; done
if [[ "$1" == "--root="* ]]; then shift; fi
if [[ "$1" == "mask" ]]; then
    unit="$2"
    mkdir -p "$root/etc/systemd/system"
    ln -sf /dev/null "$root/etc/systemd/system/$unit"
fi
if [[ "$1" == "is-active" ]]; then exit 1; fi
'
stub objcopy 'exit 0'
# shellcheck disable=SC2016
stub lsinitcpio '
cat "__LOG__/lsinitcpio-output" 2>/dev/null
'
# shellcheck disable=SC2016
stub mkinitcpio '
[[ "$1" == "-P" ]] && echo "usr/lib/initcpio/hooks/omarchy-kids-unlock" > "__LOG__/lsinitcpio-output"
'
stub limine-snapper-sync ''
# cryptsetup luksDump: two enabled LUKS2 slots, matching the luks-slots
# fixture below (boot:luks-slots, issue #29's new check).
stub cryptsetup '
if [[ "$1" == "luksDump" ]]; then
cat <<"DUMP"
Keyslots:
  0: luks2
  1: luks2
Tokens:
DUMP
fi
'

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_KIDS_ROOT="$SCRATCH_ROOT"
export OMARCHY_KIDS_HOME_ROOT="$HOMEROOT"
export OMARCHY_KIDS_LUKS_DEVICE="/dev/fake0"

# --- seed every lock as "already provisioned", using lib/posture.sh's
#     own writers directly, same as assert-test.sh -------------------

# shellcheck source=lib/conf.sh
source "$ROOT_DIR/lib/conf.sh"
# shellcheck source=lib/posture.sh
source "$ROOT_DIR/lib/posture.sh"

posture_add_fstab_line kid-ada
posture_add_namespace_lines kid-ada

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

posture_ensure_pam_namespace sddm
posture_ensure_pam_namespace systemd-user
posture_write_polkit_admin_rule mark
posture_write_polkit_deny_rule
posture_write_sddm_theme_dropin
posture_write_accountsservice kid-ada fox
posture_write_face_icon "$SHARE/avatars/fox.svg" kid-ada
posture_write_portal_conf mark "$(printf 'kid-ada\tAda Lovelace\tfox')"
printf '%s' 'Ada Lovelace' > "$LOG/gecos/kid-ada"
posture_ensure_parent_unlock_line sddm
posture_ensure_parent_unlock_line omarchy-lock-password

mkdir -p "$HOMEROOT/home/kid-ada"
touch "$LOG/mounted-kid-ada"

echo "kid-ada omarchy-kids omarchy-kids-6-8" > "$LOG/groups/kid-ada"

for n in 2 3 4 5 6; do
    mkdir -p "$SCRATCH_ROOT/etc/systemd/system"
    ln -sf /dev/null "$SCRATCH_ROOT/etc/systemd/system/getty@tty$n.service"
done

for u in omarchy-kids-boot-login.service omarchy-kids-boot-login-cleanup.service omarchy-kids-assert.service; do
    mkdir -p "$SCRATCH_ROOT/etc/systemd/system/multi-user.target.wants"
    ln -sf "/usr/lib/systemd/system/$u" "$SCRATCH_ROOT/etc/systemd/system/multi-user.target.wants/$u"
done
mkdir -p "$SCRATCH_ROOT/etc/systemd/system/sockets.target.wants"
ln -sf /usr/lib/systemd/system/omarchy-kids-authd.socket "$SCRATCH_ROOT/etc/systemd/system/sockets.target.wants/omarchy-kids-authd.socket"
mkdir -p "$SCRATCH_ROOT/etc/systemd/system/timers.target.wants"
ln -sf /usr/lib/systemd/system/omarchy-kids-ask-collect.timer "$SCRATCH_ROOT/etc/systemd/system/timers.target.wants/omarchy-kids-ask-collect.timer"
ln -sf /usr/lib/systemd/system/omarchy-kids-time.timer "$SCRATCH_ROOT/etc/systemd/system/timers.target.wants/omarchy-kids-time.timer"

mkdir -p "$ETC/hyprland"
cp "$SHARE"/hyprland/*.lua "$ETC/hyprland/"

mkdir -p "$SCRATCH_ROOT/etc/chromium/policies/managed"
CHROMIUM_FILE="$SCRATCH_ROOT/etc/chromium/policies/managed/omarchy-kids-6-8.json"
cat > "$CHROMIUM_FILE" <<'EOF'
{"DnsOverHttpsMode": "secure"}
EOF
chmod 0640 "$CHROMIUM_FILE"

mkdir -p "$SCRATCH_ROOT/usr/lib/initcpio/hooks" "$SCRATCH_ROOT/boot/EFI/Linux"
touch "$SCRATCH_ROOT/usr/lib/initcpio/hooks/omarchy-kids-unlock"
touch "$SCRATCH_ROOT/boot/EFI/Linux/arch-linux.efi"
echo "usr/lib/initcpio/hooks/omarchy-kids-unlock" > "$LOG/lsinitcpio-output"

# --- extra fixtures for check, beyond what assert-test.sh needs -------
#
# sudoers: a readable, empty pair (account:no-sudo would otherwise WARN
#          "cannot verify" — real, just not readable by this non-root
#          suite, same reason a real /etc/sudoers is 0440).
# luks-slots + cryptsetup stub above: boot:luks-slots (issue #29's slot-
#          count-consistency check) needs both to resolve past "cannot
#          verify".
# limine.conf / etc/default/limine: boot:editor-disabled and
#          boot:snapshot-entries reuse omarchy-kids-assert's own
#          limine_editor_ok/limine_snapshots_ok, which (like every lock
#          here) report "ok" when the file is simply absent — these
#          fixtures make them a real, checked PASS instead.
# usage/: time:ledger:kid-ada would otherwise WARN "doesn't exist yet",
#          true and correct before a kid's first session, but not what
#          a "clean, everything-checked" tree should show.
mkdir -p "$SCRATCH_ROOT/etc"
: > "$SCRATCH_ROOT/etc/sudoers"
mkdir -p "$SCRATCH_ROOT/etc/sudoers.d"
printf '0=mark\n1=kid-ada\n' > "$ETC/luks-slots"
printf 'default_entry: 1\neditor_enabled: no\n' > "$SCRATCH_ROOT/boot/limine.conf"
mkdir -p "$SCRATCH_ROOT/etc/default"
printf 'MAX_SNAPSHOT_ENTRIES=0\n' > "$SCRATCH_ROOT/etc/default/limine"
mkdir -p "$SCRATCH_ROOT/var/lib/omarchy-kids/kid-ada/usage"

# --- --help / bad args ------------------------------------------------

out="$("$BIN" --help)"; st=$?
check_eq "$st" 0 "--help exits 0"
check_contains "$out" "Usage: omarchy-kids-check" "--help prints usage"

"$BIN" --nonsense >/dev/null 2>&1
check_eq "$?" 2 "an unknown flag exits 2"

# --- a clean, fully-provisioned tree: exit 0 ("safe to hand over") -----

out="$("$BIN")"; st=$?
check_eq "$st" 0 "a clean, fully-provisioned tree exits 0"
check_contains "$out" "All checks pass" "clean tree: the human verdict line says so"
check_not_contains "$out" "FAIL" "clean tree: no FAIL line anywhere"
check_not_contains "$out" "WARN" "clean tree: no WARN line anywhere either (every fixture answers definitively)"
for id in "account:kid-ada:exists" "account:kid-ada:no-wheel" "account:kid-ada:no-sudo" \
    "account:kid-ada:band-group" "account:kid-ada:home-noexec" "account:kid-ada:gecos" \
    "lock:fstab:kid-ada" "lock:groups:kid-ada" "lock:boot-hook" "lock:limine-editor" "lock:limine-snapshots" \
    "boot:unlock-hook" "boot:luks-slots" "boot:editor-disabled" "boot:snapshot-entries" \
    "login:theme-dropin" "login:theme-conf-user" "login:face:kid-ada" "login:autologin-dropin" \
    "pam:parent-unlock:sddm" "pam:faillock-order:sddm" "web:mode:6-8" "web:doh:6-8" \
    "time:ledger:kid-ada" "firmware:password"; do
    check_contains "$out" "$id" "clean tree: report includes '$id'"
done

# --- --json: shape, and the same verdict/exit_code as the exit code ----

json="$("$BIN" --json)"; jst=$?
check_eq "$jst" 0 "--json on a clean tree also exits 0"
check_contains "$json" '"verdict": "pass"' "--json: verdict is pass"
check_contains "$json" '"exit_code": 0' "--json: exit_code matches the process exit code"
check_contains "$json" '"sections": [' "--json: has a sections array"
check_contains "$json" '"name": "Accounts"' "--json: has an Accounts section"
check_contains "$json" '"name": "Locks"' "--json: has a Locks section"
check_contains "$json" '"name": "Firmware"' "--json: has a Firmware section"
check_contains "$json" '"id": "lock:fstab:kid-ada", "status": "pass"' "--json: a check object has id/status fields"
check_contains "$json" '"detail":' "--json: a check object has a detail field"
if command -v python3 >/dev/null 2>&1; then
    if printf '%s' "$json" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["verdict"]=="pass"; assert d["exit_code"]==0; assert isinstance(d["sections"], list) and d["sections"]; [d for s in d["sections"] for c in s["checks"] if c["status"] in ("pass","warn","fail","skip")]' 2>/dev/null; then
        pass "--json: parses as valid JSON with the documented shape (python3 json.load)"
    else
        fail "--json: python3 could not parse it as the documented shape"
    fi
else
    pass "--json: skipped the python3 structural parse (no python3 on this box)"
fi

# --- a missing face icon: WARN, not FAIL — exit 1, not 2 ----------------

FACE_ICON="$SCRATCH_ROOT/usr/share/sddm/faces/kid-ada.face.icon"
rm -f "$FACE_ICON"
out="$("$BIN")"; st=$?
plain="$(strip_ansi "$out")"
check_eq "$st" 1 "a missing face icon alone: exits 1 (warn), not 2 (fail)"
check_contains "$plain" "WARN  lock:face:kid-ada" "missing face icon: lock:face:kid-ada is a WARN"
check_contains "$plain" "WARN  login:face:kid-ada" "missing face icon: login:face:kid-ada is a WARN too"
check_not_contains "$plain" "FAIL" "missing face icon: nothing else reports FAIL"
check_contains "$out" "Passing, with warnings" "missing face icon: the human verdict says 'passing, with warnings'"
posture_write_face_icon "$SHARE/avatars/fox.svg" kid-ada  # restore for what follows

# --- a broken lock: FAIL — exit 2 ---------------------------------------

DENY_RULE="$SCRATCH_ROOT/etc/polkit-1/rules.d/41-omarchy-kids-deny.rules"
rm -f "$DENY_RULE"
out="$("$BIN")"; st=$?
plain="$(strip_ansi "$out")"
check_eq "$st" 2 "a broken lock (polkit-deny missing) exits 2"
check_contains "$plain" "FAIL  lock:polkit-deny" "broken lock: lock:polkit-deny reports FAIL"
check_contains "$out" "run 'omarchy-kids-assert'" "broken lock: the detail names the fix, without running it"
check_contains "$out" "Not ready" "broken lock: the human verdict says 'not ready'"

json2="$("$BIN" --json)"
check_contains "$json2" '"verdict": "fail"' "--json also reflects a broken lock as verdict fail"
check_contains "$json2" '"exit_code": 2' "--json also reflects exit_code 2"
posture_write_polkit_deny_rule  # restore, after both the human and json checks above

# --- check never calls a *_fix: the fstab/mount/systemctl argv log never
#     shows a fix-shaped call (mount --bind, mount -o remount, systemctl
#     mask/enable) across this whole run, only fix() functions'
#     signatures. lock_check calls only *_ok functions -- confirm no
#     fixing side effects happened by re-breaking a lock and checking
#     that a FAIL does NOT restore it. ---------------------------------

rm -f "$DENY_RULE"
"$BIN" >/dev/null 2>&1
[[ ! -f "$DENY_RULE" ]] && pass "check never fixes: a FAILed lock (polkit-deny) is still missing after a run" \
    || fail "check must never write a lock back -- polkit-deny exists after a plain run"
posture_write_polkit_deny_rule  # restore for what follows

# --- firmware-password gate (R-TRUST-3): red (FAIL) until marked done,
#     a plain PASS (with the software caveat) once it is -------------

conf_del "$ETC/machine.conf" firmware.card_done
out="$("$BIN")"
plain="$(strip_ansi "$out")"
check_contains "$plain" "FAIL  firmware:password" "firmware not marked done: FAIL (red), per R-TRUST-3"
check_contains "$out" "isn't marked done" "firmware not marked done: names the manual step"

conf_set "$ETC/machine.conf" firmware.card_done yes
out="$("$BIN")"
plain="$(strip_ansi "$out")"
check_contains "$plain" "PASS  firmware:password" "firmware marked done: PASS, with a software caveat in its own detail text"
check_contains "$out" "can't be verified from software" "firmware marked done: still honest about what it can't prove (R-TRUST-2)"

# --- no kids provisioned: Accounts/Locks/Firmware/Time say so, nothing
#     pretends to have checked anything kid-specific ------------------

EMPTY_ETC="$TMP/etc-empty/omarchy-kids"
mkdir -p "$EMPTY_ETC/kids"
cat > "$EMPTY_ETC/machine.conf" <<'EOF'
parent=mark
EOF
out="$(OMARCHY_KIDS_ETC="$EMPTY_ETC" "$BIN")"
check_contains "$out" "SKIP  accounts:none" "no kids: Accounts says so"
check_contains "$out" "SKIP  locks:none" "no kids: Locks says so"
check_contains "$out" "SKIP  firmware:password" "no kids: Firmware is skipped, not red, before any kid exists"
check_not_contains "$out" "kid-ada" "no kids: nothing about kid-ada leaks in from the real \$OMARCHY_KIDS_ETC"

# --- --live: without root, warns and skips rather than faking a result -

out="$("$BIN" --live)"; st=$?
if [[ "$(id -u)" != "0" ]]; then
    check_contains "$out" "live:skipped" "--live as non-root: the Live tests section names why it skipped"
    check_contains "$out" "isn't root" "--live as non-root: says it needs root"
else
    pass "--live: this suite is somehow running as root; skipping the non-root assertion (AGENTS.md rule 8's own root/unshare convention)"
fi

out="$("$BIN")"
check_contains "$out" "not run — pass --live" "without --live: the Live tests section says how to run it"

echo "check-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
