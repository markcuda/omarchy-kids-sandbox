# shellcheck shell=bash
# lib/posture.sh — writers for the machine-level "posture" that
# omarchy-kids-provision lays down around a kid account: the two polkit
# rules (R-FND-3, R-FND-4), the pam_namespace lines and PAM stack edits
# (R-FND-2a), the /etc/fstab bind-mount line (R-FND-2), the AccountsService
# pin (R-LOGIN-3), and the luks-slots rewrite (R-SEC-4, see docs/provision.md
# for why it is a full rewrite and not an append).
#
# Every real path here is prefixed by OMARCHY_KIDS_ROOT (default: empty, so
# the real /etc, /var apply) so tests — and a dry run reviewed before it is
# trusted — can point the whole set at a scratch tree:
#   OMARCHY_KIDS_ROOT  scratch prefix for /etc/polkit-1, /etc/security,
#                      /etc/pam.d, /etc/fstab, /var/lib/AccountsService
#
# Not meant to be executed directly; source it from a command (after
# lib/conf.sh, which these functions assume is already loaded for callers
# that also need conf_get/conf_set, though nothing in here calls them
# directly).

posture_root() { printf '%s' "${OMARCHY_KIDS_ROOT:-}"; }
posture_polkit_dir() { printf '%s/etc/polkit-1/rules.d' "$(posture_root)"; }
posture_namespace_conf() { printf '%s/etc/security/namespace.conf' "$(posture_root)"; }
posture_pam_dir() { printf '%s/etc/pam.d' "$(posture_root)"; }
posture_fstab() { printf '%s/etc/fstab' "$(posture_root)"; }
posture_accountsservice_dir() { printf '%s/var/lib/AccountsService/users' "$(posture_root)"; }
posture_sddm_conf_dir() { printf '%s/etc/sddm.conf.d' "$(posture_root)"; }
posture_sddm_theme_dir() { printf '%s/usr/share/sddm/themes/omarchy-kids' "$(posture_root)"; }

# posture_install_if_changed FILE CONTENT [MODE] — writes CONTENT (plus a
# trailing newline) to FILE via a same-directory temp file and rename, but
# only if FILE doesn't already hold exactly that. Idempotent: a second call
# with the same CONTENT never touches the file's mtime or leaves a stage
# file behind if the process is killed mid-write.
posture_install_if_changed() {
    local file="$1" content="$2" mode="${3:-0644}" dir stage
    dir="$(dirname "$file")"
    install -d -m 0755 "$dir"
    if [[ -f "$file" ]] && [[ "$(cat "$file")" == "$content" ]]; then
        return 0
    fi
    stage="$(mktemp "$dir/.$(basename "$file").XXXXXX")"
    printf '%s\n' "$content" > "$stage"
    chmod "$mode" "$stage"
    mv -f "$stage" "$file"
}

# --- polkit (R-FND-3, R-FND-4) ---------------------------------------------

# posture_polkit_admin_rule_text PARENT — 40-omarchy-kids.rules: members of
# omarchy-kids get PARENT as their polkit admin identity, so the native
# dialog asks for (and checks against) the parent's own account, never root.
posture_polkit_admin_rule_text() {
    local parent="$1"
    cat <<RULES
// Omarchy Kids Mode: members of omarchy-kids get the parent account as
// their polkit admin identity (SPEC.md R-FND-3), so the native dialog
// asks for the parent password and checks it against the parent's own
// account -- never root. Written once by "omarchy-kids-provision add";
// left in place by "remove" (machine-level, R-FND-6) until Remove Kids
// Mode takes the whole package out.
polkit.addAdminRule(function(action, subject) {
    if (subject.isInGroup("omarchy-kids")) {
        return ["unix-user:$parent"];
    }
});
RULES
}

posture_write_polkit_admin_rule() {
    local parent="$1" file
    file="$(posture_polkit_dir)/40-omarchy-kids.rules"
    posture_install_if_changed "$file" "$(posture_polkit_admin_rule_text "$parent")" 0644
}

