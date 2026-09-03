# shellcheck shell=bash
# lib/theme.sh — resolves Omarchy's per-theme colors and font the exact
# way Omarchy's own tools do (bin/omarchy-theme-color/-set/-current, all
# $HOME-relative — Omarchy is single-user), so every Kids Mode surface
# looks like the rest of the machine under whatever theme the parent
# picked. THEME_KIDS_HOME points that resolution at another account's
# $HOME, for a root-owned caller (lib/posture.sh) that needs the
# parent's theme rather than root's. Not meant to be executed directly;
# source it from a command or from lib/tui.sh. Full ground-truth
# citations against omacom/omarchy v4.0.2: docs/theming.md.
#
# A shell with no Omarchy session env sourced (SSH, a bare `unshare`, CI)
# leaves $OMARCHY_PATH unset, which omarchy-theme-color depends on to
# find its own files -- default it to /usr/share/omarchy, and LANG to
# C.UTF-8 (gum's box-drawing needs UTF-8), before any Omarchy tool below
# ever runs (issue #48). A theme tool that still fails never aborts the
# caller -- see _theme_kids_tool_ready -- it falls back to this file's
# own palette instead, with one log line.
: "${OMARCHY_PATH:=/usr/share/omarchy}"
export OMARCHY_PATH
if [[ -z "${LANG:-}" || "${LANG:-}" == "C" ]]; then
    export LANG=C.UTF-8
fi

# theme_dir — the directory whose colors.toml theme_color/theme_font read.
# THEME_KIDS_HOME overrides $HOME (posture code resolving another
# account's theme); unset/empty falls back to plain $HOME, matching every
# omarchy-theme-* script above.
theme_dir() {
    printf '%s/.local/state/omarchy/current/theme' "${THEME_KIDS_HOME:-$HOME}"
}

# _theme_kids_fallback NAME — theme_color's fallback (no omarchy-theme-
# color, no colors.toml yet, or an empty key): matches the hardcoded
# defaults share/sddm-theme/theme.conf already shipped. Plain case, not
# an associative array -- bash 3.2 (macOS) has neither.
_theme_kids_fallback() {
    case "$1" in
        background) printf '#1a1b26\n' ;;
        foreground) printf '#ffffff\n' ;;
        accent) printf '#8fb8ff\n' ;;
        muted) printf '#9aa5ce\n' ;;
        error) printf '#f7768e\n' ;;
        warning) printf '#ffd27a\n' ;;
        surface) printf '#232838\n' ;;
        surface_muted) printf '#1f2335\n' ;;
        highlight) printf '#3a4266\n' ;;
    esac
}
THEME_KIDS_FALLBACK_FONT="JetBrainsMono Nerd Font"

# _theme_kids_tool_ready — true once, cheaply, for the life of this
# process: whether `omarchy-theme-color` is on PATH *and* actually runs
# here (a real exit-0 on some invocation, not just "the file exists" —
# --all is used here because it never fails just for a key a theme
# doesn't define, only for the tool itself being broken/missing its own
# dependencies, e.g. $OMARCHY_PATH still not pointing at a real install).
# Checked once and cached in _THEME_KIDS_TOOL_STATUS: every theme_color
# call after the first reuses that answer instead of re-probing, and a
# broken tool logs exactly one line here, not once per color this file
# ever resolves.
_THEME_KIDS_TOOL_STATUS=""
_theme_kids_tool_ready() {
    if [[ -z "$_THEME_KIDS_TOOL_STATUS" ]]; then
        if command -v omarchy-theme-color >/dev/null 2>&1 \
            && omarchy-theme-color --file "$(theme_dir)/colors.toml" --all >/dev/null 2>&1; then
            _THEME_KIDS_TOOL_STATUS="ok"
        else
            _THEME_KIDS_TOOL_STATUS="unavailable"
            echo "theme_color: omarchy-theme-color is missing or failed here — using the fallback palette (docs/theming.md)" >&2
        fi
    fi
    [[ "$_THEME_KIDS_TOOL_STATUS" == "ok" ]]
}

# theme_color NAME — resolves one semantic color via omarchy-theme-color
# against theme_dir's colors.toml, falling back to _theme_kids_fallback.
# Three extra names beyond the required six (surface, surface_muted,
# highlight) map to real omarchy-theme-color keys for theme.conf's tile
# roles -- see docs/theming.md for which.
theme_color() {
    local name="$1" key value
    case "$name" in
        background | foreground | accent | muted) key="$name" ;;
        error) key="red" ;;
        warning) key="orange" ;;
        surface) key="lighter_background" ;;
        surface_muted) key="dark_background" ;;
        highlight) key="selection" ;;
        *)
            echo "theme_color: unknown color '$name'" >&2
            return 1
            ;;
    esac

    if _theme_kids_tool_ready; then
        value="$(omarchy-theme-color --file "$(theme_dir)/colors.toml" "$key" 2>/dev/null || true)"
    fi
    if [[ -z "${value:-}" ]]; then
        value="$(_theme_kids_fallback "$name")"
    fi
    printf '%s\n' "$value"
}

# theme_font — resolves the "monospace" fontconfig alias the same way
# Omarchy's shell does (`fc-match -f '%{family[0]}' monospace`).
# THEME_KIDS_HOME has no effect here on purpose: fontconfig resolves
# per-process, with no supported way to ask for another account's font.
# Falls back to theme.conf's original hardcoded value.
theme_font() {
    local family
    if command -v fc-match >/dev/null 2>&1; then
        family="$(fc-match -f '%{family[0]}' monospace 2>/dev/null || true)"
    fi
    [[ -n "${family:-}" ]] || family="$THEME_KIDS_FALLBACK_FONT"
    printf '%s\n' "$family"
}
