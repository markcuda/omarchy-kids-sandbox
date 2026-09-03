# shellcheck shell=bash
# lib/provision-add.sh — omarchy-kids-provision's "add" subcommand: the
# Unix account, profile, every posture write, the LUKS slot, and the
# portal/theme.conf.user rebuild. Sourced by the dispatcher; not meant
# to be executed directly.

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
    # R-LOGIN / review S10: the display name reaches `usermod -c` (GECOS,
    # ':'-delimited), the portal's tab-delimited entry, and lib/posture.sh's
    # ':'/','-delimited kids= field. A name carrying any of those separators
    # -- or a newline -- silently shifts another kid's avatar or account onto
    # the wrong greeter tile. Refuse it here, once, at the only entry point.
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
    base_account="$("$CONF" slug "$display")"
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

    # R-FND-2: the account itself.
    # The package's install scriptlet creates these, but a checkout run (tests, the VM) may not have them.
    run groupadd -f omarchy-kids
    run groupadd -f "$group"
    run useradd -m -s /bin/bash -G "omarchy-kids,$group" "$account"

    # R-SEC-3: one password, or a locked account (3-5 only).
    if (( no_password )); then
        run usermod -L "$account"
    else
        printf '%s:%s\n' "$account" "$kid_password" | run chpasswd
    fi

    # R-LOGIN: the greeter's tile shows the kid's display name, not the
    # bare account suffix (issue #39 -- V1's live VM run showed "ada",
    # "cy" instead of "Ada", "Cy"). SDDM's UserModel reads "realName"
    # from the passwd GECOS field (docs/portal.md), not from
    # AccountsService, so this is `usermod -c`, not a posture_* writer.
    # `usermod -c` is chfn's non-interactive equivalent -- no PAM prompt,
    # no argv password. Re-asserted (idempotent, comparing the current
    # GECOS field) as the "gecos:<account>" lock in omarchy-kids-assert.
    run usermod -c "$display" "$account"

    # R-FND-2: home bind-mounted nosuid,nodev,noexec.
    run posture_add_fstab_line "$account"
    # A bind mount must exist before it can be remounted with restrictive flags.
    run mount --bind "$(home_dir_for "$account")" "$(home_dir_for "$account")"
    run mount -o remount,bind,nosuid,nodev,noexec "$(home_dir_for "$account")"

    # Appendix B: the profile.
    run "$CONF" set "$account" name "$display"
    run "$CONF" set "$account" avatar "$avatar"
    run "$CONF" set "$account" band "$band"
    run "$CONF" set "$account" password "$([[ $no_password == 1 ]] && echo none || echo set)"
    run "$CONF" set "$account" onboarded no

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

    # R-SEC-2: the parent-unlock verifier line (docs/authd.md), machine-level
    # and idempotent -- every kid's "add" calls this, but lib/posture.sh's
    # own marker check means only the first one that finds each stack ready
    # actually changes anything. Soft-fails (a warning, not a die): the lock
    # screen's PAM stack may not exist yet on this box (omarchy-apply-lock
    # hasn't run), and provisioning a kid should not be blocked on that.
    ensure_parent_unlock_soft sddm
    ensure_parent_unlock_soft "$(posture_parent_unlock_lock_stack)"

    # R-SEC-4: a LUKS key slot, only when there's a password and a device.
    if (( want_password )); then
        local device=""
        if device="$(detect_luks_device "$luks_device")"; then
            [[ -n "$parent_password" ]] || die "add: found a LUKS device ($device) but no parent password; pass --parent-password-stdin or --parent-password-fd"
            # Never through `run`: its `printf ' %q'` preview would print
            # both secrets (review S6). Same DRY_RUN contract, own preview.
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

    # R-LOGIN, issue #39: the actual file SDDM's UserModel reads for the
    # avatar on this stack -- see lib/posture.sh's own header comment on
    # posture_write_face_icon for why AccountsService's Icon= line above
    # isn't it. Copied from the same real avatar directory
    # posture_accountsservice_text's Icon= line points at, resolved
    # through $SHARE so tests can point it at a scratch tree.
    run posture_write_face_icon "$SHARE/avatars/$avatar.svg" "$account"

    # R-LOGIN: select the portal theme (share/sddm-theme/ ->
    # /usr/share/sddm/themes/omarchy-kids). Machine-level like the polkit
    # rules just above -- written once, left alone by "remove" until
    # Remove Kids Mode (R-FND-6), since the portal is still correct as
    # long as any kid profile remains.
    run posture_write_sddm_theme_dropin

    # R-LOGIN, issue #39: theme.conf.user, decided from the profile
    # registry rather than the "kid-" username prefix (docs/portal.md).
    # Rebuilt in full from every provisioned kid; this kid's entry is
    # appended explicitly (not read back off $KIDS_DIR) so DRY_RUN=1's
    # preview shows the correct content even though nothing was written.
    local portal_entries=() line
    while IFS= read -r line; do
        [[ -n "$line" ]] && portal_entries+=("$line")
    done < <(portal_conf_entries "$KIDS_DIR" "$account")
    portal_entries+=("$account"$'\t'"$display"$'\t'"$avatar")
    run posture_write_portal_conf "$parent" "${portal_entries[@]}"

    # Issue #10 finding (b): go through Omarchy's own per-user setup so the
    # desktop never shows "Pending Omarchy Migrations".
    # omarchy-provision-user refuses to run as root and needs the user's own $HOME; --first-install
    # marks every shipped migration done for a freshly created account (its documented purpose).
    # Its failure is a warning, not a failed provision: the account, slot, locks and profile
    # are all in place by now, and on a VM built from the ISO's offline set it fails on a
    # missing bundled Node tarball (seen live 2026-09-02). Fall back to marking migrations.
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

    echo "Done: $account"
}

# luks_occupied_slots DEVICE — every key slot in use, one number per
# line, sorted. Handles both dump spellings: LUKS2's "  N: luks2" under
# Keyslots:, and LUKS1's "Key Slot N: ENABLED".
luks_occupied_slots() {
    cryptsetup luksDump "$1" 2>/dev/null | sed -n \
        -e 's/^[[:space:]]*\([0-9][0-9]*\):[[:space:]]*luks2[[:space:]]*$/\1/p' \
        -e 's/^Key Slot \([0-9][0-9]*\): ENABLED[[:space:]]*$/\1/p' \
        | sort -n -u
}

# add_luks_slot ACCOUNT DEVICE — adds the kid's passphrase (fd 3) as a
# new key slot on DEVICE, authorized by the parent's (fd 4). Secrets
# arrive on file descriptors, never argv, so this is never called
# through `run` (whose %q preview would print both, review S6). The new
# slot is found by diffing luksDump before/after, not by
# --test-passphrase (which reports the first matching slot -- a kid
# typing the parent's own passphrase used to land a second "0=" line,
# review §1.10); that passphrase is now rejected up front instead.
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