# posture_polkit_deny_rule_text — 41-omarchy-kids-deny.rules: outright
# denies, no prompt at all, for a kid account (R-FND-4).
posture_polkit_deny_rule_text() {
    cat <<'RULES'
// Omarchy Kids Mode: outright denies for kid accounts, no prompt at all
// (SPEC.md R-FND-4). Written once by "omarchy-kids-provision add"; left
// in place by "remove" until Remove Kids Mode.
polkit.addRule(function(action, subject) {
    if (!subject.isInGroup("omarchy-kids")) return null;
    var id = action.id;
    if (id.indexOf("org.freedesktop.NetworkManager.settings.modify") === 0 ||
        id.indexOf("org.freedesktop.udisks2.filesystem-mount") === 0 ||
        id.indexOf("org.freedesktop.udisks2.encrypted-unlock") === 0 ||
        id === "org.freedesktop.udisks2.loop-setup" ||
        id === "org.freedesktop.systemd1.manage-units" ||
        id.indexOf("org.freedesktop.packagekit.") === 0 ||
        id.indexOf("org.freedesktop.Flatpak.") === 0 ||
        id.indexOf("org.omarchy.") === 0) {
        return polkit.Result.NO;
    }
});
RULES
}

posture_write_polkit_deny_rule() {
    local file
    file="$(posture_polkit_dir)/41-omarchy-kids-deny.rules"
    posture_install_if_changed "$file" "$(posture_polkit_deny_rule_text)" 0644
}

# --- pam_namespace (R-FND-2a) -----------------------------------------------

# posture_namespace_line_tmp/shm ACCOUNT — the exact namespace.conf lines
# for this account. Same instance-prefix shape for /tmp and /dev/shm;
# pam_namespace's own polyinstantiation (per-uid contexts) is what actually
# keeps two kids' tmpfs's apart, not a distinct prefix per account.
posture_namespace_line_tmp() { printf '/tmp /tmp/kids-inst/ tmpfs:mntopts=nosuid,nodev,noexec %s' "$1"; }
posture_namespace_line_shm() { printf '/dev/shm /dev/shm/kids-inst/ tmpfs:mntopts=nosuid,nodev,noexec %s' "$1"; }

posture_add_namespace_lines() {
    local account="$1" file l1 l2
    file="$(posture_namespace_conf)"
    install -d -m 0755 "$(dirname "$file")"
    touch "$file"
    l1="$(posture_namespace_line_tmp "$account")"
    l2="$(posture_namespace_line_shm "$account")"
    grep -qxF "$l1" "$file" || printf '%s\n' "$l1" >> "$file"
    grep -qxF "$l2" "$file" || printf '%s\n' "$l2" >> "$file"
}

posture_remove_namespace_lines() {
    local account="$1" file tmp l1 l2 line
    file="$(posture_namespace_conf)"
    [[ -f "$file" ]] || return 0
    l1="$(posture_namespace_line_tmp "$account")"
    l2="$(posture_namespace_line_shm "$account")"
    tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "$l1" || "$line" == "$l2" ]] && continue
        printf '%s\n' "$line" >> "$tmp"
    done < "$file"
    mv -f "$tmp" "$file"
}

# posture_ensure_pam_namespace PAM_FILE_BASENAME — appends a marker comment
# plus "session required pam_namespace.so" to /etc/pam.d/<basename> (sddm,
# systemd-user) if the marker isn't already there. Idempotent: never
# duplicates the line on a second kid's add.
posture_pam_namespace_marker() { printf '# omarchy-kids: pam_namespace for kid sessions (R-FND-2a)'; }

posture_ensure_pam_namespace() {
    local base="$1" file marker line
    file="$(posture_pam_dir)/$base"
    marker="$(posture_pam_namespace_marker)"
    line="session required pam_namespace.so"
    install -d -m 0755 "$(dirname "$file")"
    # Arch ships some stacks only under /usr/lib/pam.d (systemd-user). An /etc copy overrides the
    # vendor file wholesale, so seed it from the vendor file before appending, never edit /usr/lib.
    if [[ ! -f "$file" && -f "$(posture_root)/usr/lib/pam.d/$base" ]]; then
        cp "$(posture_root)/usr/lib/pam.d/$base" "$file"
    fi
    touch "$file"
    grep -qxF "$marker" "$file" && return 0
    {
        printf '%s\n' "$marker"
        printf '%s\n' "$line"
    } >> "$file"
}

