#!/bin/bash
# Tests share/hyprland/L{1,2,3}.lua, share/hyprland/band-*.lua, and
# bin/omarchy-kids-session-start (SPEC.md R-DESK-1, R-DESK-3, R-DESK-5,
# Appendix E). Self-contained: writes only under a scratch $TMP.
#
# What this does NOT and cannot check without a real Hyprland/Quickshell
# (see docs/levels.md's verification-in-the-VM section and the header
# comments in the files themselves):
#   - that the Lua actually parses/runs under Hyprland's embedded Lua
#     (luac -p is used if available, but this dev environment and most
#     CI runners don't have a standalone Lua/luac, so that check is
#     usually SKIPped, not run)
#   - that `fullscreen = true` is really the right shape for a boolean
#     windowrule, that hl.unbind takes a key-combo string, or that
#     SUPER + RETURN is really Omarchy's terminal bind
#   - anything in share/launcher/shell.qml (no Quickshell here at all)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HYPR="$DIR/share/hyprland"
SESSION_START="$DIR/bin/omarchy-kids-session-start"

fail=0
check() { # got want label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else echo "FAIL $3 (want '$2', got '$1')"; fail=1; fi
}
check_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then echo "ok   $3"; else echo "FAIL $3 (want to find '$2' in '$1')"; fail=1; fi
}
# bind_combos FILE -> each o.bind(...)'s first (key-combo) argument, one
# per line, in file order.
bind_combos() {
  grep -oE '^o\.bind\("[^"]+"' "$1" | sed -E 's/^o\.bind\("(.*)"$/\1/'
}

sorted() { printf '%s\n' "$@" | sort; }

# sorted_combos FILE -> bind_combos's output, sorted, newline-joined.
# A plain while-read loop into an array, not `$(bind_combos ...)`
# unquoted (which word-splits "SUPER + Home" into three separate words)
# and not `mapfile` (bash 4+ only; keep this bash-3.2-safe).
sorted_combos() {
  local file="$1" line combos=()
  while IFS= read -r line; do
    combos+=("$line")
  done < <(bind_combos "$file")
  sorted "${combos[@]}"
}

# --- lua syntax, if luac is available (this repo ships no Lua of its
# own, so skipping is the common case, not a failure) --------------------

if command -v luac >/dev/null 2>&1; then
  for f in "$HYPR"/L1.lua "$HYPR"/L2.lua "$HYPR"/L3.lua "$HYPR"/band-3-5.lua "$HYPR"/band-6-8.lua; do
    if luac -p "$f" 2>/tmp/levels-test-luac.$$; then
      echo "ok   luac -p $(basename "$f")"
    else
      echo "FAIL luac -p $(basename "$f"): $(cat /tmp/levels-test-luac.$$)"
      fail=1
    fi
    rm -f /tmp/levels-test-luac.$$
  done
else
  echo "SKIP luac syntax check: luac not found"
fi

# --- L1: exactly the Appendix E set, nothing else -----------------------

L1_WANT=$(sorted \
  'SUPER + Home' \
  'SUPER + RETURN' \
  'SUPER + Q' \
  'SUPER + SHIFT + K' \
  'SUPER + SUPER_L' \
  'XF86AudioRaiseVolume' \
  'XF86AudioLowerVolume' \
  'XF86AudioMute' \
  'XF86MonBrightnessUp' \
  'XF86MonBrightnessDown')
L1_GOT=$(sorted_combos "$HYPR/L1.lua")
check "$L1_GOT" "$L1_WANT" "L1.lua binds exactly the Appendix E Level 1 set"

# --- L2: the L1 set plus Appendix E's Level 2 additions ------------------

L2_WANT=$(sorted \
  'SUPER + Home' \
  'SUPER + RETURN' \
  'SUPER + Q' \
  'SUPER + SHIFT + K' \
  'SUPER + SUPER_L' \
  'XF86AudioRaiseVolume' \
  'XF86AudioLowerVolume' \
  'XF86AudioMute' \
  'XF86MonBrightnessUp' \
  'XF86MonBrightnessDown' \
  'SUPER + LEFT' \
  'SUPER + RIGHT' \
  'SUPER + UP' \
  'SUPER + DOWN' \
  'SUPER + SHIFT + LEFT' \
  'SUPER + SHIFT + RIGHT' \
  'SUPER + SHIFT + UP' \
  'SUPER + SHIFT + DOWN' \
  'SUPER + K' \
  'SUPER + SPACE')
L2_GOT=$(sorted_combos "$HYPR/L2.lua")
check "$L2_GOT" "$L2_WANT" "L2.lua binds the Level 1 set plus Appendix E's Level 2 additions"

# --- L1/L2 never pull in Omarchy's own binding modules -------------------
#
# Matched against actual require(...) calls, not comment prose: both
# files' header comments explain, in English, why default.hypr.bindings.*
# is *not* required, which would otherwise false-positive a plain
# substring search.

