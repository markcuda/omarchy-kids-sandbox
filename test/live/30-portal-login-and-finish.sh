#!/bin/bash
# 30-portal-login-and-finish: from the portal, log in as the test kid, open the exit modal
# (three Super taps within 1.5s), Finish with the parent password, and confirm the portal comes
# back (SPEC.md §8 item 3; docs/exit.md's "Verified live" sequence, which this mirrors exactly:
# Left/Enter/password to the launcher, triple Super, parent password, Tab to Finish, Enter).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/live/lib.sh
source "$DIR/lib.sh"

build_install && ok "package installed and pacman -Qkk clean" ||
  fail "package build/install/Qkk gate failed"

boot_with "$LIVE_OWNER_PASSWORD" "$LIVE_OWNER_ACCOUNT" &&
  ok "vm booted" || fail "vm never came up"

portal_reset 30 && ok "greeter is up" || fail "greeter never appeared"

# Time's Up must not fire at login: earlier scenarios may have used today's budget up, and the
# overlay would swallow the Super taps below. Give the kid headroom for this run, restore after.
budget_before="$(vmroot "omarchy-kids-conf get $LIVE_KID1_ACCOUNT budget_min" 2>/dev/null)"
vmroot "omarchy-kids-conf set $LIVE_KID1_ACCOUNT budget_min 600 >/dev/null" &&
  ok "budget_min raised to 600 for this run (was ${budget_before:-unset})" || fail "could not raise budget_min"

if portal_login "$LIVE_KID1_ACCOUNT" "$LIVE_KID1_PASSWORD"; then
  ok "logged in as $LIVE_KID1_ACCOUNT from the portal"
else
  fail "portal login for $LIVE_KID1_ACCOUNT failed"
  state
fi

wait_kid_ready "$LIVE_KID1_ACCOUNT" && ok "launcher is up (binds live)" || fail "launcher never came up"
shot 30-launcher || fail "screenshot failed"

# Three Super taps inside 1.5s opens the exit modal (the `{ release = true }` bind every level
# config sets — docs/exit.md).
for _ in 1 2 3; do
  qmp key meta_l >/dev/null
  sleep 0.25
done
sleep 3
qmp type "$LIVE_OWNER_PASSWORD" >/dev/null
qmp key tab >/dev/null
qmp enter >/dev/null

if assert_no_session "$LIVE_KID1_ACCOUNT" 30; then
  ok "$LIVE_KID1_ACCOUNT's session ended after Finish"
else
  fail "$LIVE_KID1_ACCOUNT's session is still up after Finish"
  state
fi

if assert_greeter 30; then
  ok "greeter came back after Finish"
else
  fail "no greeter after Finish"
fi

shot 30-after-finish || fail "screenshot failed"

if [[ -n "$budget_before" ]]; then
  vmroot "omarchy-kids-conf set $LIVE_KID1_ACCOUNT budget_min $budget_before >/dev/null" &&
    ok "budget_min restored to $budget_before" || fail "could not restore budget_min"
fi

scenario_result 30-portal-login-and-finish