# --- parent-unlock PAM line (R-SEC-2, R-SEC-3; SPEC.md I-6; docs/authd.md) --
#
# The lock screen and SDDM both need "did a parent type their own password
# here?" answered the same way (docs/authd.md): pam_exec.so calling
# omarchy-kids-parent-auth, which asks the omarchy-kids-authd daemon rather
# than re-implementing password checking. This line is written once, into
# each real stack this ships on, at a fixed position relative to that
# stack's own first "auth" line -- not by finding a pam_unix.so line to
# jump around, which real Omarchy 4.0.2 stacks don't reliably even have
# (confirmed against a real box; see below).
#
# Placement, confirmed against the real /etc/pam.d/sddm and
# /etc/pam.d/omarchy-lock-password on Omarchy 4.0.2 (there is no
# /etc/pam.d/hyprlock on that box -- omarchy-apply-lock always writes
# omarchy-lock-password):
#
#   /etc/pam.d/sddm is `auth include system-login` first -- no pam_unix.so
#   line of its own at all, and no leading pam_faillock preauth line
#   either. Our line has to go *before* that first "auth" line, so it runs
#   (and can potentially succeed outright) before system-login's own chain
#   -- which is what actually checks whichever account is really logging
#   in -- ever runs.
#
#   /etc/pam.d/omarchy-lock-password (bin/omarchy-apply-lock,
#   scratchpad/pr9750.diff) leads with
#   "auth required pam_faillock.so preauth ...". Our line goes right
#   *after* that one line (never before it -- preauth has to run first so
#   a lockout is tracked correctly), still ahead of pam_unix.so.
#
# So the one rule that covers both real shapes: insert right after a
# leading "auth ... pam_faillock.so ... preauth" line if the very first
# "auth" line in the file is one, otherwise insert right before that first
# "auth" line. ("auth", not "-auth" -- a dash-prefixed line is a
# module-load-failure-is-silent variant of the same facility, never the
# anchor point.) Never touches system-login or system-auth themselves
# (I-7): those are included by reference, never opened by this function.
#
# The control is fixed, not computed: "[success=done default=ignore]".
# "done" ends the whole stack successfully the instant a parent's password
# verifies, so pam_unix (and whatever system-login/system-auth's own chain
# does) is never even consulted with the parent's password. "default=ignore"
# on anything else (wrong password, daemon unreachable, rate-limited) falls
# through to the stack's normal chain, which -- because our line sits
# ahead of it with `expose_authtok` already having read the typed password
# -- reuses that exact same token via pam_unix's own `try_first_pass`
# (already on both real stacks' pam_unix lines), so nobody is ever
# prompted twice.

# posture_parent_unlock_marker — the idempotence marker placed immediately
# above the inserted pam_exec line. A second kid's "add", or
# omarchy-kids-assert re-running, sees the marker and does nothing further.
posture_parent_unlock_marker() { printf '# omarchy-kids: parent-unlock verifier (R-SEC-2, R-SEC-3)'; }

# posture_parent_unlock_line — the exact pam_exec line, docs/authd.md's
# canonical form with a fixed "done" jump (see the section header above
# for why this is a fixed control, not a computed jump count).
posture_parent_unlock_line() {
    printf 'auth       [success=done default=ignore]  pam_exec.so quiet expose_authtok /usr/bin/omarchy-kids-parent-auth'
}

# posture_parent_unlock_lock_stack — which second PAM stack (besides
# sddm) gets the parent-unlock line: always "omarchy-lock-password",
# what bin/omarchy-apply-lock (the installer path; scratchpad/pr9750.diff)
# actually writes on Omarchy 4.0.2. There is no vanilla "hyprlock" PAM
# service on that box to fall back to -- an earlier version of this
# function guessed one; confirmed wrong against a real machine and
# removed. Kept as a function (not a literal string at every call site)
# so the one place this could ever need to change again is one place.
posture_parent_unlock_lock_stack() { printf 'omarchy-lock-password\n'; }

