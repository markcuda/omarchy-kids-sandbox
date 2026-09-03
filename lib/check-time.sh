# shellcheck shell=bash
# lib/check-time.sh — omarchy-kids-check's Time section. Sourced by the
# dispatcher; not meant to be executed directly. docs/check.md.

run_time_section() {
  # SKIP under a scratch root: no live systemd to ask (docs/check.md).
  if [[ -z "$(posture_root)" ]]; then
    if systemctl is-active --quiet omarchy-kids-time.timer 2>/dev/null; then
      add_result Time "time:timer" pass "omarchy-kids-time.timer is active (R-TIME-1)"
    else
      add_result Time "time:timer" fail "omarchy-kids-time.timer is not active — screen time isn't being tracked (R-TIME-1)"
    fi
  else
    add_result Time "time:timer" skip "not checked under a scratch root (no live systemd to ask) — see the 'units' lock in the Locks section for enablement"
  fi

  local acct any=0 udir
  while IFS= read -r acct; do
    [[ -n "$acct" ]] || continue
    any=1
    udir="$(time_usage_dir "$acct")"
    if [[ -d "$udir" ]]; then
      add_result Time "time:ledger:$acct" pass "$udir exists (R-TIME-1)"
    else
      add_result Time "time:ledger:$acct" warn "$udir doesn't exist yet — no minutes recorded for $acct yet (normal before their first session)"
    fi
  done < <(kids_list "$KIDS_DIR")
  [[ "$any" == 1 ]] || add_result Time "time:ledger" skip "no kids provisioned; nothing to check"
}
