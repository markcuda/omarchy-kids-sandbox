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
  local transaction="$TRANSACTIONS_DIR/$account.json"
  [[ -e "$profile" || -f "$transaction" ]] || die "remove: no such kid account '$account'"

  local display_name
  display_name="$(conf_get "$profile" name 2>/dev/null || true)"
  [[ -n "$display_name" || "$DRY_RUN" != 0 ]] || display_name="$(luks_transaction_field "$account" display)"
  [[ -n "$display_name" ]] || display_name="$account"

  echo "Removing kid $account"

  # R-SEC-4: portal mode cannot prove a recorded key is gone. Disk mode
  # journals the slot before killing it, then completes or resumes the map.
  local slot="" device="" intent="" intent_file luks_mode="" account_state=""
  if [[ "$DRY_RUN" == 0 ]]; then
    transaction_dir_ensure || die "remove: could not create trusted transaction storage" 1
    luks_lock_acquire "$SLOTS_FILE" || die "remove: could not acquire the shared transaction lock" 1
  fi
  slot="$(luks_slot_for_account "$SLOTS_FILE" "$account" || true)"
  intent_file="$(luks_removal_intent_file "$SLOTS_FILE" "$account")"
  if [[ -e "$intent_file" ]]; then
    intent="$(luks_read_removal_intent "$SLOTS_FILE" "$account")" ||
      die "remove: invalid LUKS removal intent at $intent_file; repair it before retrying" 1
    slot="${intent%% *}"
  fi
  if [[ -f "$transaction" ]]; then
    kids_transaction validate "$TRANSACTIONS_DIR" "$account" ||
      die "remove: $account has no valid authoritative transaction; legacy slot mappings are not deletion proof" 1
    luks_mode="$(luks_transaction_field "$account" luks_mode)"
    if [[ "$luks_mode" == none && -n "$slot" ]]; then
      die "remove: non-LUKS transaction for $account conflicts with legacy slot evidence; preserve and repair it before removal" 1
    fi
    if [[ "$boot_mode" == portal && "$luks_mode" == owned ]]; then
      die "remove: portal mode cannot verify the owned LUKS identity for $account; remove it in disk mode first" 1
    fi
  fi
  if [[ "$boot_mode" == portal && -n "$slot" ]]; then
    die "remove: portal mode cannot verify recorded LUKS slot $slot for $account; remove the slot in disk mode first" 1
  fi
  if [[ "$DRY_RUN" == 0 ]]; then
    if [[ ! -f "$transaction" ]]; then
      if [[ "$boot_mode" == disk && -n "$slot" ]]; then
        device="$(detect_luks_device "$luks_device")" ||
          die "remove: disk mode cannot find the LUKS root for legacy slot $slot" 1
        luks_migrate_legacy_account_locked "$device" "$account" ||
          die "remove: legacy slot $slot for $account has no exact ownership token; no slot was deleted" 1
      elif [[ -z "$slot" ]]; then
        account_migrate_profile_locked "$account" ||
          die "remove: could not migrate the legacy profile for $account" 1
      fi
    fi
    kids_transaction validate "$TRANSACTIONS_DIR" "$account" ||
      die "remove: $account has no valid authoritative transaction; legacy slot mappings are not deletion proof" 1
    luks_mode="$(luks_transaction_field "$account" luks_mode)"
    account_state="$(luks_transaction_field "$account" account_state)"
    if [[ "$account_state" != complete && "$account_state" != removing && "$account_state" != unmounted &&
      "$account_state" != fstab_removed && "$account_state" != namespace_removed &&
      "$account_state" != accountsservice_removed && "$account_state" != face_removed &&
      "$account_state" != launcher_removed && "$account_state" != session_removed &&
      "$account_state" != account_removed && "$account_state" != home_moved && "$account_state" != cleaned ]]; then
      die "remove: account lifecycle for $account is incomplete ($account_state); finish or repair add first" 1
    fi
  elif [[ -f "$transaction" ]]; then
    luks_mode="$(luks_transaction_field "$account" luks_mode 2>/dev/null || true)"
  fi
  if [[ "$boot_mode" == disk && ("$luks_mode" == owned || "$DRY_RUN" != 0 && -n "$slot") ]]; then
    [[ -n "$device" ]] || device="$(detect_luks_device "$luks_device")" ||
      die "remove: disk mode cannot find the LUKS root for slot $slot" 1
    if [[ "$DRY_RUN" == "0" ]]; then
      luks_remove_account_slot_locked "$SLOTS_FILE" "$account" "$device" ||
        die "remove: LUKS slot removal did not finish for $account" 1
    else
      run luks_remove_account_slot "$SLOTS_FILE" "$account" "$device"
    fi
  fi

  if [[ "$DRY_RUN" == 0 ]]; then
    account_state="$(luks_transaction_field "$account" account_state)"
    if [[ "$account_state" == complete ]]; then
      kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" complete removing || die "remove: could not record account removal intent" 1
    fi
    if [[ "$(luks_transaction_field "$account" luks_mode)" == none &&
    "$(luks_transaction_field "$account" state)" == added ]]; then
      kids_transaction transition "$TRANSACTIONS_DIR" "$account" added removing || die "remove: could not record non-LUKS removal" 1
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
  if ! command -v findmnt >/dev/null 2>&1 || findmnt -no TARGET "$(home_dir_for "$account")" >/dev/null 2>&1; then
    run umount "$(home_dir_for "$account")"
  fi
  run posture_remove_fstab_line "$account"

  # Appendix B
  run launcher_map_remove "$account"
  run session_manifest_remove "$account"

  # R-FND-6: the account, then its home.
  if [[ "$DRY_RUN" == 0 ]]; then
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != removing ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" removing unmounted
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != unmounted ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" unmounted fstab_removed
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != fstab_removed ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" fstab_removed namespace_removed
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != namespace_removed ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" namespace_removed accountsservice_removed
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != accountsservice_removed ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" accountsservice_removed face_removed
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != face_removed ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" face_removed launcher_removed
    account_state="$(luks_transaction_field "$account" account_state)"
    [[ "$account_state" != launcher_removed ]] || kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" launcher_removed session_removed
  fi
  if [[ "$DRY_RUN" != 0 ]]; then
    run userdel "$account"
  elif [[ "$(luks_transaction_field "$account" account_state)" == session_removed ]]; then
    if ! userdel "$account"; then
      getent passwd "$account" 2>/dev/null | grep -q . && die "remove: userdel failed for $account" 1
    fi
  fi
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == session_removed ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" session_removed account_removed || die "remove: could not record account deletion" 1
  fi
  if ((! keep_home)); then
    local dest parent_home source
    parent_home="$(parent_home_dir "$MACHINE_CONF")"
    dest="$parent_home/Kids Mode/$display_name"
    source="$(home_dir_for "$account")"
    if [[ "$DRY_RUN" == 0 ]]; then
      kids_transaction destination "$TRANSACTIONS_DIR" "$account" "$dest" || die "remove: home destination conflicts with the journal" 1
      [[ ! -e "$dest" || ! -e "$source" ]] || die "remove: both home source and destination exist; refusing to overwrite either" 1
      [[ -e "$dest" || -e "$source" ]] || die "remove: both home source and recorded destination are absent; refusing to record file preservation" 1
    fi
    run install -d -m 0700 "$parent_home/Kids Mode"
    [[ ! -e "$source" ]] || run mv "$source" "$dest"
  fi
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == account_removed ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" account_removed home_moved || die "remove: could not record home retirement" 1
  fi
  # Keep the profile as the retry record until the account and home are done.
  run rm -f "$profile"
  if [[ "$DRY_RUN" == 0 && "$(luks_transaction_field "$account" account_state)" == home_moved ]]; then
    kids_transaction lifecycle "$TRANSACTIONS_DIR" "$account" home_moved cleaned || die "remove: could not record lifecycle completion" 1
    if [[ "$(luks_transaction_field "$account" luks_mode)" == none &&
    "$(luks_transaction_field "$account" state)" == removing ]]; then
      kids_transaction transition "$TRANSACTIONS_DIR" "$account" removing removed || die "remove: could not record non-LUKS retirement" 1
    fi
    luks_lock_release
  fi

  echo "Done: $account removed"
  echo "(groups, console masks, and the polkit rules stay until Remove Kids Mode -- SPEC.md R-FND-6)"
}
