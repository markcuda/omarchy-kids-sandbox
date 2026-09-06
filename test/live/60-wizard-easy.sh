#!/bin/bash
# 60-wizard-easy: drive the Easy wizard over `ssh -tt` (sudo's ticket is per-tty — docs/vm.md)
# with an answers file for the 6-8 band's Simple defaults, Apply for real, then cold boot as the
# kid it provisions (SPEC.md §8 item 1; docs/wizard.md's "Verified live" section, which this
# mirrors: all fifteen A1-A14 screens, Apply, then a cold boot on the new kid's disk password).
#
# Idempotent: if the wizard kid already exists (an earlier run of this scenario that 90-remove
# hasn't torn down, or one already provisioned by hand), the wizard step is skipped and this only
# re-confirms the cold boot.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/live/lib.sh
source "$DIR/lib.sh"

WIZARD_ANSWERS_ACTIVE=0
# shellcheck disable=SC2329 # invoked by EXIT/INT/TERM traps
wizard_answers_cleanup() {
  if [[ "$WIZARD_ANSWERS_ACTIVE" -eq 1 ]]; then
    if vmroot "rm -rf -- $(printf '%q' "$WIZARD_RUN_DIR")" >/dev/null 2>&1; then
      WIZARD_ANSWERS_ACTIVE=0
    else
      echo "wizard answers cleanup failed" >&2
      return 1
    fi
  fi
}
# shellcheck disable=SC2329 # invoked by EXIT/INT/TERM traps
wizard_answers_exit() {
  local status="$?"
  trap - EXIT INT TERM
  if ! wizard_answers_cleanup; then
    status=1
  fi
  exit "$status"
}
# shellcheck disable=SC2329 # invoked by INT/TERM/HUP traps
wizard_answers_signal() {
  local signal="$1"
  trap - EXIT INT TERM HUP
  wizard_answers_cleanup || echo "wizard answers cleanup failed" >&2
  if [[ "$signal" == INT ]]; then
    exit 130
  fi
  exit 143
}
trap wizard_answers_exit EXIT
trap 'wizard_answers_signal INT' INT
trap 'wizard_answers_signal TERM' TERM
trap 'wizard_answers_signal HUP' HUP

build_install && ok "package installed and pacman -Qkk clean" ||
  fail "package build/install/Qkk gate failed"

account="$(vm "omarchy-kids-conf slug '$LIVE_WIZARD_KID_NAME'")"
if [[ -n "$account" ]]; then
  ok "wizard kid's account will be $account"
else
  fail "could not compute the slug for $LIVE_WIZARD_KID_NAME"
  account="__unknown__" # never matches a real account; keeps the checks below harmless
fi

if vmroot "id $account >/dev/null 2>&1"; then
  ok "$account already provisioned — skipping the wizard run"
else
  WIZARD_RUN_DIR="$(vm 'umask 077; dir=$(mktemp -d /tmp/.omarchy-kids-wizard.XXXXXX) || exit 1; chmod 700 "$dir" || exit 1; printf "%s\n" "$dir"')" || {
    fail "could not create a private wizard directory"
    scenario_result 60-wizard-easy
  }
  WIZARD_ANSWERS_ACTIVE=1
  WIZARD_ANSWERS_PATH="$WIZARD_RUN_DIR/answers.txt"
  WIZARD_OUTPUT_PATH="$WIZARD_RUN_DIR/wizard.out"
  WIZARD_ANSWERS_Q="$(printf '%q' "$WIZARD_ANSWERS_PATH")"
  WIZARD_OUTPUT_Q="$(printf '%q' "$WIZARD_OUTPUT_PATH")"
  if vm_write_file "$WIZARD_ANSWERS_PATH" <<EOA; then
begin
$LIVE_OWNER_PASSWORD
$LIVE_WIZARD_KID_NAME
$LIVE_WIZARD_KID_AVATAR
6-8
simple
garden
default
pack
parent
1
$LIVE_WIZARD_KID_PASSWORD
$LIVE_WIZARD_KID_PASSWORD
apply
return
EOA
    ok "answers file written"
  else
    fail "could not write the answers file"
    scenario_result 60-wizard-easy
  fi

  # One `ssh -tt` session so the `sudo -v` warm-up and the wizard's own later `sudo` calls
  # share one tty-scoped ticket (docs/wizard.md's "Root and the one sudo prompt": DRY_RUN=0
  # does not cross sudo, so every step gets --apply on argv instead; the sudo ticket itself
  # still has to survive from the warm-up to the last apply_step_*, which needs one tty).
  out="$(vm_tty "sudo -S -p '' -v < <(sed -n '2p' $WIZARD_ANSWERS_Q) 2>/dev/null; status=\$?; [ \$status -eq 0 ] || exit \$status; OMARCHY_KIDS_TUI_ANSWERS=$WIZARD_ANSWERS_Q DRY_RUN=0 timeout 300 omarchy-kids-wizard --apply </dev/null >$WIZARD_OUTPUT_Q 2>&1; echo \"wizard-exit=\$?\"")"
  if wizard_answers_cleanup; then
    :
  else
    fail "could not remove the wizard answers file"
  fi

  if [[ "$out" == *"wizard-exit=0"* ]]; then
    ok "wizard Apply exited 0"
  else
    fail "wizard Apply did not exit 0 ($out)"
  fi

  if vmroot "id $account >/dev/null 2>&1"; then
    ok "$account exists after Apply"
  else
    fail "$account was not created"
  fi
fi

if boot_with "$LIVE_WIZARD_KID_PASSWORD" "$account"; then
  ok "vm booted with the wizard kid's disk password"
else
  fail "vm never came up on the wizard kid's password"
fi

if assert_session "$account" 60; then
  ok "$account's session is live"
else
  fail "$account's session never appeared"
  state
fi

shot 60-wizard-kid || fail "screenshot failed"

scenario_result 60-wizard-easy
