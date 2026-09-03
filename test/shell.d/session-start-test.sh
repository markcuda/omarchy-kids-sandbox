#!/bin/bash
# Tests bin/omarchy-kids-session-start's Level 1/2 launcher tile JSON
# (SPEC.md I-6, R-APPS-4; issue #42): each app tile is marked
# `installed: true|false` by checking a matched .desktop entry or the
# resolved exec's first word on PATH -- never `pacman -Q` (a fake PATH
# with a couple of present execs and none of the rest is the whole
# fixture, per the issue). By default a missing app's tile is omitted
# entirely (logged why); with apps.show_missing=yes it's kept, greyed,
# with a "not installed yet"/"installing..." caption -- "installing..."
# when the app's package is sitting in omarchy-kids-apps' own pending
# install queue.
#
# Fully self-contained, same shape as test/shell.d/apps-test.sh: real
# bin/omarchy-kids-conf and bin/omarchy-kids-apps run against scratch
# OMARCHY_KIDS_ETC/SHARE/ROOT trees; share/ is copied from the repo (real
# bands.toml and packs/), not faked. Only a couple of pack ids get a
# fake "installed" signal (a stub PATH executable or a fake .desktop
# file) -- the rest are simply never installed, which is the live VM
# state issue #42 describes (none of the 6-8 pack apps installed).
# `gtk-launch`/`quickshell`/`omarchy-kids-time` are never actually
# invoked: OMARCHY_KIDS_SESSION_START_NO_EXEC=1 makes the script return
# right after writing the tile JSON instead of exec'ing anything.
set -uo pipefail

# shellcheck source=test/shell.d/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_START="$DIR/bin/omarchy-kids-session-start"
CONF="$DIR/bin/omarchy-kids-conf"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP session-start-test.sh: python3 not found"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP session-start-test.sh: jq not found"
  exit 0
fi

fail=0
pass() { echo "ok   $*"; }
fail_() {
  echo "FAIL $*"
  fail=1
}
check() { # got want label
  if [[ "$1" == "$2" ]]; then pass "$3"; else fail_ "$3 (want '$2', got '$1')"; fi
}
check_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail_ "$3 (want to find '$2' in '$1')"; fi
}
check_not_contains() { # haystack needle label
  if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail_ "$3 (did not want to find '$2' in '$1')"; fi
}

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ETC="$TMP/etc"
SHARE="$TMP/share"
ROOT="$TMP/root" # OMARCHY_KIDS_ROOT (the apps-queue file lives under here)
RUN="$TMP/run"
APPDIR="$TMP/applications"
STUBS="$TMP/stubs"

mkdir -p "$SHARE/bands" "$SHARE/packs" "$ETC/kids" "$RUN" "$APPDIR" "$STUBS"
cp "$DIR/share/bands/bands.toml" "$SHARE/bands/"
cp "$DIR"/share/packs/*.toml "$SHARE/packs/"

ACCOUNT="kid-ada"
cat >"$ETC/kids/$ACCOUNT.conf" <<EOF
name=Ada Lovelace
avatar=fox
band=6-8
level=1
web=none
EOF

# --- fixture: one app "installed" via a matched .desktop file --------------
# (tuxpaint's pack id and pkg are both "tuxpaint"; find_desktop_file's
# substring match hits the basename either way.)
cat >"$APPDIR/tuxpaint.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Tux Paint
Exec=tuxpaint
Icon=tuxpaint-icon
EOF

# --- fixture: one app "installed" via a bare exec on PATH -------------------
# (gcompris's pack id is "gcompris"; resolve_tile falls back to running
# the id itself when no .desktop file matches, so a PATH executable
# named "gcompris" is what "installed" means for it here.)
cat >"$STUBS/gcompris" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUBS/gcompris"

# ktuberling, supertux, supertuxkart, klettres, kanagram: no .desktop
# file, no PATH executable -- stay missing and unqueued throughout,
# the live VM state issue #42 describes.

# blinken: missing, but its package is sitting in the pending install
# queue omarchy-kids-apps install --apply would have written.
QUEUE_FILE="$ROOT/var/lib/omarchy-kids/apps-queue"
mkdir -p "$(dirname "$QUEUE_FILE")"
printf 'blinken\n' >"$QUEUE_FILE"

source "$(dirname "${BASH_SOURCE[0]}")/tree.sh"
# `id -un` is how a command answers "which account am I?" now -- never
# $OMARCHY_KIDS_ACCOUNT (review §3.7) -- so this test stubs `id` the way
# it already stubs the rest of its world. The real uid is kept so every
# per-uid path (launcher-<uid>.json) still resolves to one place.
kids_id_stub "$STUBS" "$ACCOUNT" "$(id -u)"
# Only the stubs and a base toolset: an Omarchy box has the real
# omarchy-*/omarchy-kids-* commands on PATH, and a check that one is
# missing must not depend on this box (AGENTS.md, testing rules).
BASE_PATH="$(kids_base_path "$TMP/base")"
export PATH="$STUBS:$BASE_PATH"
export OMARCHY_KIDS_ETC="$ETC"
export OMARCHY_KIDS_SHARE="$SHARE"
export OMARCHY_KIDS_ROOT="$ROOT"
export OMARCHY_KIDS_RUN="$RUN"
export OMARCHY_KIDS_APPLICATIONS_DIRS="$APPDIR"
export OMARCHY_KIDS_SESSION_START_NO_EXEC="1"

