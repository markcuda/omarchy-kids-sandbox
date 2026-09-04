#!/bin/bash
# Tests bin/omarchy-kids-session-start's Level 1/2 display JSON
# (SPEC.md I-6, R-APPS-4; issue #42): executable argv and install state
# come only from the root-owned launcher map. By default a missing app's
# display tile is omitted; with apps.show_missing=yes it is kept, greyed,
# with a "not installed yet"/"installing..." caption.
#
# Fully self-contained, same shape as test/shell.d/apps-test.sh: real
# bin/omarchy-kids-conf and bin/omarchy-kids-apps run against scratch
# trees selected by constants in a copied command; share/ is copied from the repo (real
# bands.toml and packs/), not faked. Only a couple of pack ids get a
# fake "installed" signal in the root-built map (a stub PATH executable
# or a fake .desktop file); the rest are simply never installed.
# /usr/bin/quickshell and omarchy-kids-time are never actually
# invoked: OMARCHY_KIDS_SESSION_START_NO_EXEC=1 makes the script return
# right after writing the tile JSON instead of exec'ing anything.
set -uo pipefail

# shellcheck source=test/shell.d/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SESSION_START=""
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
mkdir -p "$ROOT/usr/share/applications"
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
# (tuxpaint's pack id and pkg are both "tuxpaint"; the root map's
# package-owned desktop lookup hits the basename either way.)
cat >"$APPDIR/tuxpaint.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Tux Paint
Exec=tuxpaint --file %F
Icon=tuxpaint-icon
EOF
cp "$APPDIR/tuxpaint.desktop" "$ROOT/usr/share/applications/"

# --- fixture: one app "installed" via a bare executable on PATH -------------
# (gcompris has no desktop entry, so the root-built map resolves its absolute
# executable path while the test PATH is controlled by this scratch tree.)
cat >"$STUBS/gcompris" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUBS/gcompris"
cp "$STUBS/gcompris" "$STUBS/tuxpaint"

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
export OMARCHY_KIDS_SESSION_START_NO_EXEC="1"

# Build the trusted map before the kid-side session starts.
LIB="$DIR/lib"
KIDS_DIR="$ETC/kids"
CONF_BIN="$DIR/bin/omarchy-kids-conf"
KIDS_PY=python3
LAUNCHER_MAP="$ETC/launchers/$ACCOUNT.json"
# The map builder shares the installed command's trusted readers in this fixture.
source "$DIR/lib/conf.sh"
source "$DIR/lib/kids.sh"
source "$DIR/lib/launcher-map.sh"
launcher_map_fix "$ACCOUNT"
check "$(kids_file_mode "$LAUNCHER_MAP" 2>/dev/null || true)" "644" \
  "root launcher map is mode 0644"

# The packaged command uses build-time constants; substitute them in this
# copied test command, never by exporting a runtime path override.
SESSION_ROOT="$TMP/installed"
mkdir -p "$SESSION_ROOT/bin"
cp -R "$DIR/lib" "$SESSION_ROOT/"
cp "$DIR/bin/omarchy-kids-session-start" "$SESSION_ROOT/bin/"
cp "$DIR/bin/omarchy-kids-conf" "$SESSION_ROOT/bin/"
cp "$DIR/bin/omarchy-kids-apps" "$SESSION_ROOT/bin/"
cp "$DIR/bin/omarchy-kids-time" "$SESSION_ROOT/bin/"
SESSION_COPY="$SESSION_ROOT/bin/omarchy-kids-session-start"
kids_set_const "$SESSION_COPY" ETC "$ETC"
kids_set_const "$SESSION_COPY" SHARE "$SHARE"
kids_set_const "$SESSION_COPY" SYSROOT "$ROOT"
kids_set_const "$SESSION_COPY" RUN "$RUN"
SESSION_START="$SESSION_COPY"

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
check "$(echo "$tp" | jq -r 'has("exec")')" "false" \
  "default: runtime tile has no executable field"
check "$(jq -r '.tiles[] | select(.id == "tuxpaint") | .argv[0]' "$LAUNCHER_MAP")" "$STUBS/tuxpaint" \
  "root map resolves tuxpaint to an absolute executable"
check "$(jq -r '.tiles[] | select(.id == "tuxpaint") | .argv | length' "$LAUNCHER_MAP")" "2" \
  "root map strips desktop-entry field codes but keeps fixed arguments"
# issue #54: the launcher resolves this name through the icon theme itself
# (Quickshell.iconPath()) -- this script only carries display metadata.
check "$(echo "$tp" | jq -r '.icon')" "tuxpaint-icon" \
  "default: tuxpaint's icon field carries the desktop entry's Icon= value"

gc="$(tile gcompris)"
check "$(echo "$gc" | jq -r '.installed')" "true" \
  "default: gcompris (bare exec on PATH) is installed:true"
check "$(echo "$gc" | jq -r '.icon')" "" \
  "default: gcompris (bare exec fallback, no matched .desktop) has an empty icon field"
check "$(jq -r '.tiles[] | select(.id == "gcompris") | .argv[0]' "$LAUNCHER_MAP")" "$STUBS/gcompris" \
  "root map resolves a bare pack executable to an absolute path"

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
check "$(echo "$kt" | jq -r 'has("exec")')" "false" \
  "show_missing=yes: missing runtime tile still has no executable field"

log2="$(cat "$LOG_FILE" 2>/dev/null || true)"
check_not_contains "$log2" "tile omitted" "show_missing=yes: nothing is omitted, so nothing is logged as omitted"

exit $fail
