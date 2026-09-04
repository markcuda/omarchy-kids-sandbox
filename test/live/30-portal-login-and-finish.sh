#!/bin/bash
# 30-portal-login-and-finish: from the portal, log in as the test kid, open the exit modal
# (three Super taps within 1.5s), Finish with the parent password, and confirm the portal comes
# back (SPEC.md §8 item 3; docs/exit.md's "Verified live" sequence, which this mirrors exactly:
# Left/Enter/password to the launcher, triple Super, parent password, Enter on the only action).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/live/lib.sh
source "$DIR/lib.sh"

LIVE_PORTAL_STRAY_ACCOUNT="${LIVE_PORTAL_STRAY_ACCOUNT:-portal-stray}"
LIVE_PORTAL_STRAY_CREATED=0
# shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
portal_stray_cleanup() {
  if [[ "$LIVE_PORTAL_STRAY_CREATED" -eq 1 ]]; then
    vmroot "userdel '$LIVE_PORTAL_STRAY_ACCOUNT'" >/dev/null 2>&1 || true
  fi
}
trap portal_stray_cleanup EXIT

if vmroot "id -u '$LIVE_PORTAL_STRAY_ACCOUNT' >/dev/null 2>&1"; then
  ok "unallowlisted stray account is present: $LIVE_PORTAL_STRAY_ACCOUNT"
elif vmroot "useradd -M -s /usr/bin/nologin '$LIVE_PORTAL_STRAY_ACCOUNT'"; then
  LIVE_PORTAL_STRAY_CREATED=1
  ok "created unallowlisted stray account: $LIVE_PORTAL_STRAY_ACCOUNT"
else
  fail "could not create unallowlisted stray account: $LIVE_PORTAL_STRAY_ACCOUNT"
fi

build_install && ok "package installed and pacman -Qkk clean" ||
  fail "package build/install/Qkk gate failed"

boot_with "$LIVE_OWNER_PASSWORD" "$LIVE_OWNER_ACCOUNT" &&
  ok "vm booted" || fail "vm never came up"

portal_reset 30 && ok "greeter is up" || fail "greeter never appeared"

tile_counts="$(portal_live_tile_counts 2>/dev/null || true)"
expected_tiles="$(portal_live_config_tile_count 2>/dev/null || true)"
read -r actual_tiles observed_kids observed_parents <<<"$tile_counts"
if [[ "${actual_tiles:-}" =~ ^[0-9]+$ && "${observed_kids:-}" =~ ^[0-9]+$ &&
  "${observed_parents:-}" =~ ^[0-9]+$ && "$expected_tiles" =~ ^[0-9]+$ ]] &&
  ((actual_tiles == expected_tiles)) &&
  ((actual_tiles == observed_kids + observed_parents)); then
  ok "portal observed finalized tile count ($actual_tiles; kids=$observed_kids parents=$observed_parents)"
else
  fail "portal observed tile report is '$tile_counts', expected $expected_tiles from theme.conf.user"
fi

# Time's Up must not fire at login: earlier scenarios may have used today's budget up, and the
# overlay would swallow the Super taps below. Give the kid headroom for this run, restore after.
kid_budget_headroom "$LIVE_KID1_ACCOUNT" &&
  ok "budget_min raised to 600 for this run (was ${KID_BUDGET_BEFORE:-unset})" || fail "could not raise budget_min"

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
qmp enter >/dev/null # Finish is the modal's only action (share/exit-modal/shell.qml)

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

kid_budget_restore "$LIVE_KID1_ACCOUNT" && ok "budget_min restored to $KID_BUDGET_BEFORE" || fail "could not restore budget_min"

scenario_result 30-portal-login-and-finish