# posture_ensure_parent_unlock_line STACK — inserts the parent-unlock
# pam_exec line into /etc/pam.d/<STACK>, once, idempotently (the marker
# above is the whole idempotence check). STACK is whatever the caller
# already decided on (sddm, or posture_parent_unlock_lock_stack's
# answer) -- this function doesn't choose. See the section header above
# for exactly where the line lands and why.
#
# Fails (returns 1, writes nothing) if the file doesn't exist, or has no
# non-comment "auth" line at all to anchor on -- callers decide whether
# that's fatal (omarchy-kids-provision warns and keeps going;
# omarchy-kids-assert reports the lock FAIL and keeps going too, per its
# own "one bad lock never stops the rest" contract).
posture_ensure_parent_unlock_line() {
    local stack="$1" file marker
    file="$(posture_pam_dir)/$stack"
    marker="$(posture_parent_unlock_marker)"
    if [[ ! -f "$file" ]]; then
        echo "posture_ensure_parent_unlock_line: no such PAM stack '$file'" >&2
        return 1
    fi
    grep -qxF "$marker" "$file" && return 0

    # Find the first non-comment "auth" line (a literal "auth" token,
    # not "-auth"), and note whether it is itself a leading
    # "pam_faillock.so ... preauth" line.
    local line anchor_line="" anchor_is_preauth=0 found=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        if [[ "$line" =~ ^auth[[:space:]] ]]; then
            anchor_line="$line"
            found=1
            if [[ "$line" == *pam_faillock.so* && "$line" == *preauth* ]]; then
                anchor_is_preauth=1
            fi
            break
        fi
    done < "$file"
    if [[ "$found" == 0 ]]; then
        echo "posture_ensure_parent_unlock_line: no non-comment 'auth ...' line in $file to anchor on" >&2
        return 1
    fi

    local tmp inserted=0
    tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$anchor_is_preauth" == 0 && "$inserted" == 0 && "$line" == "$anchor_line" ]]; then
            printf '%s\n' "$marker" >> "$tmp"
            printf '%s\n' "$(posture_parent_unlock_line)" >> "$tmp"
            inserted=1
        fi
        printf '%s\n' "$line" >> "$tmp"
        if [[ "$anchor_is_preauth" == 1 && "$inserted" == 0 && "$line" == "$anchor_line" ]]; then
            printf '%s\n' "$marker" >> "$tmp"
            printf '%s\n' "$(posture_parent_unlock_line)" >> "$tmp"
            inserted=1
        fi
    done < "$file"
    mv -f "$tmp" "$file"
}

# posture_remove_parent_unlock_line STACK — reverses
# posture_ensure_parent_unlock_line: drops the marker line and the
# pam_exec line right after it. No-op if the marker isn't there (never
# provisioned, already removed, or the stack doesn't exist).
posture_remove_parent_unlock_line() {
    local stack="$1" file marker
    file="$(posture_pam_dir)/$stack"
    marker="$(posture_parent_unlock_marker)"
    [[ -f "$file" ]] || return 0
    grep -qxF "$marker" "$file" || return 0

    local tmp line skip_next=0
    tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$marker" ]]; then
            skip_next=1
            continue
        fi
        if [[ "$skip_next" == 1 ]]; then
            skip_next=0
            continue
        fi
        printf '%s\n' "$line" >> "$tmp"
    done < "$file"
    mv -f "$tmp" "$file"
}

# --- fstab (R-FND-2) --------------------------------------------------------

# posture_fstab_line ACCOUNT — the exact bind-mount line for ACCOUNT's
# home. Always the real /home path, even under a scratch OMARCHY_KIDS_ROOT:
# this text is read by a real machine's mount at boot, so it must be right
# no matter where this call is being exercised from.
posture_fstab_line() { printf '/home/%s /home/%s none bind,nosuid,nodev,noexec 0 0' "$1" "$1"; }

