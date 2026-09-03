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
# than re-implementing password checking. This line is written once, right
# after the stack's own pam_unix.so line, with a jump number chosen so a
# verifier success lands exactly where pam_unix's own success would have.

# posture_parent_unlock_marker — the idempotence marker placed immediately
# above the inserted pam_exec line. A second kid's "add", or
# omarchy-kids-assert re-running, sees the marker and does nothing further.
posture_parent_unlock_marker() { printf '# omarchy-kids: parent-unlock verifier (R-SEC-2, R-SEC-3)'; }

# posture_parent_unlock_line SUCCESS — the exact pam_exec line, docs/authd.md's
# canonical form with SUCCESS filled in (see posture_ensure_parent_unlock_line
# for how that number is worked out).
posture_parent_unlock_line() {
    printf 'auth       [success=%s default=ignore]  pam_exec.so quiet expose_authtok /usr/bin/omarchy-kids-parent-auth' "$1"
}

# posture_parent_unlock_lock_stack — which second PAM stack (besides sddm)
# gets the parent-unlock line, chosen by what the installer actually wrote
# on this box: Omarchy's own lock-screen stack
# (bin/omarchy-apply-lock -- see scratchpad/pr9750.diff for its exact shape)
# if it exists, else the vanilla hyprlock PAM service.
posture_parent_unlock_lock_stack() {
    if [[ -f "$(posture_pam_dir)/omarchy-lock-password" ]]; then
        printf 'omarchy-lock-password\n'
    else
        printf 'hyprlock\n'
    fi
}

# posture_ensure_parent_unlock_line STACK — inserts the parent-unlock
# pam_exec line into /etc/pam.d/<STACK>, directly after the stack's first
# "auth ... pam_unix.so" line, once, idempotently (the marker above is the
# whole idempotence check). STACK is whatever the caller already decided on
# (sddm, or posture_parent_unlock_lock_stack's answer) -- this function
# doesn't choose.
#
# The jump number: pam_unix's own control on that line names how many
# lines its own success skips forward ("[success=N ...]"). Our line sits
# one line further down the stack than pam_unix did (inserted right after
# it), so landing on the exact same target line needs N-1.
#
# Special case, taken verbatim from Omarchy's own omarchy-lock-password
# writer (bin/omarchy-apply-lock in the installer; scratchpad/pr9750.diff):
# a pam_unix line reading exactly "[success=1 default=bad]" isn't a
# "skip N lines" distance in the usual sense -- that control exists only to
# jump over the single "[default=die] pam_faillock authfail" line
# immediately below it. N-1 there would be 0 (no jump at all), which would
# walk our own success straight into the authfail branch pam_unix's own
# success was skipping. So that one shape is hardcoded rather than
# computed: same insertion point (still "right after pam_unix", which is
# also "right before the authfail line" in this exact stack), but
# success=1, default=ignore, unchanged.
#
# Fails (returns 1, writes nothing) if the file doesn't exist or has no
# "auth ... pam_unix.so" line with a "[success=N ...]" control to read --
# callers decide whether that's fatal (omarchy-kids-provision warns and
# keeps going; omarchy-kids-assert reports the lock FAIL and keeps going
# too, per its own "one bad lock never stops the rest" contract).
posture_ensure_parent_unlock_line() {
    local stack="$1" file marker
    file="$(posture_pam_dir)/$stack"
    marker="$(posture_parent_unlock_marker)"
    if [[ ! -f "$file" ]]; then
        echo "posture_ensure_parent_unlock_line: no such PAM stack '$file'" >&2
        return 1
    fi
    grep -qxF "$marker" "$file" && return 0

    local line unix_line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$unix_line" && "$line" =~ ^auth[[:space:]] && "$line" == *pam_unix.so* ]]; then
            unix_line="$line"
        fi
    done < "$file"
    if [[ -z "$unix_line" ]]; then
        echo "posture_ensure_parent_unlock_line: no 'auth ... pam_unix.so' line in $file" >&2
        return 1
    fi

    local n=""
    if [[ "$unix_line" =~ \[success=([0-9]+)[[:space:]]+default=[a-z]+\] ]]; then
        n="${BASH_REMATCH[1]}"
    else
        echo "posture_ensure_parent_unlock_line: pam_unix.so line in $file has no '[success=N default=...]' control" >&2
        return 1
    fi

    local success
    if [[ "$unix_line" == *'[success=1 default=bad]'* ]]; then
        success=1
    else
        success=$((n - 1))
    fi

    local tmp inserted=0
    tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")"
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line" >> "$tmp"
        if [[ "$inserted" == 0 && "$line" == "$unix_line" ]]; then
            printf '%s\n' "$marker" >> "$tmp"
            printf '%s\n' "$(posture_parent_unlock_line "$success")" >> "$tmp"
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
