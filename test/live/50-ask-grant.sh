#!/bin/bash
# 50-ask-grant: from the kid's own session, "Ask a grown-up" for 15 more minutes; a parent
# approves on the spot with their password; confirm the grant lands in the ledger (SPEC.md §8
# item 6; docs/ask.md's "Verified live" section — `omarchy-kids-ask time 15`, the parent password,
# and `omarchy-kids-time status` showing the raised budget within the minute).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/live/lib.sh
source "$DIR/lib.sh"

build_install && ok "package installed and pacman -Qkk clean" ||
  fail "package build/install/Qkk gate failed"

boot_with "$LIVE_OWNER_PASSWORD" "$LIVE_OWNER_ACCOUNT" &&
  ok "vm booted" || fail "vm never came up"

portal_reset 30 && ok "greeter is up" || fail "greeter never appeared"

kid_budget_headroom "$LIVE_KID1_ACCOUNT" &&
  ok "budget headroom set for the grant recovery run" || fail "could not set budget headroom"

if portal_login "$LIVE_KID1_ACCOUNT" "$LIVE_KID1_PASSWORD"; then
  ok "logged in as $LIVE_KID1_ACCOUNT"
else
  fail "portal login for $LIVE_KID1_ACCOUNT failed"
fi

wait_kid_ready "$LIVE_KID1_ACCOUNT" && ok "launcher is up for the grant recovery run" ||
  fail "launcher never came up for the grant recovery run"

before="$(vmroot "omarchy-kids-time status $LIVE_KID1_ACCOUNT | head -1")"

# `omarchy-kids-ask time 15` has to run inside the kid's own session (it execs the ask modal
# under that session's Wayland/D-Bus environment). docs/ask.md's own live run and the reference
# driver it cites harvest that environment off the launcher's already-running process and re-exec
# under it, detached, so this ssh call returns immediately and the modal opens on the console.
vmroot "cat > /tmp/live-ask.sh <<'EOS'
pid=\$(pgrep -u $LIVE_KID1_ACCOUNT -f launcher/shell.qml | head -1)
for v in WAYLAND_DISPLAY XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_ID DBUS_SESSION_BUS_ADDRESS; do
  export \$v=\"\$(tr '\\0' '\\n' </proc/\$pid/environ | grep \"^\$v=\" | cut -d= -f2-)\"
done
setsid omarchy-kids-ask time 15 >/tmp/live-ask.log 2>&1 < /dev/null &
EOS
chmod 755 /tmp/live-ask.sh; runuser -u $LIVE_KID1_ACCOUNT -- bash /tmp/live-ask.sh" &&
  ok "asked for 15 more minutes" || fail "could not start the ask modal"

sleep 5
shot 50-ask-modal || fail "screenshot failed"

qmp type "$LIVE_OWNER_PASSWORD" >/dev/null
qmp enter >/dev/null
sleep 5

waited=0
granted=0
status="$before"
while ((waited < 90)); do
  status="$(vmroot "omarchy-kids-time status $LIVE_KID1_ACCOUNT | head -1")"
  if [[ -n "$status" && "$status" != "$before" ]]; then
    granted=1
    break
  fi
  sleep 5
  waited=$((waited + 5))
done

if ((granted)); then
  ok "ledger shows the grant ('$before' -> '$status')"
  if assert_session "$LIVE_KID1_ACCOUNT" 15; then
    ok "kid session remains available after the root grant"
  else
    fail "kid session did not resume after the root grant"
  fi
else
  fail "ledger never reflected the +15 grant (still: '$before')"
fi

shot 50-root-time-granted || fail "screenshot failed"
kid_budget_restore "$LIVE_KID1_ACCOUNT" && ok "budget headroom restored" || fail "could not restore budget headroom"

scenario_result 50-ask-grant
