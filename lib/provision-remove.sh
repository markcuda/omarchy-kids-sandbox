# shellcheck shell=bash
# lib/provision-remove.sh — omarchy-kids-provision's "remove" subcommand.
# Sourced by the dispatcher; not meant to be executed directly. docs/provision.md.

cmd_remove() {
  local account="" keep_home=0 luks_device=""

  while (($#)); do
    case "$1" in
      --keep-home)
        keep_home=1
        shift
        ;;
      --luks-device)
        luks_device="${2:?--luks-device needs a value}"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --) shift ;;
      -*) die "remove: unknown option '$1'" ;;
      *)
        if [[ -z "$account" ]]; then account="$1"; else die "remove: unexpected argument '$1'"; fi
        shift
        ;;
    esac
  done

  [[ -n "$account" ]] || die "remove: needs an account"
  local boot_mode
  boot_mode="$(read_boot_mode)"
  if [[ "$boot_mode" == portal && -n "$luks_device" ]]; then
    die "remove: --luks-device is not available in portal mode"
  fi
  local profile="$KIDS_DIR/$account.conf"
  [[ -e "$profile" ]] || die "remove: no such kid account '$account' (no profile at $profile)"

  local display_name
  display_name="$(conf_get "$profile" name 2>/dev/null || true)"
  [[ -n "$display_name" ]] || display_name="$account"

  echo "Removing kid $account"

  # R-SEC-4: retain the mapping until the slot is gone, then rewrite it.
  local slot="" device=""
  if [[ "$boot_mode" == disk ]]; then
    slot="$(luks_slot_for_account "$SLOTS_FILE" "$account" || true)"
  fi
  if [[ -n "$slot" ]]; then
    device="$(detect_luks_device "$luks_device")" ||
      die "remove: disk mode cannot find the LUKS root for slot $slot" 1
    local parent_line entries=() line acct
    parent_line="$(luks_slots_parent_line "$SLOTS_FILE")"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      acct="${line#*=}"
      acct="${acct%%:*}"
      [[ "$acct" == "$account" ]] && continue
      entries+=("$line")
    done < <(luks_slots_kid_entries "$SLOTS_FILE")
    if [[ "$DRY_RUN" == "0" ]]; then
      local slot_state
      if luks_slot_occupied "$device" "$slot"; then
        cryptsetup luksKillSlot --batch-mode "$device" "$slot" ||
          die "remove: cryptsetup could not remove slot $slot for $account" 1
      else
        slot_state=$?
        ((slot_state == 1)) || die "remove: could not inspect LUKS slots on $device" 1
      fi
      posture_write_luks_slots "$SLOTS_FILE" "$parent_line" "${entries[@]+"${entries[@]}"}" ||
        die "remove: slot $slot is gone, but could not update $SLOTS_FILE; retry removal" 1
    else
      run cryptsetup luksKillSlot --batch-mode "$device" "$slot"
      run posture_write_luks_slots "$SLOTS_FILE" "$parent_line" "${entries[@]+"${entries[@]}"}"
    fi
  fi

  # R-FND-2a
  run posture_remove_namespace_lines "$account"

  # R-LOGIN-3
  run posture_remove_accountsservice "$account"

  # R-LOGIN, issue #39
  run posture_remove_face_icon "$account"

  # R-LOGIN, issue #39: theme.conf.user rebuilt without this account.
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
  run launcher_map_remove "$account"
  run session_manifest_remove "$account"

  # R-FND-6: the account, then its home.
  run userdel "$account"
  if ((!keep_home)); then
    local dest parent_home
    parent_home="$(parent_home_dir "$MACHINE_CONF")"
    dest="$parent_home/Kids Mode/$display_name"
    run install -d -m 0755 "$parent_home/Kids Mode"
    run mv "$(home_dir_for "$account")" "$dest"
  fi

  echo "Done: $account removed"
  echo "(groups, console masks, and the polkit rules stay until Remove Kids Mode -- SPEC.md R-FND-6)"
}
