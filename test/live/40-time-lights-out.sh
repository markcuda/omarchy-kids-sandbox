#!/bin/bash
# 40-time-lights-out: set the test kid's lights_out in the past, log in, and confirm the
# Time's Up overlay auto-finishes the session with no answer (SPEC.md §8 item 5; docs/time.md's
# "Verified live" section: Time's Up ran a countdown and auto-Finished after 60s).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test/live/lib.sh
source "$DIR/lib.sh"

build_install && ok "package installed and pacman -Qkk clean" \
    || fail "package build/install/Qkk gate failed"

boot_with "$LIVE_OWNER_PASSWORD" "$LIVE_OWNER_ACCOUNT" \
    && ok "vm booted" || fail "vm never came up"

if vmroot "omarchy-kids-conf set $LIVE_KID1_ACCOUNT lights_out 00:01 >/dev/null"; then
    ok "lights_out set in the past for $LIVE_KID1_ACCOUNT"
else
    fail "could not set lights_out"
fi

portal_reset 30 && ok "greeter is up" || fail "greeter never appeared"

if portal_login "$LIVE_KID1_ACCOUNT" "$LIVE_KID1_PASSWORD"; then
    ok "logged in as $LIVE_KID1_ACCOUNT"
else
    fail "portal login for $LIVE_KID1_ACCOUNT failed"
fi

shot 40-times-up || fail "screenshot failed"

if assert_no_session "$LIVE_KID1_ACCOUNT" 90; then
    ok "session auto-finished after lights-out"
else
    fail "$LIVE_KID1_ACCOUNT's session is still up past the auto-finish deadline"
    state
fi

if assert_greeter 30; then
    ok "greeter came back after auto-finish"
else
    fail "no greeter after auto-finish"
fi

# Idempotent re-run: put lights_out back so a later run of this (or any other) scenario doesn't
# find the kid already locked out from this test.
if vmroot "omarchy-kids-conf set $LIVE_KID1_ACCOUNT lights_out $LIVE_KID1_LIGHTS_OUT_RESET >/dev/null"; then
    ok "lights_out restored to $LIVE_KID1_LIGHTS_OUT_RESET"
else
    fail "could not restore lights_out"
fi

scenario_result 40-time-lights-out
