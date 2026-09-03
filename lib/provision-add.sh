# shellcheck shell=bash
# lib/provision-add.sh — omarchy-kids-provision's "add" subcommand.
# Sourced by the dispatcher; not meant to be executed directly.
# docs/provision.md has the full design and every judgment call below.

cmd_add() {
    local display="" band="" avatar="fox"
    local want_password=0 no_password=0
    local parent_pw_stdin=0 parent_pw_fd="" luks_device=""

    while (($#)); do
        case "$1" in
            --band) band="${2:?--band needs a value}"; shift 2 ;;
            --avatar) avatar="${2:?--avatar needs a value}"; shift 2 ;;
            --password-stdin) want_password=1; shift ;;
            --no-password) no_password=1; shift ;;
            --parent-password-stdin) parent_pw_stdin=1; shift ;;
            --parent-password-fd) parent_pw_fd="${2:?--parent-password-fd needs a value}"; shift 2 ;;
            --luks-device) luks_device="${2:?--luks-device needs a value}"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            --) shift ;;
            -*) die "add: unknown option '$1'" ;;
            *)
                if [[ -z "$display" ]]; then display="$1"; else die "add: unexpected argument '$1'"; fi
                shift
                ;;
        esac
    done

    [[ -n "$display" ]] || die "add: needs a display name"
    # R-LOGIN / review S10: refused here, once, at the only entry point --
    # docs/provision.md's "Secrets and LUKS slots" section has the why.
    valid_display_name "$display" || die "add: display name may not contain a tab, newline, ':' or ',' and must be 1-64 characters"
    [[ -n "$band" ]] || die "add: needs --band"
    is_valid_band "$band" || die "add: unknown band '$band' (must be one of ${VALID_BANDS[*]})"
    if (( want_password && no_password )); then
        die "add: --password-stdin and --no-password are mutually exclusive"
    fi
    if (( ! want_password && ! no_password )); then
        die "add: needs --password-stdin or --no-password"
    fi
    if (( no_password )); then
        local optional
        optional="$(band_field "$band" password_optional)"
        [[ "$optional" == "true" ]] || die "add: --no-password is only allowed for band 3-5"
    fi

    local base_account account group
    base_account="$("$CONF_BIN" slug "$display")"
    account="$(unique_account "$base_account")"
    group="$(group_for_band "$band")"

    local kid_password="" parent_password=""
    if (( want_password )); then
        if ! IFS= read -r kid_password; then
            [[ -n "$kid_password" ]] || die "add: --password-stdin needs the password on stdin"
        fi
        local min
        min="$(band_field "$band" password_min)"
        [[ "${#kid_password}" -ge "$min" ]] || die "add: password too short for band $band (minimum $min characters)"
    fi
    if (( parent_pw_stdin )); then
        if ! IFS= read -r parent_password; then
            [[ -n "$parent_password" ]] || die "add: --parent-password-stdin needs a second stdin line"
        fi
    elif [[ -n "$parent_pw_fd" ]]; then
        IFS= read -r parent_password <&"$parent_pw_fd" || die "add: could not read the parent password from fd $parent_pw_fd"
    fi

    echo "Adding kid '$display' as $account (band $band)"

    # R-FND-2: the account itself (groupadd -f: a checkout run may lack these).
    run groupadd -f omarchy-kids
    run groupadd -f "$group"
    run useradd -m -s /bin/bash -G "omarchy-kids,$group" "$account"

    # R-SEC-3: one password, or a locked account (3-5 only).
    if (( no_password )); then
        run usermod -L "$account"
    else
        printf '%s:%s\n' "$account" "$kid_password" | run chpasswd
    fi

    # R-LOGIN, issue #39: the greeter's tile name comes from passwd's GECOS
    # field, not AccountsService (docs/portal.md) -- usermod -c, not a
    # posture_* writer. Re-asserted as the "gecos:<account>" lock.
    run usermod -c "$display" "$account"

    # R-FND-2: home bind-mounted nosuid,nodev,noexec (must exist before remount).
    run posture_add_fstab_line "$account"
    run mount --bind "$(home_dir_for "$account")" "$(home_dir_for "$account")"
    run mount -o remount,bind,nosuid,nodev,noexec "$(home_dir_for "$account")"

    # Appendix B: the profile.
    run "$CONF_BIN" set "$account" name "$display"
    run "$CONF_BIN" set "$account" avatar "$avatar"
    run "$CONF_BIN" set "$account" band "$band"
    run "$CONF_BIN" set "$account" password "$([[ $no_password == 1 ]] && echo none || echo set)"
    run "$CONF_BIN" set "$account" onboarded no

    # R-FND-3, R-FND-4: polkit admin identity + denies.
    local parent
    parent="$(read_parent)"
    [[ -n "$parent" ]] || die "cannot find 'parent=' in $MACHINE_CONF; run machine setup before provisioning a kid"
    run posture_write_polkit_admin_rule "$parent"
    run posture_write_polkit_deny_rule

    # R-FND-5: text consoles masked while any kid profile exists.
    local n sysctl_root=()
    [[ -n "${OMARCHY_KIDS_ROOT:-}" ]] && sysctl_root=(--root="$OMARCHY_KIDS_ROOT")
    for n in 2 3 4 5 6; do
        run systemctl "${sysctl_root[@]+"${sysctl_root[@]}"}" mask "getty@tty$n.service"
    done

    # R-FND-2a: a private noexec tmpfs for /tmp and /dev/shm.
    run posture_add_namespace_lines "$account"
    run posture_ensure_pam_namespace sddm
    run posture_ensure_pam_namespace systemd-user

    run posture_ensure_pam_namespace sddm-autologin

    # R-SEC-2: the parent-unlock verifier line (docs/authd.md), idempotent.
    # Soft-fails: the lock screen's PAM stack may not exist yet on this box.
    ensure_parent_unlock_soft sddm
    ensure_parent_unlock_soft "$(posture_parent_unlock_lock_stack)"

    # R-SEC-4: a LUKS key slot, only when there's a password and a device.
    if (( want_password )); then
        local device=""
        if device="$(detect_luks_device "$luks_device")"; then
            [[ -n "$parent_password" ]] || die "add: found a LUKS device ($device) but no parent password; pass --parent-password-stdin or --parent-password-fd"
            # Never through `run`: its preview would print both secrets
            # (review S6, docs/provision.md). Own DRY_RUN preview instead.
            if [[ "$DRY_RUN" == "0" ]]; then
                add_luks_slot "$account" "$device" \
                    3< <(printf '%s\n' "$kid_password") \
                    4< <(printf '%s\n' "$parent_password")
            else
                printf '  [dry-run]'
                printf ' %q' add_luks_slot "$account" "$device"
                printf ' <secret> <secret>\n'
            fi
        fi
    fi

    # R-LOGIN-3: pin the kid session, no session picker.
    run posture_write_accountsservice "$account" "$avatar"

    # R-LOGIN, issue #39: the file SDDM's UserModel actually reads for the
    # avatar, not AccountsService's Icon= above (docs/portal.md's "Avatars").
    run posture_write_face_icon "$SHARE/avatars/$avatar.svg" "$account"

    # R-LOGIN: select the portal theme. Left alone by "remove" until
    # Remove Kids Mode (R-FND-6) -- still correct while any kid remains.
    run posture_write_sddm_theme_dropin

    # R-LOGIN, issue #39: theme.conf.user, rebuilt whole (docs/portal.md).
    # This kid's entry is appended explicitly, not read back off $KIDS_DIR,
    # so DRY_RUN=1's preview shows the correct content unwritten.
    local portal_entries=() line
    while IFS= read -r line; do
        [[ -n "$line" ]] && portal_entries+=("$line")
    done < <(portal_conf_entries "$KIDS_DIR" "$account")
    portal_entries+=("$account"$'\t'"$display"$'\t'"$avatar")
    run posture_write_portal_conf "$parent" "${portal_entries[@]}"

    # Issue #10 finding (b): so the desktop never shows "Pending Omarchy
    # Migrations" -- docs/provision.md's "Known gap". A failure here is a
    # warning, not a failed provision: everything else is already in place.
    if command -v omarchy-provision-user >/dev/null 2>&1; then
        if ! run runuser -l "$account" -c "omarchy-provision-user --first-install"; then
            echo "warning: omarchy-provision-user failed for $account; marking Omarchy migrations done instead" >&2
            run mark_migrations_done "$account"
        fi
    else
        run mark_migrations_done "$account"
    fi

    # Issue #44: override whatever chromium-flags.conf Omarchy's per-user
    # setup just left in this fresh home with Kids Mode's own copy, minus
    # the extension-loading flag the kids policy always refuses.
    run install_kids_chromium_flags "$account"

    # R-DESK, issue #53: the kid's desktop matches the house look at first
    # login -- docs/theming.md. "$CONF_BIN" set is the one writer; nothing here
    # touches theme files directly.
    local parent_theme=""
    parent_theme="$(THEME_KIDS_HOME="$(posture_parent_home "$parent")" theme_current_name)"
    if [[ -n "$parent_theme" ]]; then
        run "$CONF_BIN" set "$account" theme "$parent_theme"
    else
        echo "warning: parent '$parent' has no current Omarchy theme yet (never ran 'omarchy theme set'); $account keeps the desktop's stock theme" >&2
    fi

    echo "Done: $account"
}