posture_add_fstab_line() {
    local account="$1" file line
    file="$(posture_fstab)"
    line="$(posture_fstab_line "$account")"
    install -d -m 0755 "$(dirname "$file")"
    touch "$file"
    grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}

posture_remove_fstab_line() {
    local account="$1" file line tmp l
    file="$(posture_fstab)"
    [[ -f "$file" ]] || return 0
    line="$(posture_fstab_line "$account")"
    tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")"
    while IFS= read -r l || [[ -n "$l" ]]; do
        [[ "$l" == "$line" ]] && continue
        printf '%s\n' "$l" >> "$tmp"
    done < "$file"
    mv -f "$tmp" "$file"
}

# --- AccountsService (R-LOGIN-3) -------------------------------------------

# posture_accountsservice_text AVATAR — pins the kid session so the tile
# has no session picker. The icon path is always the real, installed
# location: it's read by the greeter on the real machine, not by whatever
# scratch OMARCHY_KIDS_SHARE a test points at.
posture_accountsservice_text() {
    local avatar="$1"
    cat <<EOF
[User]
Session=omarchy-kids
XSession=omarchy-kids
Icon=/usr/share/omarchy-kids/avatars/$avatar.svg
EOF
}

posture_write_accountsservice() {
    local account="$1" avatar="$2" file
    file="$(posture_accountsservice_dir)/$account"
    posture_install_if_changed "$file" "$(posture_accountsservice_text "$avatar")" 0644
}

posture_remove_accountsservice() {
    local account="$1"
    rm -f "$(posture_accountsservice_dir)/$account"
}

# --- SDDM face icons (issue #39, live VM finding) --------------------------
#
# AccountsService's own Icon= key (posture_accountsservice_text above) is
# NOT what SDDM's UserModel actually reads for the "icon" role on this
# stack. UserModel's constructor (sddm/sddm's src/greeter/UserModel.cpp,
# fetched 2026-09, confirmed by reading it directly) checks, in this
# order: "<home>/.face.icon" first, then the literal path
# "/var/lib/AccountsService/icons/<account>" (a cache file the real
# accountsd daemon populates itself via its own D-Bus SetIconFile method
# -- nothing in this repo ever calls that method, so this file is never
# created here and its existence check always fails), then
# "<FacesDir>/<account>.face.icon" (FacesDir defaults to
# /usr/share/sddm/faces -- /usr/lib/sddm/sddm.conf.d/default.conf line
# 58). The third path is the one that actually has to exist on disk for
# an avatar to render on this stack; posture_accountsservice_text's own
# Icon= line is kept as-is (it may still matter to a D-Bus-backed
# AccountsService client elsewhere, and removing a working write is
# needless churn), it just isn't what SDDM itself reads.
#
# Copied, not symlinked, and never under the kid's own home: "~/.face.icon"
# is the *first* path UserModel checks, ahead of this one, and the kid's
# home must stay untrusted (I-3) -- writing there would also hand the kid
# a way to swap their own avatar file for something else read by root's
# greeter process. Copying instead of pointing straight at
# share/avatars/<avatar>.svg keeps this file's content independent of
# wherever the package happens to install avatars, matching
# posture_accountsservice_text's own reasoning for using a fixed,
# real path rather than a scratch one for the *destination* -- the
# *source* is still caller-supplied here (unlike the Icon= line's plain
# string) because copying needs a real, readable file to copy from, and
# the real command (omarchy-kids-provision) and its tests use different
# real/scratch source directories (OMARCHY_KIDS_SHARE) the way
# omarchy-kids-assert's hyprland-configs lock already does for
# share/hyprland/*.lua.
posture_sddm_faces_dir() { printf '%s/usr/share/sddm/faces' "$(posture_root)"; }

