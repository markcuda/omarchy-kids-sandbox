# shellcheck shell=bash
# lib/assert-locks.sh — omarchy-kids-assert's per-kid and machine-level
# lock *_ok/*_fix pairs (everything but the Limine locks). Sourced by
# the dispatcher; not meant to be executed directly. See docs/assert.md's
# "Lock list" and "Judgment calls" for the full table and every rationale
# below -- each comment here is a one-line pointer, not the full case.

profile_field() { conf_get "$KIDS_DIR/$1.conf" "$2" 2>/dev/null || true; }

# fstab: R-FND-2's bind-mount line, via lib/posture.sh's idempotent writer.
fstab_ok() { grep -qxF "$(posture_fstab_line "$1")" "$(posture_fstab)" 2>/dev/null; }
fstab_fix() { posture_add_fstab_line "$1"; }

# mount: actually mounted noexec,nosuid,nodev right now, not just fstab.
mount_opts_ok() { [[ "$1" == *noexec* && "$1" == *nosuid* && "$1" == *nodev* ]]; }
mount_ok() {
    local opts
    opts="$(findmnt -no OPTIONS "$(home_dir_for "$1")" 2>/dev/null || true)"
    [[ -n "$opts" ]] && mount_opts_ok "$opts"
}
mount_fix() {
    local account="$1" home opts
    home="$(home_dir_for "$account")"
    opts="$(findmnt -no OPTIONS "$home" 2>/dev/null || true)"
    if [[ -z "$opts" ]]; then
        mount --bind "$home" "$home" || return 1
    fi
    mount -o remount,bind,nosuid,nodev,noexec "$home"
}

# namespace: R-FND-2a's two pam_namespace.conf lines for this account.
namespace_ok() {
    local file
    file="$(posture_namespace_conf)"
    [[ -f "$file" ]] || return 1
    grep -qxF "$(posture_namespace_line_tmp "$1")" "$file" \
        && grep -qxF "$(posture_namespace_line_shm "$1")" "$file"
}
namespace_fix() { posture_add_namespace_lines "$1"; }

# accountsservice: R-LOGIN-3's session pin, exact content match (same
# idempotence check posture_write_accountsservice itself uses).
accountsservice_ok() {
    local account="$1" avatar="$2" file
    file="$(posture_accountsservice_dir)/$account"
    [[ -f "$file" ]] && [[ "$(cat "$file")" == "$(posture_accountsservice_text "$avatar")" ]]
}
accountsservice_fix() { posture_write_accountsservice "$1" "$2"; }

# gecos (issue #39): passwd's GECOS field, which SDDM reads for realName.
gecos_ok() {
    local account="$1" name="$2" current
    command -v getent >/dev/null 2>&1 || return 2  # no way to read the field back
    current="$(getent passwd "$account" 2>/dev/null | cut -d: -f5)"
    [[ "$current" == "$name" ]]
}
gecos_fix() { usermod -c "$2" "$1"; }

# face (issue #39): the file SDDM's UserModel actually reads for the
# avatar, not AccountsService's Icon= (docs/portal.md's "Avatars").
face_ok() {
    local account="$1" avatar="$2" src file
    src="$SHARE/avatars/$avatar.svg"
    file="$(posture_sddm_faces_dir)/$account.face.icon"
    [[ -f "$file" ]] && cmp -s "$src" "$file"
}
face_fix() { posture_write_face_icon "$SHARE/avatars/$2.svg" "$1"; }

