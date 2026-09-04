#!/bin/bash
# 10-cold-boot-kid: cold boot the VM with a kid's disk password. R-BOOT's per-slot autologin
# should land straight in that kid's own omarchy-kids session, keyboard untouched (SPEC.md V7,
# §8 item 2's second half; docs/boot.md; docs/session.md's "Verified live" section).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/live/lib.sh
source "$DIR/lib.sh"

build_install && ok "package installed and pacman -Qkk clean" ||
  fail "package build/install/Qkk gate failed"

if boot_with "$LIVE_KID1_PASSWORD" "$LIVE_KID1_ACCOUNT"; then
  ok "vm booted with ${LIVE_KID1_ACCOUNT}'s disk password"
else
  fail "vm never came up on ${LIVE_KID1_ACCOUNT}'s disk password"
fi

if assert_session "$LIVE_KID1_ACCOUNT" 60; then
  ok "$LIVE_KID1_ACCOUNT's session is live"
else
  fail "$LIVE_KID1_ACCOUNT's session never appeared"
  state
fi

shot 10-cold-boot-kid || fail "screenshot failed"

# The root launcher map is rebuilt at boot by omarchy-kids-assert; an empty environment there
# once produced a map with no app tiles (2026-09-03).
tiles="$(vmroot "jq -r '.tiles | length' /etc/omarchy-kids/launchers/$LIVE_KID1_ACCOUNT.json" 2>/dev/null | tr -d '[:space:]')"
if [[ "${tiles:-0}" -gt 2 ]]; then
  ok "root launcher map lists $tiles tiles for $LIVE_KID1_ACCOUNT"
else
  fail "root launcher map has only ${tiles:-0} tiles for $LIVE_KID1_ACCOUNT"
fi

# A live session is not a working desktop: the launcher must actually be running (2026-09-03,
# a session that failed closed on a missing manifest still counted as "live").
if vmroot "pgrep -u '$LIVE_KID1_ACCOUNT' -f 'omarchy-kids/launcher/shell.qml' >/dev/null" 2>/dev/null; then
  ok "the Level 1 launcher is running for $LIVE_KID1_ACCOUNT"
else
  fail "no launcher process for $LIVE_KID1_ACCOUNT (session-start failed closed?)"
  vmroot "uid=\$(id -u '$LIVE_KID1_ACCOUNT'); tail -3 /run/user/\$uid/omarchy-kids/session-\$uid.log" 2>/dev/null | cut -c1-160
fi

scenario_result 10-cold-boot-kid