# posture_write_face_icon SRC ACCOUNT — SRC is the avatar SVG's full
# source path (the caller resolves which avatar and which directory
# avatars live in). Copied byte-for-byte (not routed through
# posture_install_if_changed's text-content helper, which normalizes
# trailing newlines -- this is meant to be an exact copy of an SVG file,
# same atomic temp-file-then-rename shape every other writer here uses,
# skipped entirely via `cmp -s` if the destination already matches, the
# same idempotence check omarchy-kids-assert's own hyprland-configs lock
# already uses for a directory of files).
posture_write_face_icon() {
    local src="$1" account="$2" file dir stage
    if [[ ! -r "$src" ]]; then
        echo "posture_write_face_icon: no such avatar file '$src'" >&2
        return 1
    fi
    file="$(posture_sddm_faces_dir)/$account.face.icon"
    dir="$(dirname "$file")"
    install -d -m 0755 "$dir"
    cmp -s "$src" "$file" 2>/dev/null && return 0
    stage="$(mktemp "$dir/.$(basename "$file").XXXXXX")"
    install -m 0644 "$src" "$stage"
    mv -f "$stage" "$file"
}

# posture_remove_face_icon ACCOUNT — reverses posture_write_face_icon.
posture_remove_face_icon() {
    rm -f "$(posture_sddm_faces_dir)/$1.face.icon"
}

# --- SDDM theme selection (R-LOGIN, issue #14) -----------------------------

# posture_sddm_theme_dropin_text — the whole content of
# /etc/sddm.conf.d/zz-omarchy-kids-theme.conf: selects our portal
# (share/sddm-theme/ -> /usr/share/sddm/themes/omarchy-kids) the same way
# Omarchy's own /etc/sddm.conf.d/10-theme.conf selects "omarchy" --
# `[Theme]` `Current=<name>` is SDDM's own documented key
# (data/man/sddm.conf.rst.in upstream), read from every conf.d file in
# order, so ours (a "zz-" prefix, same convention as
# zz-omarchy-kids-autologin.conf in docs/boot.md) simply has to sort after
# Omarchy's "10-" one to win. Kept as its own drop-in, never a hand-edit
# of Omarchy's 10-theme.conf (I-7: core untouched).
posture_sddm_theme_dropin_text() {
    cat <<'EOF'
[Theme]
Current=omarchy-kids
EOF
}

posture_write_sddm_theme_dropin() {
    local file
    file="$(posture_sddm_conf_dir)/zz-omarchy-kids-theme.conf"
    posture_install_if_changed "$file" "$(posture_sddm_theme_dropin_text)" 0644
}

# posture_remove_sddm_theme_dropin — drops the theme selection back to
# whatever Omarchy's own conf.d already has (its 10-theme.conf, untouched).
# Not wired into "omarchy-kids-provision remove": like the polkit rules,
# this is a machine-level lock (R-FND-6) left in place until Remove Kids
# Mode takes the whole package out, since the portal is still the right
# greeter for the machine as long as any other kid remains provisioned.
posture_remove_sddm_theme_dropin() {
    rm -f "$(posture_sddm_conf_dir)/zz-omarchy-kids-theme.conf"
}

