# shellcheck shell=bash
# lib/posture.sh — writers for the machine-level "posture" a kid account
# needs: polkit rules (R-FND-3/4), pam_namespace/PAM stack edits
# (R-FND-2a), the fstab bind-mount line (R-FND-2), the AccountsService
# pin (R-LOGIN-3), and the luks-slots/portal rewrites (R-SEC-4). Every
# real path is prefixed by OMARCHY_KIDS_ROOT (default empty) for tests.
# Not meant to be executed directly; source it after lib/conf.sh. Full
# design and every env var: docs/portal.md, docs/boot.md.
# shellcheck source=./theme.sh
source "$(dirname "${BASH_SOURCE[0]}")/theme.sh"

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
# posture_valid_account NAME — the account names this file is willing to
# interpolate into a polkit rule or an SDDM config. Anchored, bounded, and
# refuses everything that could close a JavaScript string or a config
# field (review S9): a `parent=` value in machine.conf carrying a quote or
# a ']' either breaks the admin rule outright -- polkit then falls back to
# asking for *root*'s password, not the parent's -- or injects JavaScript.
posture_valid_account() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

posture_polkit_admin_rule_text() {
    local parent="$1"
    posture_valid_account "$parent" || {
        echo "lib/posture.sh: refusing to write a polkit admin rule for an unusable parent name '$parent'" >&2
        return 1
    }
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

# The text is built into a local *first*: a `$(...)` in an argument list
# swallows its own non-zero exit even under `set -e`, so the guard above
# used to end up writing an empty admin rule and reporting it fixed --
# polkit then asks for root's password, the exact failure the guard
# exists to prevent (review §2.2).
posture_write_polkit_admin_rule() {
    local parent="$1" file text
    file="$(posture_polkit_dir)/40-omarchy-kids.rules"
    text="$(posture_polkit_admin_rule_text "$parent")" || return 1
    posture_install_if_changed "$file" "$text" 0644
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
# One pam_exec line, `[success=done default=ignore]`, inserted right
# after a leading pam_faillock preauth line if the stack has one, else
# right before the first "auth" line -- covers both real Omarchy 4.0.2
# stacks (sddm, omarchy-lock-password). "done" ends the stack the instant
# a parent's password verifies; "default=ignore" falls through to
# pam_unix's own try_first_pass, so nobody is prompted twice. Never
# touches system-login/system-auth (I-7). Forensics on both real stacks
# this was confirmed against: docs/authd.md.

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
# pam_exec line into /etc/pam.d/<STACK> once, idempotently (the marker
# above is the whole check). Fails (returns 1, writes nothing) if the
# file doesn't exist or has no "auth" line to anchor on -- callers
# decide whether that's fatal.
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
# AccountsService's Icon= key is NOT what SDDM's UserModel actually reads
# here -- it checks ~/.face.icon, then a cache file this repo never
# populates, then <FacesDir>/<account>.face.icon (the one that has to
# exist). Copied here, not symlinked or written under the kid's home
# (I-3). Full UserModel.cpp citation: docs/portal.md.
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

# posture_sddm_theme_dropin_text — /etc/sddm.conf.d/zz-omarchy-kids-
# theme.conf: `[Theme] Current=omarchy-kids`, sorting after Omarchy's own
# 10-theme.conf by filename (SDDM reads every conf.d file in order).
# Its own drop-in, never a hand-edit of Omarchy's (I-7).
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
# Replaces an earlier "kid-" username-prefix heuristic (broke on an owner
# actually named kid-vm) and a portal.json+XHR design (needed a
# sddm.service restart, which re-fires the owner's stock autologin).
# Uses SDDM's own ThemeConfig::setTo() override instead: theme.conf.user
# next to the installed theme.conf, read automatically, no restart.
# Root-owned 0644, rewritten in full on every add/remove. Full citation
# and the live-VM finding: docs/portal.md.

# posture_parent_home PARENT — resolves PARENT's $HOME. A thin name for
# lib/theme.sh's own theme_account_home (AGENTS.md: "no duplicated
# helpers" — that function generalizes what used to be duplicated here,
# issue #53): `getent passwd` first, falling back to
# OMARCHY_KIDS_HOME_ROOT-prefixed "/home/<parent>" for tests. Points
# lib/theme.sh's THEME_KIDS_HOME at the parent's own theme, not root's.
posture_parent_home() { theme_account_home "$1"; }

# posture_theme_conf_lines PARENT — the nine [General] color/font keys
# theme.conf(.user) carries, resolved from PARENT's own Omarchy theme
# (THEME_KIDS_HOME points lib/theme.sh at PARENT's $HOME even though this
# runs as root). Falls back to theme.conf's own hardcoded defaults when
# the parent hasn't set a theme. Subshell so THEME_KIDS_HOME doesn't leak.
# Full key list and citation: share/sddm-theme/theme.conf's own header.
posture_theme_conf_lines() {
    local parent="$1"
    (
        THEME_KIDS_HOME="$(posture_parent_home "$parent")"
        export THEME_KIDS_HOME
        printf 'backgroundColor=%s\n' "$(theme_color background)"
        printf 'tileColor=%s\n' "$(theme_color surface)"
        printf 'tileHighlightColor=%s\n' "$(theme_color highlight)"
        printf 'parentTileColor=%s\n' "$(theme_color surface_muted)"
        printf 'accentColor=%s\n' "$(theme_color accent)"
        printf 'textColor=%s\n' "$(theme_color foreground)"
        printf 'mutedTextColor=%s\n' "$(theme_color muted)"
        printf 'errorColor=%s\n' "$(theme_color error)"
        printf 'fontFamily=%s\n' "$(theme_font)"
    )
}

# posture_portal_conf_text PARENT [ENTRY...] — ENTRY is
# "account<TAB>name<TAB>avatar" (tab, not ':'/',' -- both are separators
# in the "kids=" value below, so a name containing either is theme-
# invisible, not a crash, until a real wizard sanitizes it). Writes
# "parent=<account>" and "kids=<account>:<name>:<avatar>,...".
# Followed by posture_theme_conf_lines' nine color/font keys (docs/
# theming.md, issue #48) — same file, same [General] section, so SDDM's
# ThemeConfig::setTo() layers all eleven keys over theme.conf's own
# defaults in one pass.
posture_portal_conf_text() {
    local parent="$1" kids_field="" sep="" entry account name avatar
    shift
    posture_valid_account "$parent" || {
        echo "lib/posture.sh: refusing to write theme.conf.user for an unusable parent name '$parent'" >&2
        return 1
    }
    for entry in "$@"; do
        IFS=$'\t' read -r account name avatar <<<"$entry"
        # A name carrying one of this field's own separators would shift
        # every later tile by one (review S10). omarchy-kids-provision
        # rejects such a name at `add`; a profile written before that check
        # existed is skipped here rather than corrupting the whole greeter.
        if [[ "$name" == *:* || "$name" == *,* ]]; then
            echo "lib/posture.sh: '$account' has a display name containing ':' or ','; left off the greeter" >&2
            continue
        fi
        kids_field="${kids_field}${sep}${account}:${name}:${avatar}"
        sep=","
    done
    cat <<EOF
[General]
parent=$parent
kids=$kids_field
EOF
    posture_theme_conf_lines "$parent"
}

# posture_write_portal_conf PARENT [ENTRY...] — path is always
# $(posture_sddm_theme_dir)/theme.conf.user (see the section header
# above for why this isn't a caller-supplied FILE argument the way
# portal.json's writer took one: this is the one installed theme
# directory, not a scratch-overridable ETC path).
# Same shape as posture_write_polkit_admin_rule: the text first, so an
# unusable parent name aborts the write instead of silently producing a
# greeter with no parent= and no kids= line (review §2.2).
posture_write_portal_conf() {
    local parent="$1"
    shift
    local file text
    file="$(posture_sddm_theme_dir)/theme.conf.user"
    text="$(posture_portal_conf_text "$parent" "$@")" || return 1
    posture_install_if_changed "$file" "$text" 0644
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