LAUNCHER_JSON="$RUN/launcher-$(id -u).json"
LOG_FILE="$RUN/session-$(id -u).log"

tile() { # tile ID -> that tile's JSON object from the launcher file, or "null"
  jq -c --arg id "$1" '.tiles[] | select(.id == $id)' "$LAUNCHER_JSON" 2>/dev/null
}

# --- default (apps.show_missing unset -> "no"): installed apps show
# installed:true; missing apps are omitted entirely, logged why --------------

"$SESSION_START" >/dev/null
check "$?" "0" "session-start (default): exits 0"

tp="$(tile tuxpaint)"
check "$(echo "$tp" | jq -r '.installed')" "true" \
  "default: tuxpaint (matched .desktop) is installed:true"
check "$(echo "$tp" | jq -r '.exec')" "gtk-launch tuxpaint" \
  "default: tuxpaint's exec still resolves through the matched .desktop file"
# issue #54: the launcher (share/launcher/shell.qml) resolves this name
# through the icon theme itself (Quickshell.iconPath()) -- this script's
# job is only to hand it the desktop entry's raw Icon= value verbatim.
check "$(echo "$tp" | jq -r '.icon')" "tuxpaint-icon" \
  "default: tuxpaint's icon field carries the desktop entry's Icon= value"

gc="$(tile gcompris)"
check "$(echo "$gc" | jq -r '.installed')" "true" \
  "default: gcompris (bare exec on PATH) is installed:true"
check "$(echo "$gc" | jq -r '.icon')" "" \
  "default: gcompris (bare exec fallback, no matched .desktop) has an empty icon field"

check "$(tile ktuberling)" "" "default: ktuberling (missing, unqueued) tile is omitted"
check "$(tile blinken)" "" "default: blinken (missing, queued) tile is also omitted -- show_missing is off"
check "$(tile supertux)" "" "default: supertux tile is omitted"

log="$(cat "$LOG_FILE" 2>/dev/null || true)"
check_contains "$log" "tile omitted for 'ktuberling'" "default: log names the omitted ktuberling tile"
check_contains "$log" "not installed yet" "default: ktuberling's log line says 'not installed yet' (not queued)"
check_contains "$log" "tile omitted for 'blinken'" "default: log names the omitted blinken tile"
check_contains "$log" "installing..." "default: blinken's log line says 'installing...' (queued)"

# --- apps.show_missing=yes: missing apps are kept, greyed, captioned -------

"$CONF" set "$ACCOUNT" apps.show_missing yes >/dev/null
: >"$LOG_FILE"
rm -f "$LAUNCHER_JSON"

"$SESSION_START" >/dev/null
check "$?" "0" "session-start (apps.show_missing=yes): exits 0"

kt="$(tile ktuberling)"
[[ -n "$kt" ]] && pass "show_missing=yes: ktuberling tile is present" ||
  fail_ "show_missing=yes: ktuberling tile is present (got nothing)"
check "$(echo "$kt" | jq -r '.installed')" "false" "show_missing=yes: ktuberling is installed:false"
check "$(echo "$kt" | jq -r '.caption')" "not installed yet" \
  "show_missing=yes: ktuberling's caption is 'not installed yet' (unqueued)"

bl="$(tile blinken)"
[[ -n "$bl" ]] && pass "show_missing=yes: blinken tile is present" ||
  fail_ "show_missing=yes: blinken tile is present (got nothing)"
check "$(echo "$bl" | jq -r '.installed')" "false" "show_missing=yes: blinken is installed:false"
check "$(echo "$bl" | jq -r '.caption')" "installing..." \
  "show_missing=yes: blinken's caption is 'installing...' (queued)"

tp2="$(tile tuxpaint)"
check "$(echo "$tp2" | jq -r '.installed')" "true" "show_missing=yes: installed apps are unaffected (tuxpaint)"
check "$(echo "$tp2" | jq -r '.caption')" "" "show_missing=yes: an installed app's caption is empty"

log2="$(cat "$LOG_FILE" 2>/dev/null || true)"
check_not_contains "$log2" "tile omitted" "show_missing=yes: nothing is omitted, so nothing is logged as omitted"

exit $fail
