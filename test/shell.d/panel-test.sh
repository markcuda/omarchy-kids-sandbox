#!/bin/bash
# Tests bin/omarchy-kids-panel (SPEC.md R-WIZ-7, R-WIZ-8, R-ASK-2,
# R-TIME-4/5, R-FND-6; issue #21). Drives every screen through
# OMARCHY_KIDS_TUI_ANSWERS, same convention as test/shell.d/wizard-test.sh.
#
# Two kinds of check here:
#
#   - dry-run (the default): asserts the exact "[dry-run] sudo ..." line
#     the panel itself prints for a write, same style as
#     wizard-test.sh's own checks -- no stub PATH needed for these, since
#     DRY_RUN=1 never reaches a real command.
#   - real mode (--apply): a pass-through `sudo` fake (same shape as
#     wizard-test.sh's RM_STUBS/sudo) plus a "spy" wrapper around each of
#     omarchy-kids-conf/-time/-ask/-apps/-web/-provision that logs its own
#     argv to $ARGV_LOG and then runs the *real* command against this
#     file's own scratch OMARCHY_KIDS_ETC/SHARE/ROOT trees -- so these
#     checks prove both the exact command AND that it actually did the
#     right thing (a budget that's really changed, an app that's really
#     hidden, a request that's really approved). omarchy-kids-provision's
#     spy is the one exception: `remove` is faked (logged, not really
#     run) rather than dragging in provision-test.sh's whole
#     useradd/cryptsetup/mount stub environment for a check that's really
#     about the panel's own wiring, not provision's own correctness
#     (that's provision-test.sh's job).
#
# One provisioned kid throughout: kid-ada, band 6-8 (AGENTS.md rule 9).
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT_DIR/bin/omarchy-kids-panel"

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP panel-test.sh: python3 not found (needed by omarchy-kids-conf/-ask)"
    exit 0
fi

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; rc=1; }
rc=0

check_contains() { # haystack needle label
    if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (want to find '$2' in '$1')"; fi
}
check_not_contains() { # haystack needle label
    if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail "$3 (did not want to find '$2' in '$1')"; fi
}
check_status() { # got want label
    if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want exit $2, got $1)"; fi
}

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

ETC="$TMP/etc"
SHARE="$TMP/share"
ROOT="$TMP/root" # OMARCHY_KIDS_ROOT
STUBS="$TMP/stubs"
ARGV_LOG="$TMP/argv.log"
QUEUE_DIR="$ROOT/var/lib/omarchy-kids/queue"

