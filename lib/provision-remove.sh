# shellcheck shell=bash
# lib/provision-remove.sh — omarchy-kids-provision's "remove" subcommand:
# reverses a single kid's posture, LUKS slot, and portal/theme.conf.user
# entry. Sourced by the dispatcher; not meant to be executed directly.

cmd_remove() {
    local account="" keep_home=0

    while (($#)); do
        case "$1" in
            --keep-home) keep_home=1; shift ;;
            -h|--help) usage; exit 0 ;;
            --) shift ;;
            -*) die "remove: unknown option '$1'" ;;
            *)
                if [[ -z "$account" ]]; then account="$1"; else die "remove: unexpected argument '$1'"; fi
                shift
                ;;
        esac
    done

    [[ -n "$account" ]] || die "remove: needs an account"
    local profile="$KIDS_DIR/$account.conf"
    [[ -e "$profile" ]] || die "remove: no such kid account '$account' (no profile at $profile)"

    local display_name
    display_name="$(conf_get "$profile" name 2>/dev/null || true)"
    [[ -n "$display_name" ]] || display_name="$account"

    echo "Removing kid $account"

    # R-SEC-4: kill the LUKS slot (by number -- we can't test the kid's
    # password without the kid's password), then rewrite luks-slots from
    # what's left.
    local slot
    slot="$(luks_slot_for_account "$SLOTS_FILE" "$account" || true)"
    if [[ -n "$slot" ]]; then
        local device=""
        if device="$(detect_luks_device "")"; then
            run cryptsetup luksKillSlot --batch-mode "$device" "$slot"
        else
            echo "warning: no LUKS device found; slot $slot for $account was not killed on disk (luks-slots is rewritten anyway)" >&2
        fi
        local parent_line entries=() line acct
        parent_line="$(luks_slots_parent_line "$SLOTS_FILE")"
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            acct="${line#*=}"; acct="${acct%%:*}"
            [[ "$acct" == "$account" ]] && continue
            entries+=("$line")
        done < <(luks_slots_kid_entries "$SLOTS_FILE")
        run posture_write_luks_slots "$SLOTS_FILE" "$parent_line" "${entries[@]+"${entries[@]}"}"
    fi

    # R-FND-2a
    run posture_remove_namespace_lines "$account"

    # R-LOGIN-3
    run posture_remove_accountsservice "$account"

    # R-LOGIN, issue #39
    run posture_remove_face_icon "$account"

    # R-LOGIN, issue #39: theme.conf.user rebuilt without this account,
    # same full-rewrite shape as the luks-slots handling above.
    local parent portal_entries=() line
    parent="$(read_parent)"
    while IFS= read -r line; do
        [[ -n "$line" ]] && portal_entries+=("$line")
    done < <(portal_conf_entries "$KIDS_DIR" "$account")
    run posture_write_portal_conf "$parent" "${portal_entries[@]+"${portal_entries[@]}"}"

    # R-FND-2: unmount and drop the fstab line.
    run umount "$(home_dir_for "$account")"
    run posture_remove_fstab_line "$account"

    # Appendix B
    run rm -f "$profile"

    # R-FND-6: the account, then its home.
    run userdel "$account"
    if (( ! keep_home )); then
        local dest parent_home
        parent_home="$(parent_home_dir "$MACHINE_CONF")"
        dest="$parent_home/Kids Mode/$display_name"
        run install -d -m 0755 "$parent_home/Kids Mode"
        run mv "$(home_dir_for "$account")" "$dest"
    fi

    echo "Done: $account removed"
    echo "(groups, console masks, and the polkit rules stay until Remove Kids Mode -- SPEC.md R-FND-6)"
}
