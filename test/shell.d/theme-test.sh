#!/bin/bash
# Tests lib/theme.sh: theme_dir, theme_color, and theme_font (docs/theming.md).
#
# Every scenario runs in its own subshell (lib/theme.sh sourced fresh each
# time) so one test's PATH/env changes never leak into the next. Two fake
# tools go on a stub PATH: `omarchy-theme-color`, which mimics the real
# tool's `--file <colors.toml> <key>` interface (exit 1 / no output for a
# key it doesn't have, same as the real one) so these tests never depend
# on Omarchy actually being installed on the machine running test/all, and
# `fc-match`, mimicking `-f '%{family[0]}' monospace`.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
THEME_LIB="$ROOT/lib/theme.sh"

pass() { echo "PASS  $*"; }
fail() {
    echo "FAIL  $*"
    rc=1
}
rc=0

check_eq() { # got want label
    if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want '$2', got '$1')"; fi
}

TMP="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

STUBS="$TMP/stubs"
mkdir -p "$STUBS"

# Fake omarchy-theme-color: reads "--file <path> <key>", greps a plain
# "key=value" line out of that file (colors.toml's own real shape, quotes
# and all), same as the real parser's "one value per line" contract.
# Missing file or missing key: prints nothing and exits 1, exactly how the
# real tool reports "this theme doesn't define that key" (its own
# `[[ -n $value ]] || exit 1`). "--all" (theme_color's own readiness
# probe, lib/theme.sh's _theme_kids_tool_ready) succeeds whenever the file
# exists, regardless of which keys it defines — same as the real tool,
# which never fails just because a theme is missing a particular key.
cat >"$STUBS/omarchy-theme-color" <<'EOF'
#!/bin/bash
file="" key=""
while (( $# > 0 )); do
    case "$1" in
        --file) file="$2"; shift 2 ;;
        --all) key="--all"; shift ;;
        *) key="$1"; shift ;;
    esac
done
[[ -f "$file" ]] || exit 1
[[ "$key" == "--all" ]] && exit 0
value="$(sed -nE "s/^${key}[[:space:]]*=[[:space:]]*[\"']?([^\"']*)[\"']?.*/\1/p" "$file" | head -1)"
[[ -n "$value" ]] || exit 1
printf '%s\n' "$value"
EOF
chmod +x "$STUBS/omarchy-theme-color"

# Fake omarchy-theme-color that always fails, the way the real tool does
# when $OMARCHY_PATH isn't set outside a full Omarchy session (issue #48's
# live finding) — used below to prove that failure never aborts a caller,
# only falls back with one log line.
mkdir -p "$STUBS/broken-theme-color"
cat >"$STUBS/broken-theme-color/omarchy-theme-color" <<'EOF'
#!/bin/bash
echo "omarchy-theme-color: OMARCHY_PATH is not set" >&2
exit 1
EOF
chmod +x "$STUBS/broken-theme-color/omarchy-theme-color"

cat >"$STUBS/fc-match" <<'EOF'
#!/bin/bash
echo "Comic Sans MS"
EOF
chmod +x "$STUBS/fc-match"

FIXTURE_HOME="$TMP/home"
FIXTURE_THEME_DIR="$FIXTURE_HOME/.local/state/omarchy/current/theme"
mkdir -p "$FIXTURE_THEME_DIR"
cat >"$FIXTURE_THEME_DIR/colors.toml" <<'EOF'
background = "#111111"
foreground = "#eeeeee"
accent = "#22aaff"
muted = "#888888"
red = "#ff3333"
orange = "#ffaa00"
lighter_background = "#222222"
dark_background = "#050505"
selection = "#334455"
EOF

# --- theme_dir --------------------------------------------------------------

out="$(
    HOME="$FIXTURE_HOME"
    unset THEME_KIDS_HOME
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    theme_dir
)"
check_eq "$out" "$FIXTURE_THEME_DIR" "theme_dir: defaults to \$HOME/.local/state/omarchy/current/theme"

out="$(
    HOME="/somewhere/else"
    THEME_KIDS_HOME="$FIXTURE_HOME"
    export THEME_KIDS_HOME
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    theme_dir
)"
check_eq "$out" "$FIXTURE_THEME_DIR" "theme_dir: THEME_KIDS_HOME overrides \$HOME"

# --- theme_color: fixture theme dir, real-shaped omarchy-theme-color stub --

run_with_fixture() { # NAME
    (
        PATH="$STUBS:$PATH"
        THEME_KIDS_HOME="$FIXTURE_HOME"
        export PATH THEME_KIDS_HOME
        # shellcheck source=/dev/null
        source "$THEME_LIB"
        theme_color "$1"
    )
}

check_eq "$(run_with_fixture background)" "#111111" "theme_color background: reads colors.toml's own key"
check_eq "$(run_with_fixture foreground)" "#eeeeee" "theme_color foreground"
check_eq "$(run_with_fixture accent)" "#22aaff" "theme_color accent"
check_eq "$(run_with_fixture muted)" "#888888" "theme_color muted"
check_eq "$(run_with_fixture error)" "#ff3333" "theme_color error: mapped to colors.toml's 'red'"
check_eq "$(run_with_fixture warning)" "#ffaa00" "theme_color warning: mapped to colors.toml's 'orange'"
check_eq "$(run_with_fixture surface)" "#222222" "theme_color surface: mapped to 'lighter_background'"
check_eq "$(run_with_fixture surface_muted)" "#050505" "theme_color surface_muted: mapped to 'dark_background'"
check_eq "$(run_with_fixture highlight)" "#334455" "theme_color highlight: mapped to 'selection'"