mkdir -p "$ETC/kids" "$SHARE/bands" "$SHARE/packs" "$SHARE/avatars" "$STUBS" "$QUEUE_DIR"
cp "$ROOT_DIR/share/bands/bands.toml" "$SHARE/bands/"
cp "$ROOT_DIR"/share/packs/*.toml "$SHARE/packs/"
: >"$ARGV_LOG"

cat >"$ETC/kids/kid-ada.conf" <<'EOF'
name=Ada
avatar=fox
band=6-8
EOF

answers_file() { # writes $@ (one per line) to a fresh file, prints its path
    local f="$TMP/answers.$RANDOM"
    printf '%s\n' "$@" >"$f"
    printf '%s' "$f"
}

# run_panel ANSWERS_FILE [FLAGS...] -> stdout+stderr in $out, exit in
# $PANEL_STATUS. The answers-file harness has no terminal, so the panel's
# own default here is a preview; every call below says which it wants.
run_panel() {
    local answers="$1"
    shift
    out="$(OMARCHY_KIDS_TUI_ANSWERS="$answers" "$BIN" "$@" 2>&1)"
    PANEL_STATUS=$?
}

# --- dry-run: exact "[dry-run] sudo ..." lines, nothing on PATH stubbed
# beyond the real helper binaries beside this script (no writes ever
# actually run in this mode) ------------------------------------------

export OMARCHY_KIDS_ETC="$ETC" OMARCHY_KIDS_SHARE="$SHARE" OMARCHY_KIDS_ROOT="$ROOT"

answers="$(answers_file "kid:kid-ada" time grant 15 back back quit)"
run_panel "$answers" --dry-run
check_status "$PANEL_STATUS" 0 "dry-run grant exits 0"
check_contains "$out" "sudo $ROOT_DIR/bin/omarchy-kids-time grant kid-ada 15" \
    "dry-run: 'give more minutes' prints the exact grant command"

answers="$(answers_file "kid:kid-ada" time budget 45 back back quit)"
run_panel "$answers"
check_contains "$out" "sudo $ROOT_DIR/bin/omarchy-kids-conf set kid-ada budget_min 45" \
    "dry-run: changing the budget prints the exact conf-set command"

answers="$(answers_file "kid:kid-ada" apps gcompris back back quit)"
run_panel "$answers"
check_contains "$out" "sudo $ROOT_DIR/bin/omarchy-kids-apps hide kid-ada gcompris" \
    "dry-run: hiding an app prints the exact hide command"

answers="$(answers_file "kid:kid-ada" remove NotAda back quit)"
run_panel "$answers"
check_not_contains "$out" "omarchy-kids-provision remove" \
    "dry-run: a wrong confirmation name never even prints a remove command"
check_contains "$out" "didn't match" "dry-run: a wrong confirmation name says so"

answers="$(answers_file "kid:kid-ada" remove Ada back quit)"
run_panel "$answers"
check_contains "$out" "sudo $ROOT_DIR/bin/omarchy-kids-provision remove kid-ada --apply" \
    "dry-run: the right confirmation name prints the exact remove command"

answers="$(answers_file quit)"
run_panel "$answers"
check_status "$PANEL_STATUS" 0 "Home alone: 'quit' exits 0"
check_contains "$out" "Ada · 6-8" "Home lists the one provisioned kid"
check_contains "$out" "Add a kid" "Home offers Add a kid"
check_contains "$out" "Requests (0)" "Home shows the open-request count"
check_contains "$out" "Remove Kids Mode" "Home offers the Remove Kids Mode row"

answers="$(answers_file "@esc")"
run_panel "$answers"
check_status "$PANEL_STATUS" 0 "Home: Esc also leaves (I-5, keyboard-complete)"

answers="$(answers_file "@ctrlc" yes)"
run_panel "$answers"
check_status "$PANEL_STATUS" 130 "Home: Ctrl+C leaves with 130"

# --- real mode (--apply): a pass-through sudo, and a spy wrapper per
# helper binary that logs argv then runs the real thing --------------

# sudo: strips the flags this panel passes (-v with nothing else, or a
# command after them) and execs whatever's left -- same fake as
# wizard-test.sh's RM_STUBS/sudo.
cat >"$STUBS/sudo" <<'EOF'
#!/bin/bash
args=()
while (($#)); do
    case "$1" in
        -n | -v | -S) shift ;;
        -p) shift 2 ;;
        -u) shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
if ((${#args[@]} == 0)); then
    cat >/dev/null
    exit 0
fi
exec "${args[@]}"
EOF
chmod +x "$STUBS/sudo"

# spy NAME REAL -- logs "NAME argv..." to $ARGV_LOG, then execs REAL with
# the same argv (so the real behavior -- and the real command's own exit
# status -- still happen, against this file's scratch trees).
spy() {
    local name="$1" real="$2" f="$STUBS/$1"
    cat >"$f" <<EOF
#!/bin/bash
{ printf '%s' "$name"; printf ' %s' "\$@"; printf '\n'; } >> "$ARGV_LOG"
exec "$real" "\$@"
EOF
    chmod +x "$f"
}
spy omarchy-kids-conf "$ROOT_DIR/bin/omarchy-kids-conf"
spy omarchy-kids-time "$ROOT_DIR/bin/omarchy-kids-time"
spy omarchy-kids-ask "$ROOT_DIR/bin/omarchy-kids-ask"
spy omarchy-kids-apps "$ROOT_DIR/bin/omarchy-kids-apps"
spy omarchy-kids-web "$ROOT_DIR/bin/omarchy-kids-web"

# omarchy-kids-provision's spy fakes `remove` instead of really running
# it (see this file's header) but still forwards `list`/`--help` to the
# real thing, since the panel's Home screen and the password fallback
# both depend on those.
cat >"$STUBS/omarchy-kids-provision" <<EOF
#!/bin/bash
{ printf '%s' "omarchy-kids-provision"; printf ' %s' "\$@"; printf '\n'; } >> "$ARGV_LOG"
if [[ "\${1:-}" == "remove" ]]; then
    echo "kid-ada: removed (fake, panel-test.sh)"
    exit 0
fi
exec "$ROOT_DIR/bin/omarchy-kids-provision" "\$@"
EOF
chmod +x "$STUBS/omarchy-kids-provision"

export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_CONF_BIN="$STUBS/omarchy-kids-conf"
export OMARCHY_KIDS_TIME_BIN="$STUBS/omarchy-kids-time"
export OMARCHY_KIDS_ASK_BIN="$STUBS/omarchy-kids-ask"
export OMARCHY_KIDS_APPS_BIN="$STUBS/omarchy-kids-apps"
export OMARCHY_KIDS_WEB_BIN="$STUBS/omarchy-kids-web"
export OMARCHY_KIDS_PROVISION_BIN="$STUBS/omarchy-kids-provision"

# --- real: grant minutes ------------------------------------------------

cat >"$ETC/kids/kid-ada.conf" <<'EOF'
name=Ada
avatar=fox
band=6-8
EOF
: >"$ARGV_LOG"
answers="$(answers_file "kid:kid-ada" time grant 15 back back quit)"
run_panel "$answers" --apply
check_status "$PANEL_STATUS" 0 "real grant exits 0"
check_contains "$(cat "$ARGV_LOG")" "omarchy-kids-time grant kid-ada 15" \
    "real: 'give more minutes' actually calls the grant command"

# --- real: change the daily budget, and it's really written ------------

: >"$ARGV_LOG"
answers="$(answers_file "kid:kid-ada" time budget 45 back back quit)"
run_panel "$answers" --apply
check_status "$PANEL_STATUS" 0 "real budget change exits 0"
check_contains "$(cat "$ARGV_LOG")" "omarchy-kids-conf set kid-ada budget_min 45" \
    "real: changing the budget actually calls conf set"
check_contains "$(cat "$ETC/kids/kid-ada.conf")" "budget_min=45" \
    "real: the budget override is really on disk afterward"

# --- real: hide an app, and it's really written -------------------------

: >"$ARGV_LOG"
answers="$(answers_file "kid:kid-ada" apps gcompris back back quit)"
run_panel "$answers" --apply
check_status "$PANEL_STATUS" 0 "real hide exits 0"
check_contains "$(cat "$ARGV_LOG")" "omarchy-kids-apps hide kid-ada gcompris" \
    "real: hiding an app actually calls apps hide"
check_contains "$(cat "$ETC/kids/kid-ada.conf")" "apps.hidden=gcompris" \
    "real: the hidden app is really on disk afterward"

# --- real: approve a request, and it's really marked approved ----------

: >"$ARGV_LOG"
req_id="$(python3 "$ROOT_DIR/lib/ask.py" write "$QUEUE_DIR" --kid kid-ada --kind time \
    --what 15 --minutes 15)"
req_id="${req_id%.json}"
answers="$(answers_file requests "$req_id" approve back quit)"
run_panel "$answers" --apply
check_status "$PANEL_STATUS" 0 "real approve exits 0"
check_contains "$(cat "$ARGV_LOG")" "omarchy-kids-ask approve $req_id --apply" \
    "real: approving a request actually calls ask approve"
check_contains "$(cat "$QUEUE_DIR/$req_id.json")" '"state": "approved"' \
    "real: the request is really marked approved afterward"

# --- real: remove a kid, wrong confirmation -> nothing runs -------------

: >"$ARGV_LOG"
answers="$(answers_file "kid:kid-ada" remove "NotAda" back quit)"
run_panel "$answers" --apply
check_status "$PANEL_STATUS" 0 "real wrong-confirmation exits 0"
check_not_contains "$(cat "$ARGV_LOG")" "omarchy-kids-provision remove" \
    "real: a wrong confirmation name never calls provision remove"
[[ -e "$ETC/kids/kid-ada.conf" ]] && pass "real: kid-ada's profile is untouched after a wrong confirmation" ||
    fail "real: kid-ada's profile is untouched after a wrong confirmation"

# --- real: remove a kid, right confirmation -> the exact command runs --

: >"$ARGV_LOG"
answers="$(answers_file "kid:kid-ada" remove "Ada" quit)"
run_panel "$answers" --apply
check_status "$PANEL_STATUS" 0 "real right-confirmation exits 0"
check_contains "$(cat "$ARGV_LOG")" "omarchy-kids-provision remove kid-ada --apply" \
    "real: the right confirmation name actually calls provision remove"

# --- --help works with no terminal and no answers file needed ----------

help_out="$("$BIN" --help 2>&1)"
help_status=$?
check_status "$help_status" 0 "--help exits 0"
check_contains "$help_out" "Usage: omarchy-kids-panel" "--help prints usage"

# =====================================================================
# review §1.5: opened by a human, the panel is real
# =====================================================================
#
# The shipped app entry runs `env OMARCHY_KIDS_LAUNCHED_BY=desktop
# omarchy-kids`, which reaches the panel with no terminal at all. Before
# this fix a parent opened Kids Mode from the drawer, changed something,
# watched "[dry-run] sudo ..." scroll past and had no change. There is no
# flag the drawer can pass to fix that, so the default has to be right.

: >"$ARGV_LOG"
answers="$(answers_file "kid:kid-ada" time budget 55 back back quit)"
out="$(OMARCHY_KIDS_TUI_ANSWERS="$answers" OMARCHY_KIDS_LAUNCHED_BY=desktop "$BIN" 2>&1)"
check_status $? 0 "launched from the app entry: exits 0"
check_not_contains "$out" "[dry-run]" "launched from the app entry: no preview, this is a real run"
check_contains "$(cat "$ETC/kids/kid-ada.conf")" "budget_min=55" \
    "launched from the app entry: the change is really on disk (review §1.5)"

# ...and --dry-run still wins, even from the app entry.
: >"$ARGV_LOG"
answers="$(answers_file "kid:kid-ada" time budget 60 back back quit)"
out="$(OMARCHY_KIDS_TUI_ANSWERS="$answers" OMARCHY_KIDS_LAUNCHED_BY=desktop "$BIN" --dry-run 2>&1)"
check_contains "$out" "[dry-run]" "--dry-run wins over the app entry"
check_contains "$(cat "$ETC/kids/kid-ada.conf")" "budget_min=55" "--dry-run wrote nothing"

# ...and with no terminal and no app entry (a script, a test, CI) the
# safe default still holds -- AGENTS.md rule 8.
answers="$(answers_file "kid:kid-ada" time budget 70 back back quit)"
out="$(OMARCHY_KIDS_TUI_ANSWERS="$answers" "$BIN" 2>&1)"
check_contains "$out" "[dry-run]" "no tty and no app entry: still previews by default"
check_contains "$(cat "$ETC/kids/kid-ada.conf")" "budget_min=55" "no tty: wrote nothing"

# The desktop entry really does set the marker the panel keys on.
DESKTOP="$ROOT_DIR/desktop/omarchy-kids.desktop"
check_contains "$(cat "$DESKTOP")" "OMARCHY_KIDS_LAUNCHED_BY=desktop" \
    "desktop/omarchy-kids.desktop marks itself as a human launch"

echo "panel-test.sh: done"
exit $rc