for lvl in L1 L2; do
  requires="$(grep -E '^\s*require\("default\.hypr\.bindings' "$HYPR/$lvl.lua" || true)"
  check "$requires" "" "$lvl.lua never requires default.hypr.bindings.*"
done

# --- L3 requires the real Omarchy defaults and unbinds the terminal -----

l3_content="$(cat "$HYPR/L3.lua")"
check_contains "$l3_content" 'require("default.hypr.omarchy")' "L3.lua requires default.hypr.omarchy"
check_contains "$l3_content" 'hl.unbind("SUPER + RETURN")' "L3.lua unbinds the (assumed) terminal bind"
check_contains "$l3_content" 'o.bind("SUPER + SHIFT + K"' "L3.lua adds the Appendix E exit-modal bind"
check_contains "$l3_content" 'o.bind("SUPER + SUPER_L", "Kids Mode: exit (tap Super three times)", "omarchy-kids-super-tap", { release = true })' \
    "L3.lua adds the triple-tap release bind"

# --- session-start writes the expected launcher JSON ---------------------

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP session-start JSON checks: jq not found"
elif ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP session-start JSON checks: python3 not found"
else
  TMP="$(mktemp -d)"
  # shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
  cleanup() { rm -rf "$TMP"; }
  trap cleanup EXIT

  SHARE="$TMP/share"
  ETC="$TMP/etc"
  RUN="$TMP/run"
  mkdir -p "$SHARE/bands" "$SHARE/packs" "$ETC/kids" "$TMP/apps"
  cp "$DIR/share/bands/bands.toml" "$SHARE/bands/"
  cp "$DIR"/share/packs/*.toml "$SHARE/packs/"

  cat >"$ETC/kids/kid-ada.conf" <<'EOF'
name=Ada
avatar=fox
band=6-8
EOF

  cat >"$TMP/apps/tuxpaint.desktop" <<'EOF'
[Desktop Entry]
Name=Tux Paint
Icon=tuxpaint
Exec=tuxpaint
EOF

  out="$(
    OMARCHY_KIDS_ETC="$ETC" \
    OMARCHY_KIDS_SHARE="$SHARE" \
    OMARCHY_KIDS_RUN="$RUN" \
    OMARCHY_KIDS_ACCOUNT="kid-ada" \
    OMARCHY_KIDS_APPLICATIONS_DIRS="$TMP/apps" \
    OMARCHY_KIDS_SESSION_START_NO_EXEC=1 \
    bash "$SESSION_START"
  )"
  check "$out" "quickshell -p $SHARE/launcher/shell.qml" "session-start prints the Level 1 exec line"

  json_path="$RUN/launcher-$(id -u).json"
  if [[ -f "$json_path" ]]; then
    echo "ok   session-start wrote $json_path"
  else
    echo "FAIL session-start did not write a launcher JSON at $json_path"
    fail=1
  fi

  if command -v jq >/dev/null 2>&1 && [[ -f "$json_path" ]]; then
    check "$(jq -r '.account' "$json_path")" "kid-ada" "launcher JSON account"
    check "$(jq -r '.band' "$json_path")" "6-8" "launcher JSON band"
    check "$(jq -r '.level' "$json_path")" "1" "launcher JSON level (band 6-8's default)"
    check "$(jq -r '.tiles | length' "$json_path")" "8" "launcher JSON has all 8 apps from the 6-8 pack"
    check "$(jq -r '.tiles[0].id' "$json_path")" "gcompris" "launcher JSON keeps pack order (first tile is gcompris)"

    tuxpaint_tile="$(jq -c '.tiles[] | select(.id == "tuxpaint")' "$json_path")"
    check_contains "$tuxpaint_tile" '"icon":"tuxpaint"' "tuxpaint tile picks up the matched .desktop file's Icon="
    check_contains "$tuxpaint_tile" '"exec":"gtk-launch tuxpaint"' "tuxpaint tile launches via gtk-launch"

    gcompris_tile="$(jq -c '.tiles[] | select(.id == "gcompris")' "$json_path")"
    check_contains "$gcompris_tile" '"exec":"gcompris"' "gcompris tile falls back to a bare command with no matching .desktop file"

    check "$(jq -r '.tiles | map(select(.id == "chromium")) | length' "$json_path")" "0" \
      "R-WEB-4: no chromium tile when the band's Chromium policy file doesn't exist"
  fi

  # Level 2/3 exec the real Omarchy shell command.
  out2="$(
    OMARCHY_KIDS_ETC="$ETC" \
    OMARCHY_KIDS_SHARE="$SHARE" \
    OMARCHY_KIDS_RUN="$RUN" \
    OMARCHY_KIDS_ACCOUNT="kid-ada" \
    OMARCHY_KIDS_LEVEL=2 \
    OMARCHY_KIDS_APPLICATIONS_DIRS="$TMP/apps" \
    OMARCHY_KIDS_SESSION_START_NO_EXEC=1 \
    bash "$SESSION_START"
  )"
  check "$out2" "omarchy-launch-shell" "session-start prints the Level 2/3 exec line"
fi

exit $fail
