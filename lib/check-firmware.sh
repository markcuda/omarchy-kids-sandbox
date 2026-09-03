# shellcheck shell=bash
# lib/check-firmware.sh — omarchy-kids-check's Firmware section (R-TRUST-3).
# Sourced by the dispatcher; not meant to be executed directly. docs/check.md.

# run_firmware_section — a firmware password lives outside this OS, so this
# only checks machine.conf's firmware.card_done, a grown-up's attestation.
run_firmware_section() {
  if [[ "$(kid_conf_count)" == 0 ]]; then
    add_result Firmware "firmware:password" skip "no kids provisioned yet; the firmware-password step matters once a kid does"
    return
  fi
  local done_flag shown
  done_flag="$(conf_get "$MACHINE_CONF" firmware.card_done 2>/dev/null || true)"
  if [[ "$done_flag" == "yes" ]]; then
    add_result Firmware "firmware:password" pass "the firmware-password step is marked done in machine.conf. This can't be verified from software — it's a grown-up's word that a firmware password is set and the parent card is stored somewhere the kids can't reach (R-TRUST-3, SPEC.md §5.3)"
  else
    shown="${done_flag:-unset}"
    add_result Firmware "firmware:password" fail "the firmware-password step isn't marked done (machine.conf firmware.card_done=$shown). Print the parent card, set a firmware/BIOS password by hand on this machine (no command here can do it for you), then mark the card done (R-TRUST-3). Until then, anyone with physical access can boot other media and skip every lock in this report."
  fi
}