# luks_occupied_slots DEVICE — occupied slots, sorted, handling both
# LUKS2's and LUKS1's luksDump spellings.
luks_occupied_slots() {
    cryptsetup luksDump "$1" 2>/dev/null | sed -n \
        -e 's/^[[:space:]]*\([0-9][0-9]*\):[[:space:]]*luks2[[:space:]]*$/\1/p' \
        -e 's/^Key Slot \([0-9][0-9]*\): ENABLED[[:space:]]*$/\1/p' \
        | sort -n -u
}

# add_luks_slot ACCOUNT DEVICE — kid's passphrase on fd 3, parent's on fd
# 4, never argv, never through `run` (review S6, docs/provision.md).
add_luks_slot() {
    local account="$1" device="$2"
    local kid_password parent_password
    IFS= read -r kid_password <&3 || true
    IFS= read -r parent_password <&4 || true
    [[ -n "$kid_password" && -n "$parent_password" ]] || die "add: add_luks_slot needs both passphrases on fds 3 and 4"

    if cryptsetup open --test-passphrase --key-file=<(printf '%s' "$kid_password") "$device" >/dev/null 2>&1; then
        die "add: that password already unlocks $device; pick a different one for $account"
    fi

    local before after
    before="$(luks_occupied_slots "$device")"
    cryptsetup luksAddKey --batch-mode --key-file=<(printf '%s' "$parent_password") \
        "$device" <(printf '%s' "$kid_password") \
        || die "add: cryptsetup luksAddKey failed for $account (is the parent passphrase right?)"
    after="$(luks_occupied_slots "$device")"

    local slot
    slot="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)"
    [[ -n "$slot" ]] || die "add: luksAddKey reported success but no new key slot appeared on $device"

    local parent_line entries=()
    parent_line="$(luks_slots_parent_line "$SLOTS_FILE")"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        entries+=("$line")
    done < <(luks_slots_kid_entries "$SLOTS_FILE")
    entries+=("$slot=$account")
    posture_write_luks_slots "$SLOTS_FILE" "$parent_line" "${entries[@]}"
    echo "  LUKS slot $slot added for $account"
}