# --- theme.conf.user: parent detection + avatars for the greeter (issue #39) -
#
# V1's live VM run (docs/portal.md's "Verified live" section) found the
# portal's tiles keying "who is the parent" off the "kid-" username prefix
# broke as soon as the machine's *owner* was named "kid-vm" (a VM test
# fixture, not a real child) -- the owner's own tile was misclassified as
# a kid.
#
# An earlier version of this fix wrote a separate portal.json and read it
# from Main.qml with XMLHttpRequest on a file:// URL. Dropped: that read
# needs QML_XHR_ALLOW_FILE_READ=1 in the greeter's own process
# environment (Qt refuses local-file XHR reads otherwise), and the only
# way found to set that was a systemd drop-in on sddm.service -- which
# only takes effect after `systemctl restart sddm`, which on a live,
# already-booted machine re-fires the owner's stock autologin. Not an
# acceptable cost for a display-name/avatar polish fix.
#
# Used instead: SDDM's own theme config override mechanism.
# `ThemeConfig::setTo()` (sddm/sddm's src/common/ThemeConfig.cpp, fetched
# 2026-09, confirmed by reading it directly) loads `<path>` (the theme's
# own theme.conf) into a QSettings, then loads a *second* QSettings from
# `<path> + ".user"` and overwrites every key the second file sets
# non-empty over the first's -- so `theme.conf.user`, right next to
# `theme.conf` in the installed theme directory, is read automatically by
# SDDM itself, with no XHR, no file:// URL, and no extra process
# environment needed. Main.qml already reads every [General] key through
# the existing "config" context property (theme.conf's own header
# comment); "parent" and "kids" below are just two more keys in that
# same property map.
#
# Written to $(posture_sddm_theme_dir)/theme.conf.user -- the *installed*
# theme directory (PKGBUILD's package() copies share/sddm-theme/ there),
# not this repo's own share/sddm-theme/theme.conf, which ships as a
# read-only package file and must never be hand-edited at runtime (I-7).
# Root-owned 0644, rewritten in full on every add/remove (never appended
# to), same "recompute the whole thing" shape portal.json used and
# luks-slots still uses: it holds names and avatar ids, none of which is
# a secret, and SDDM's greeter runs as an unprivileged user that needs to
# read it.

# posture_portal_conf_text PARENT [ENTRY...] — ENTRY is
# "account<TAB>name<TAB>avatar" (a tab, not ':' or ',' -- both are used
# as separators in the "kids=" value below, so callers are responsible
# for never handing this a name containing either; the wizard's own name
# field, once it exists, is the one place that would need to enforce
# that. A profile with such a name is theme-invisible -- not a crash --
# until AGENTS.md rule 9's "kid-ada"-only fixture convention meets a
# real wizard that has to actually sanitize this). Two [General] keys,
# both plain strings QSettings needs no escaping for on the simple
# alphanumeric+space names/avatars this repo's own fixtures and bands
# ever produce:
#   parent=<account>
#   kids=<account>:<name>:<avatar>,<account>:<name>:<avatar>,...
posture_portal_conf_text() {
    local parent="$1" kids_field="" sep="" entry account name avatar
    shift
    for entry in "$@"; do
        IFS=$'\t' read -r account name avatar <<<"$entry"
        kids_field="${kids_field}${sep}${account}:${name}:${avatar}"
        sep=","
    done
    cat <<EOF
[General]
parent=$parent
kids=$kids_field
EOF
}

# posture_write_portal_conf PARENT [ENTRY...] — path is always
# $(posture_sddm_theme_dir)/theme.conf.user (see the section header
# above for why this isn't a caller-supplied FILE argument the way
# portal.json's writer took one: this is the one installed theme
# directory, not a scratch-overridable ETC path).
posture_write_portal_conf() {
    local parent="$1"
    shift
    local file
    file="$(posture_sddm_theme_dir)/theme.conf.user"
    posture_install_if_changed "$file" "$(posture_portal_conf_text "$parent" "$@")" 0644
}

# --- luks-slots (R-SEC-4, and the "LUKS2 reuses slot numbers" finding) -----

# posture_write_luks_slots FILE PARENT_LINE [ENTRY...] — rewrites FILE
# *entirely* from PARENT_LINE (the verbatim "0=..." line, or empty to omit
# it) and the given "slot=account[:session]" ENTRY lines. Always a full
# rewrite, never an append/edit-in-place: LUKS2 hands out a freed slot
# number to the next add, so the only way to be sure a stale line never
# points a freed-and-reused slot at the wrong account is to regenerate the
# whole file from the current, known-correct set of mappings every time a
# slot changes (see docs/provision.md).
posture_write_luks_slots() {
    local file="$1" parent_line="$2" tmp e
    shift 2
    install -d -m 0755 "$(dirname "$file")"
    tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")"
    {
        [[ -n "$parent_line" ]] && printf '%s\n' "$parent_line"
        for e in "$@"; do printf '%s\n' "$e"; done
    } > "$tmp"
    chmod 0600 "$tmp"
    mv -f "$tmp" "$file"
}