# --- theme_color: fallback palette (no omarchy-theme-color on PATH) --------

run_no_tool() { # NAME
    (
        PATH="/usr/bin:/bin" # deliberately no omarchy-theme-color
        THEME_KIDS_HOME="$FIXTURE_HOME"
        export PATH THEME_KIDS_HOME
        # shellcheck source=/dev/null
        source "$THEME_LIB"
        theme_color "$1"
    )
}

check_eq "$(run_no_tool background)" "#1a1b26" "theme_color background: falls back with no omarchy-theme-color on PATH"
check_eq "$(run_no_tool accent)" "#8fb8ff" "theme_color accent: fallback"
check_eq "$(run_no_tool error)" "#f7768e" "theme_color error: fallback"
check_eq "$(run_no_tool warning)" "#ffd27a" "theme_color warning: fallback"
check_eq "$(run_no_tool surface)" "#232838" "theme_color surface: fallback"

# --- theme_color: tool present but this key isn't in the theme -------------

out="$(
    (
        PATH="$STUBS:$PATH"
        THEME_KIDS_HOME="$TMP/no-such-home"
        export PATH THEME_KIDS_HOME
        # shellcheck source=/dev/null
        source "$THEME_LIB"
        theme_color muted
    )
)"
check_eq "$out" "#9aa5ce" "theme_color: falls back when the theme has no colors.toml at all"

# --- theme_color: unknown name --------------------------------------------

(
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    theme_color nonsense >/dev/null 2>"$TMP/err"
)
theme_color_status=$?
check_eq "$theme_color_status" "1" "theme_color: unknown name exits 1"
check_eq "$(cat "$TMP/err")" "theme_color: unknown color 'nonsense'" "theme_color: unknown name prints a message"

# --- theme_font -------------------------------------------------------------

out="$(
    PATH="$STUBS:$PATH"
    export PATH
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    theme_font
)"
check_eq "$out" "Comic Sans MS" "theme_font: reads fc-match's resolved family"

out="$(
    PATH="/usr/bin:/bin" # deliberately no fc-match
    export PATH
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    theme_font
)"
check_eq "$out" "JetBrainsMono Nerd Font" "theme_font: falls back with no fc-match on PATH"

# --- issue #48 live finding: OMARCHY_PATH/LANG defaults, a broken tool
# never aborts the caller ---------------------------------------------------

out="$(
    unset OMARCHY_PATH
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    printf '%s\n' "$OMARCHY_PATH"
)"
check_eq "$out" "/usr/share/omarchy" "sourcing lib/theme.sh: OMARCHY_PATH defaults when unset"

out="$(
    OMARCHY_PATH=/some/other/path
    export OMARCHY_PATH
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    printf '%s\n' "$OMARCHY_PATH"
)"
check_eq "$out" "/some/other/path" "sourcing lib/theme.sh: an already-set OMARCHY_PATH is left alone"

out="$(
    unset LANG
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    printf '%s\n' "$LANG"
)"
check_eq "$out" "C.UTF-8" "sourcing lib/theme.sh: LANG defaults to C.UTF-8 when unset"

out="$(
    LANG=C
    export LANG
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    printf '%s\n' "$LANG"
)"
check_eq "$out" "C.UTF-8" "sourcing lib/theme.sh: LANG=C is also upgraded to C.UTF-8"

out="$(
    LANG=en_US.UTF-8
    export LANG
    # shellcheck source=/dev/null
    source "$THEME_LIB"
    printf '%s\n' "$LANG"
)"
check_eq "$out" "en_US.UTF-8" "sourcing lib/theme.sh: a real LANG is left alone"

# A tool on PATH that always dies the way the live report described
# ("OMARCHY_PATH is not set") must never abort a caller — not even one
# running under set -euo pipefail, the mode every bin/omarchy-kids-*
# command uses — and falls back to the palette with exactly one warning
# line, not one per color resolved.
# A `{ ...; } 2>file` group, not a trailing redirect on the assignment
# itself (`out="$(...)" 2>file`) — the plain bash 3.2 this also has to run
# under (AGENTS.md, lib/tui.sh's own _tui_array_copy comment) does not
# reliably apply a redirect trailing a bare assignment to the command
# substitution's own stderr; wrapping the assignment in a group does.
{
    out="$(
        set -euo pipefail
        PATH="$STUBS/broken-theme-color:$PATH"
        THEME_KIDS_HOME="$FIXTURE_HOME"
        export PATH THEME_KIDS_HOME
        # shellcheck source=/dev/null
        source "$THEME_LIB"
        for name in background foreground accent muted error warning; do
            theme_color "$name"
        done
        echo "survived rc=$?"
    )"
    rc_survived=$?
} 2>"$TMP/broken.err"
check_eq "$rc_survived" "0" "theme_color: a broken omarchy-theme-color under set -e never aborts the caller"
check_eq "$out" "$(printf '#1a1b26\n#ffffff\n#8fb8ff\n#9aa5ce\n#f7768e\n#ffd27a\nsurvived rc=0')" \
    "theme_color: falls back to the palette for every name when the tool is broken"
check_eq "$(wc -l <"$TMP/broken.err" | tr -d ' ')" "1" \
    "theme_color: a broken tool logs exactly one line, not once per color"
check_eq "$(cat "$TMP/broken.err")" \
    "theme_color: omarchy-theme-color is missing or failed here — using the fallback palette (docs/theming.md)" \
    "theme_color: the one log line explains what happened and where to read more"

echo "theme-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
