#!/bin/bash
# Tests bin/omarchy-kids-conf, lib/conf.sh, and lib/conf.py (SPEC.md
# R-BAND-1, R-BAND-2, R-BUILD-5, Appendix B, Appendix C).
# Self-contained: runs entirely against scratch OMARCHY_KIDS_ETC and
# OMARCHY_KIDS_SHARE trees, so it never touches the real /etc or
# /usr/share. share/ is copied from the repo rather than faked, so this
# also exercises the real bands.toml and packs/ this issue ships.
set -uo pipefail

# shellcheck source=test/shell.d/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF="$DIR/bin/omarchy-kids-conf"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP conf-test.sh: python3 not found"
  exit 0
fi

TMP="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ETC="$TMP/etc"
SHARE="$TMP/share"
mkdir -p "$SHARE/bands" "$SHARE/packs"
cp "$DIR/share/bands/bands.toml" "$SHARE/bands/"
cp "$DIR"/share/packs/*.toml "$SHARE/packs/"

# issue #53: a scratch system themes dir ($OMARCHY_PATH/themes) for
# `theme`'s validation and `theme_apply_for`'s own file copy, plus a
# scratch home root so that copy never touches this box's real /home.
OMARCHY_PATH="$TMP/omarchy"
mkdir -p "$OMARCHY_PATH/themes/tokyo-night" "$OMARCHY_PATH/themes/catppuccin-latte"
echo 'background = "#1a1b26"' >"$OMARCHY_PATH/themes/tokyo-night/colors.toml"
echo 'background = "#eff1f5"' >"$OMARCHY_PATH/themes/catppuccin-latte/colors.toml"
OMARCHY_KIDS_HOME_ROOT="$TMP/homeroot"
mkdir -p "$OMARCHY_KIDS_HOME_ROOT/home/kid-ada"

# A base toolset only: a real Omarchy box already has a kid-ada account,
# and `getent passwd kid-ada` would send theme_apply_for at the real
# /home/kid-ada instead of the scratch root (AGENTS.md, testing rules).
BASE_PATH="$(kids_base_path "$TMP/base")"
export PATH="$BASE_PATH"

export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_PATH
export OMARCHY_KIDS_HOME_ROOT

fail=0
check() { # got want label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else
    echo "FAIL $3 (want '$2', got '$1')"
    fail=1
  fi
}
check_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then echo "ok   $3"; else
    echo "FAIL $3 (want to find '$2' in '$1')"
    fail=1
  fi
}
check_status() { # got_status want_status label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else
    echo "FAIL $3 (want exit $2, got $1)"
    fail=1
  fi
}

# --- bands / band ---------------------------------------------------------

out="$("$CONF" bands)"
check_contains "$out" "3-5" "bands lists 3-5"
check_contains "$out" "6-8" "bands lists 6-8"
check_contains "$out" "9-12" "bands lists 9-12"
check_contains "$out" "13+" "bands lists 13+"
check_contains "$out" "Pre-reader" "bands shows the 3-5 blurb"

out="$("$CONF" band 6-8)"
check_contains "$out" "level=1" "band 6-8 has level=1"
check_contains "$out" "web=garden" "band 6-8 has web=garden"
check_contains "$out" "budget_min=60" "band 6-8 has budget_min=60"
check_contains "$out" "lights_out=19:30" "band 6-8 has lights_out=19:30"
check_contains "$out" "lights_out_weekend=20:00" "band 6-8 weekend lights-out is 30 min later"
check_contains "$out" "terminal=none" "band 6-8 has no terminal"

out="$("$CONF" band 9-12)"
check_contains "$out" "level=2" "band 9-12 has level=2"
check_contains "$out" "wifi=helper" "band 9-12 has the safe wifi helper"
check_contains "$out" "terminal=playground" "band 9-12 has a playground terminal"

"$CONF" band nope-such-band >/dev/null 2>&1
check_status "$?" 2 "band with a bad name exits 2"

# --- slug (Appendix B.1) --------------------------------------------------

check "$("$CONF" slug Ada)" "kid-ada" "slug: Ada -> kid-ada"
check "$("$CONF" slug "Zoë  O'Brien")" "kid-zoeobrien" "slug: transliterates and drops non-alphanumerics"
LONG40="$(printf 'a%.0s' {1..40})"
slug_long="$("$CONF" slug "$LONG40")"
check "${#slug_long}" "28" "slug: a 40-char name is truncated to a 24-char slug (kid- + 24)"
check "$slug_long" "kid-$(printf 'a%.0s' {1..24})" "slug: truncated slug is the first 24 chars"

# --- set: fixture profile (kid-ada, band 6-8 per AGENTS.md) ---------------

"$CONF" set kid-ada name Ada >/dev/null
"$CONF" set kid-ada avatar fox >/dev/null
"$CONF" set kid-ada band 6-8 >/dev/null
"$CONF" set kid-ada theme tokyo-night >/dev/null
check_status "$?" 0 "set writes the identity keys"

# --- get: override -> band -> default fallback ----------------------------

check "$("$CONF" get kid-ada level)" "1" "get: level falls back to band 6-8's default (1)"
check "$("$CONF" get kid-ada web)" "garden" "get: web falls back to band default (garden)"
check "$("$CONF" get kid-ada onboarded)" "no" "get: onboarded falls back to the global default (no)"
check "$("$CONF" get kid-ada password)" "set" "get: password falls back to the global default (set)"
check "$("$CONF" get kid-ada allowlist)" \
  "gcompris,tuxpaint,ktuberling,blinken,supertux,supertuxkart,klettres,kanagram" \
  "get: allowlist falls back to the band's pack"

"$CONF" set kid-ada level 2 >/dev/null
check "$("$CONF" get kid-ada level)" "2" "get: an override wins over the band default"

# --- set: validation -------------------------------------------------------

"$CONF" set kid-ada level 9 >/dev/null 2>&1
check_status "$?" 2 "set: out-of-range level is refused"

"$CONF" set kid-ada web open-everything >/dev/null 2>&1
check_status "$?" 2 "set: a bad web value is refused"

"$CONF" set kid-ada lights_out "9pm" >/dev/null 2>&1
check_status "$?" 2 "set: a non-HH:MM lights_out is refused"

err="$("$CONF" set kid-ada frobnicate yes 2>&1 >/dev/null)"
status=$?
check_status "$status" 2 "set: an unknown key is refused"
check_contains "$err" "frobnicate" "set: the refusal names the bad key"

err="$("$CONF" get kid-ada frobnicate 2>&1 >/dev/null)"
status=$?
check_status "$status" 2 "get: an unknown key is also refused"

"$CONF" set kid-ada budget_min 75 >/dev/null
check "$("$CONF" get kid-ada budget_min)" "75" "set: a valid budget_min is written and read back"

# --- theme (issue #53): validation, get, and the real apply side effect ----

check "$("$CONF" get kid-ada theme)" "tokyo-night" "get: theme reads back the fixture's override"

"$CONF" set kid-ada theme "Not A Real Theme" >/dev/null 2>&1
check_status "$?" 2 "set: a theme name with spaces/caps is refused before it ever checks the themes dir"

err="$("$CONF" set kid-ada theme no-such-theme 2>&1 >/dev/null)"
status=$?
check_status "$status" 2 "set: a lowercase-shaped but non-existent theme is refused"
check_contains "$err" "no-such-theme" "set: the refusal names the bad theme"
check_contains "$err" "$OMARCHY_PATH/themes" "set: the refusal names where it looked"

"$CONF" set kid-ada theme catppuccin-latte >/dev/null
check "$("$CONF" get kid-ada theme)" "catppuccin-latte" "set: a real installed theme is accepted and read back"

KID_THEME_DIR="$OMARCHY_KIDS_HOME_ROOT/home/kid-ada/.local/state/omarchy/current/theme"
check "$(cat "$KID_THEME_DIR/colors.toml" 2>/dev/null)" "$(cat "$OMARCHY_PATH/themes/catppuccin-latte/colors.toml")" \
  "set theme: theme_apply_for actually copied the new theme's colors.toml to disk"
check "$(cat "$OMARCHY_KIDS_HOME_ROOT/home/kid-ada/.local/state/omarchy/current/theme.name" 2>/dev/null)" "catppuccin-latte" \
  "set theme: theme.name on disk matches what was just set"

# put kid-ada back on tokyo-night for the rest of this file's fixtures
"$CONF" set kid-ada theme tokyo-night >/dev/null

# get-with-no-override still behaves like name/avatar/band (theme joined
# REQUIRED_KEYS, docs/conf.md) -- a second, fresh kid that's never had
# `theme` set at all.
"$CONF" set kid-notheme name Notheme >/dev/null
"$CONF" set kid-notheme avatar fox >/dev/null
"$CONF" set kid-notheme band 6-8 >/dev/null
"$CONF" get kid-notheme theme >/dev/null 2>&1
check_status "$?" 2 "get: theme with no override at all exits 2, same as name/avatar/band"

# --- show: source column ----------------------------------------------------
# Match on the key at the start of the line and the source at the end,
# rather than the exact column widths, so this doesn't break if the
# formatting ever changes.

out="$("$CONF" show kid-ada)"
check "$(echo "$out" | awk '/^level[ \t]/{print $NF}')" "override" "show: an overridden key is marked override"
check "$(echo "$out" | awk '/^wifi[ \t]/{print $NF}')" "band" "show: a band-derived key is marked band"
check "$(echo "$out" | awk '/^onboarded[ \t]/{print $NF}')" "default" "show: a global-default key is marked default"

# --- reset: keeps identity keys, clears the rest ----------------------------

"$CONF" set kid-ada onboarded yes >/dev/null
"$CONF" set kid-ada password set >/dev/null
"$CONF" set kid-ada menu full >/dev/null
"$CONF" reset kid-ada >/dev/null

profile="$ETC/kids/kid-ada.conf"
check "$(grep -c '^name=' "$profile")" "1" "reset: name survives"
check "$(grep -c '^avatar=' "$profile")" "1" "reset: avatar survives"
check "$(grep -c '^band=' "$profile")" "1" "reset: band survives"
check "$(grep -c '^theme=' "$profile")" "1" "reset: theme survives (issue #53)"
check "$(grep -c '^password=' "$profile")" "1" "reset: password survives"
check "$(grep -c '^onboarded=' "$profile")" "1" "reset: onboarded survives"
check "$(grep -c '^level=' "$profile")" "0" "reset: level override is cleared"
check "$(grep -c '^menu=' "$profile")" "0" "reset: menu override is cleared"
check "$("$CONF" get kid-ada level)" "1" "reset: level reads back as the band default again"
check "$("$CONF" get kid-ada onboarded)" "yes" "reset: onboarded keeps its value across reset"

# --- profile file permissions (spec 5.1: root 0644) -------------------------

mode="$(kids_file_mode "$profile")"
check "$mode" "644" "profile file is mode 0644"

# --- machine set parent (issue #46: the wizard's Apply step writes this
#     before anything else, so omarchy-kids-authd and omarchy-kids-provision
#     both have a parent to check against) -----------------------------

MACHINE_CONF="$ETC/machine.conf"
out="$("$CONF" machine set parent mark)"
st=$?
check "$st" "0" "machine set parent exits 0"
check "$out" "machine: parent=mark" "machine set parent echoes what it wrote"
check "$(cat "$MACHINE_CONF" 2>/dev/null)" "parent=mark" "machine set parent creates machine.conf with the right line"
machine_mode="$(kids_file_mode "$MACHINE_CONF")"
check "$machine_mode" "644" "machine.conf is mode 0644, same as a kid's profile"

# idempotent, and in-place: a second write replaces the value, not appends.
"$CONF" machine set parent dana >/dev/null
check "$(cat "$MACHINE_CONF" 2>/dev/null)" "parent=dana" "machine set parent replaces the value in place, doesn't append a second line"
check "$(grep -c '^parent=' "$MACHINE_CONF")" "1" "machine set parent: still exactly one parent= line"

"$CONF" machine set parent "" >/dev/null 2>&1
check "$?" "2" "machine set parent rejects an empty value"

"$CONF" machine bogus parent mark >/dev/null 2>&1
check "$?" "2" "an unknown machine subcommand exits 2"

"$CONF" machine set bogus mark >/dev/null 2>&1
check "$?" "2" "an unknown machine key exits 2"

exit $fail
