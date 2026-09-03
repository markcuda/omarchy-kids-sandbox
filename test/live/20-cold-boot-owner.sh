#!/bin/bash
# 20-cold-boot-owner: cold boot with the owner's own disk password. R-BOOT's fail-safe: the
# owner always lands on their own desktop, never the portal, never a kids session (SPEC.md V7,
# §8 item 2's first half; docs/boot.md's "the owner's disk password lands on the owner's own
# desktop" fact, confirmed live in docs/session.md's "Verified live" section).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/live/lib.sh
source "$DIR/lib.sh"

build_install && ok "package installed and pacman -Qkk clean" ||
  fail "package build/install/Qkk gate failed"

if boot_with "$LIVE_OWNER_PASSWORD" "$LIVE_OWNER_ACCOUNT"; then
  ok "vm booted with the owner's disk password"
else
  fail "vm never came up on the owner's disk password"
fi

if assert_session "$LIVE_OWNER_ACCOUNT" 60; then
  ok "$LIVE_OWNER_ACCOUNT's own session is live"
else
  fail "$LIVE_OWNER_ACCOUNT's own session never appeared"
  state
fi

if assert_no_session "$LIVE_KID1_ACCOUNT" 5; then
  ok "no kid session started on the owner's boot"
else
  fail "a kid session started on the owner's boot — fail-safe broken"
fi

shot 20-cold-boot-owner || fail "screenshot failed"

scenario_result 20-cold-boot-owner