# groups: member of omarchy-kids and the band group. No lib/posture.sh
# writer to reuse here (docs/assert.md's "Judgment calls").
current_groups() { id -nG "$1" 2>/dev/null || true; }
has_group() { [[ " $1 " == *" $2 "* ]]; }
groups_ok() {
    local account="$1" band="$2" group current
    group="$(group_for_band "$band")" || return 1
    current="$(current_groups "$account")"
    has_group "$current" omarchy-kids && has_group "$current" "$group"
}
groups_fix() {
    local account="$1" band="$2" group current missing=()
    group="$(group_for_band "$band")" || return 1
    current="$(current_groups "$account")"
    has_group "$current" omarchy-kids || missing+=(omarchy-kids)
    has_group "$current" "$group" || missing+=("$group")
    [[ ${#missing[@]} -eq 0 ]] && return 0
    local IFS=,
    usermod -aG "${missing[*]}" "$account"
}

# theme (issue #53): the kid's current Omarchy theme still matches the
# profile's `theme` override -- docs/theming.md.
theme_ok() {
    local account="$1" expected current
    expected="$(profile_field "$account" theme)"
    [[ -n "$expected" ]] || return 0
    current="$(THEME_KIDS_HOME="$(home_dir_for "$account")" theme_current_name)"
    [[ "$current" == "$expected" ]]
}
theme_fix() {
    local account="$1" expected
    expected="$(profile_field "$account" theme)"
    [[ -n "$expected" ]] || return 0
    theme_apply_for "$account" "$expected"
}

# --- machine-level locks ---

# expected in a local first: inline, an unusable parent name would make an
# empty rule file compare equal to it -- green forever with no rule (review §2.2).
polkit_admin_ok() {
    local parent file expected
    parent="$(conf_get "$MACHINE_CONF" parent 2>/dev/null || true)"
    [[ -n "$parent" ]] || return 1
    expected="$(posture_polkit_admin_rule_text "$parent")" || return 1
    file="$(posture_polkit_dir)/40-omarchy-kids.rules"
    [[ -f "$file" ]] && [[ "$(cat "$file")" == "$expected" ]]
}
polkit_admin_fix() {
    local parent
    parent="$(conf_get "$MACHINE_CONF" parent 2>/dev/null || true)"
    [[ -n "$parent" ]] || return 1
    posture_write_polkit_admin_rule "$parent"
}

polkit_deny_ok() {
    local file
    file="$(posture_polkit_dir)/41-omarchy-kids-deny.rules"
    [[ -f "$file" ]] && [[ "$(cat "$file")" == "$(posture_polkit_deny_rule_text)" ]]
}
polkit_deny_fix() { posture_write_polkit_deny_rule; }

# sddm-theme (R-LOGIN, issue #14): the portal's conf.d drop-in, exact match.
sddm_theme_ok() {
    local file
    file="$(posture_sddm_conf_dir)/zz-omarchy-kids-theme.conf"
    [[ -f "$file" ]] && [[ "$(cat "$file")" == "$(posture_sddm_theme_dropin_text)" ]]
}
sddm_theme_fix() { posture_write_sddm_theme_dropin; }

# portal-conf (issue #39): theme.conf.user, rebuilt whole every time from
# the current kid profiles + machine.conf's parent= -- docs/assert.md.
portal_conf_expected() {
    local parent entries=() line
    parent="$(conf_get "$MACHINE_CONF" parent 2>/dev/null || true)"
    [[ -n "$parent" ]] || return 1
    while IFS= read -r line; do
        [[ -n "$line" ]] && entries+=("$line")
    done < <(portal_conf_entries "$KIDS_DIR")
    posture_portal_conf_text "$parent" "${entries[@]+"${entries[@]}"}"
}
portal_conf_ok() {
    local expected file
    expected="$(portal_conf_expected)" || return 1
    file="$(posture_sddm_theme_dir)/theme.conf.user"
    [[ -f "$file" ]] && [[ "$(cat "$file")" == "$expected" ]]
}
portal_conf_fix() {
    local parent entries=() line
    parent="$(conf_get "$MACHINE_CONF" parent 2>/dev/null || true)"
    [[ -n "$parent" ]] || return 1
    while IFS= read -r line; do
        [[ -n "$line" ]] && entries+=("$line")
    done < <(portal_conf_entries "$KIDS_DIR")
    posture_write_portal_conf "$parent" "${entries[@]+"${entries[@]}"}"
}

pam_ok() {
    local file
    file="$(posture_pam_dir)/$1"
    [[ -f "$file" ]] && grep -qxF "$(posture_pam_namespace_marker)" "$file"
}
pam_fix() { posture_ensure_pam_namespace "$1"; }

# parent-unlock (R-SEC-2, R-SEC-3): the pam_exec line docs/authd.md
# describes, on sddm and whichever lock-screen stack this box has.
parent_unlock_ok() {
    local file
    file="$(posture_pam_dir)/$1"
    [[ -f "$file" ]] || return 2  # no such PAM stack here: nothing to look at
    grep -qxF "$(posture_parent_unlock_marker)" "$file"
}
parent_unlock_fix() { posture_ensure_parent_unlock_line "$1"; }

# getty@tty2..6 masked (R-FND-5): a symlink to /dev/null, checked
# directly rather than via systemctl -- docs/assert.md's "Judgment calls".
getty_unit_path() { printf '%s/etc/systemd/system/getty@tty%s.service' "$(posture_root)" "$1"; }
getty_ok() {
    local link
    link="$(getty_unit_path "$1")"
    [[ -L "$link" ]] && [[ "$(readlink "$link")" == "/dev/null" ]]
}
getty_fix() {
    local root_args=()
    [[ -n "$(posture_root)" ]] && root_args=(--root="$(posture_root)")
    systemctl "${root_args[@]}" mask "getty@tty$1.service"
}

# units (R-BOOT-3, R-SEC-2): enabled or the autologin drop-in never
# gets written. KIDS_UNITS/SOCKETS/TIMERS come from lib/units.sh, shared
# with bin/omarchy-kids-wizard's Apply-time enable --now (issue #46).
unit_link() { printf '%s/etc/systemd/system/%s.wants/%s' "$(posture_root)" "$1" "$2"; }
units_ok() {
    local u
    for u in "${KIDS_UNITS[@]}"; do [[ -L "$(unit_link multi-user.target "$u")" ]] || return 1; done
    for u in "${KIDS_SOCKETS[@]}"; do [[ -L "$(unit_link sockets.target "$u")" ]] || return 1; done
    for u in "${KIDS_TIMERS[@]}"; do [[ -L "$(unit_link timers.target "$u")" ]] || return 1; done
    # Enabled is not running: on a live system the sockets and timers must be active too.
    if [[ -z "$(posture_root)" ]]; then
        for u in "${KIDS_SOCKETS[@]}" "${KIDS_TIMERS[@]}"; do systemctl is-active --quiet "$u" || return 1; done
    fi
}
units_fix() {
    local root_args=()
    [[ -n "$(posture_root)" ]] && root_args=(--root="$(posture_root)")
    systemctl "${root_args[@]}" enable "${KIDS_UNITS[@]}" "${KIDS_SOCKETS[@]}" "${KIDS_TIMERS[@]}" || return 1
    # On a live system the sockets and timers must also be running now, not at the next boot
    # (seen live: enabled-but-inactive timers, no ledger tick). --root has no running systemd.
    [[ -n "$(posture_root)" ]] || systemctl start "${KIDS_SOCKETS[@]}" "${KIDS_TIMERS[@]}"
}

# parent-group (R-BAR-3, issue #37): the parent must be in omarchy-parents
# to read status.json (0640 root:omarchy-parents), or the bar renders nothing.
parent_group_ok() {
    local parent; parent="$(conf_get "$MACHINE_CONF" parent 2>/dev/null || true)"
    [[ -n "$parent" ]] || return 2  # machine.conf names no parent yet
    has_group "$(current_groups "$parent")" omarchy-parents
}
parent_group_fix() {
    local parent; parent="$(conf_get "$MACHINE_CONF" parent 2>/dev/null || true)"
    [[ -n "$parent" ]] || return 0
    groupadd -f omarchy-parents 2>/dev/null || true
    usermod -aG omarchy-parents "$parent"
}

# hyprland configs: every *.lua in $SHARE/hyprland copied verbatim to
# $ETC/hyprland (R-DESK-1), via omarchy-kids-session --install-configs
# when on PATH, else copied directly here (a scratch tree may lack it).
HYPR_SHARE="$SHARE/hyprland"
HYPR_ETC="$ETC/hyprland"
hyprland_ok() {
    [[ -d "$HYPR_SHARE" ]] || return 2  # the package's own configs are missing
    local f base
    for f in "$HYPR_SHARE"/*.lua; do
        [[ -e "$f" ]] || continue
        base="$(basename "$f")"
        [[ -f "$HYPR_ETC/$base" ]] || return 1
        cmp -s "$f" "$HYPR_ETC/$base" || return 1
    done
    return 0
}
hyprland_fix() {
    [[ -d "$HYPR_SHARE" ]] || return 0
    if command -v omarchy-kids-session >/dev/null 2>&1 \
        && OMARCHY_KIDS_ETC="$ETC" OMARCHY_KIDS_SHARE="$SHARE" omarchy-kids-session --install-configs >/dev/null 2>&1; then
        return 0
    fi
    install -d -m 0755 "$HYPR_ETC" || return 1
    local f base
    for f in "$HYPR_SHARE"/*.lua; do
        [[ -e "$f" ]] || continue
        base="$(basename "$f")"
        # atomic replace: Hyprland reloads on change, a half-written file shows a red banner
        install -m 0644 "$f" "$HYPR_ETC/.$base.tmp" && mv -f "$HYPR_ETC/.$base.tmp" "$HYPR_ETC/$base" || return 1
    done
}

# Chromium policy files (R-WEB-1): mode/owner only, for files that
# already exist -- no writer for them exists yet (docs/assert.md).
chromium_dir() { printf '%s/etc/chromium/policies/managed' "$(posture_root)"; }
# The group is part of the lock, not best-effort: chowning best-effort and
# returning 0 regardless used to report `fixed` on a wrong-group file
# forever (review S11). Skipped when the band group doesn't exist here.
chromium_ok() {
    local file="$1" band="${2:-}" group
    [[ "$(file_stat a "$file")" == "640" ]] || return 1
    group="$(group_for_band "$band" 2>/dev/null || true)"
    [[ -n "$group" ]] || return 0
    command -v getent >/dev/null 2>&1 && getent group "$group" >/dev/null 2>&1 || return 0
    [[ "$(file_stat G "$file")" == "$group" ]]
}
chromium_fix() {
    local file="$1" band="${2:-}" group
    chmod 0640 "$file" || return 1
    group="$(group_for_band "$band" 2>/dev/null || true)"
    [[ -n "$group" ]] || return 0
    command -v getent >/dev/null 2>&1 && getent group "$group" >/dev/null 2>&1 || return 0
    chown "root:$group" "$file"
}

# Boot hook (R-BOOT-5): checked only if the package's hook file is present.
# shellcheck disable=SC2034 # read by the sourcing command (bin/omarchy-kids-assert) and lib/check-locks.sh
HOOK_FILE="$(posture_root)/usr/lib/initcpio/hooks/omarchy-kids-unlock"
find_uki() {
    if [[ -n "${OMARCHY_KIDS_UKI:-}" ]]; then
        printf '%s\n' "$OMARCHY_KIDS_UKI"
        return 0
    fi
    local f
    for f in "$(posture_root)"/boot/EFI/Linux/*.efi; do
        [[ -e "$f" ]] || continue
        printf '%s\n' "$f"
        return 0
    done
    return 1
}
boot_hook_ok() {
    local uki tmp rc
    uki="$(find_uki)" || return 2  # no image found to check
    tmp="$(mktemp "${TMPDIR:-/tmp}/omarchy-kids-assert-initrd.XXXXXX")"
    if objcopy -O binary --only-section=.initrd "$uki" "$tmp" 2>/dev/null \
        && lsinitcpio "$tmp" 2>/dev/null | grep -q omarchy-kids-unlock; then
        rc=0
    else
        rc=1
    fi
    rm -f "$tmp"
    return "$rc"
}
boot_hook_fix() { mkinitcpio -P; }

