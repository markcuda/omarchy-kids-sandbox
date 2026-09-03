# shellcheck shell=bash
# lib/theme.sh — resolves Omarchy's per-theme colors and font the exact
# way Omarchy's own tools do, so every Kids Mode surface (the wizard/panel
# TUI, the SDDM portal's theme.conf.user) looks like the rest of the
# machine under whatever theme the parent picked. Not meant to be
# executed directly; source it from a command or from lib/tui.sh.
#
# ============================== Ground truth ================================
# Fetched and read directly from omacom/omarchy at tag v4.0.2, 2026-09:
#
#   - bin/omarchy-theme-color: "Resolve semantic colors from an Omarchy
#     theme colors.toml" — the same tool docs/tui.md already cited this
#     repo's own wizard through ("the same tool Omarchy's own templates,
#     OSC sequences, and previews resolve colors through"). Defaults to
#     $HOME/.local/state/omarchy/current/theme/colors.toml, or --file
#     <path>. Resolves a semantic key (background, foreground, accent,
#     muted, red, green, yellow, blue, magenta/purple, cyan, orange,
#     brown, dark_background, darker_background, lighter_background,
#     dark_foreground, light_foreground, bright_foreground, selection,
#     cursor, mode/theme_type, colorN, and every bright_* variant),
#     falling back through legacy color0..15/short-name aliases and
#     derived shades when a theme only defines part of the palette.
#     Omarchy's own palette has no "error"/"warning" semantic key of its
#     own — theme_color below maps those to "red" and "orange" (orange
#     itself falls back to yellow when a theme doesn't define it,
#     omarchy-theme-color's own alias_theme_color call), the same colors
#     Omarchy's generated app configs use for error/warning states.
#   - bin/omarchy-theme-set: $HOME/.local/state/omarchy/current/theme is a
#     real directory (not a symlink), rebuilt whole on every
#     `omarchy-theme-set` — never $HOME/.config/omarchy/current/theme,
#     which does not exist on this stack.
#   - bin/omarchy-theme-current: the theme's own display name lives beside
#     it, in .../current/theme.name (one line, no [General] wrapper).
#   - shell/Commons/Style.qml's fontFamily/resolveFontFamily: the shell's
#     own font is always the fontconfig alias "monospace", resolved via
#     `fc-match -f '%{family[0]}' monospace` — never read from colors.toml
#     (theme Lua/toml never sets a font family; `omarchy font set` rewrites
#     ~/.config/fontconfig/fonts.conf instead). theme_font below runs the
#     exact same command.
#
# There is no *system-wide* (root-level) current theme anywhere in
# Omarchy 4.0.2 — every path above is $HOME-relative, because Omarchy is a
# single-user desktop. THEME_KIDS_HOME (below) is this file's own way to
# point that resolution at another account's $HOME — the parent's, when a
# root-owned caller (lib/posture.sh, provisioning the portal before any
# user has ever logged in) needs the parent's theme rather than root's.
# ==============================================================================
#
# Live finding (issue #48, 2026-09): running a Kids Mode command from a
# shell without Omarchy's own session environment sourced (no interactive
# login through Hyprland — an SSH session, a bare `unshare`, a CI runner)
# leaves $OMARCHY_PATH unset, and `omarchy-theme-color` (and Omarchy's
# other bin/omarchy-* tools generally) depend on it being set to find
# their own installed files, dying with "OMARCHY_PATH is not set" instead
# of just failing the one color lookup. Two defenses, both applied the
# moment this file is sourced (before any Omarchy tool below ever runs),
# not per-call:
#   - OMARCHY_PATH defaults to /usr/share/omarchy (where the omarchy
#     package installs itself) when unset, so a real Omarchy tool that
#     needs it to find sibling files still can, even outside a full
#     session.
#   - LANG defaults to C.UTF-8 when unset or the plain "C" locale: gum's
#     own box-drawing characters (lib/tui.sh's bordered header) need a
#     UTF-8 locale to render, not just to look right.
# A theme tool that still fails after that (missing entirely, or dies for
# some other reason) never aborts the caller either way — see
# _theme_kids_tool_ready below — it just falls back to this file's own
# palette, with one log line, not silently and not by crashing.
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

# _theme_kids_fallback NAME — this repo's own dark palette, theme_color's
# fallback when omarchy-theme-color isn't on PATH, the resolved theme has
# no colors.toml yet (very early in a fresh install, or an account that
# has never run `omarchy theme set`), or a key comes back empty. Matches
# the hardcoded defaults share/sddm-theme/theme.conf and every
# share/**/*.qml file already shipped before this file existed, so a
# machine with no theme read yet looks exactly as it always has:
#   background/foreground/accent/muted/error/warning — theme_color's
#     required six; surface/surface_muted/highlight — three portal-only
#     extras (see theme_color's own comment on why).
# A plain case, not an associative array (bash 4+ only) — test/all also
# has to run under the plain bash 3.2 that ships with macOS, the same
# reason lib/tui.sh's own _tui_array_copy avoids namerefs.
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

# theme_color NAME — resolves one semantic color for the current theme
# (background, foreground, accent, muted, error, warning), through
# omarchy-theme-color against theme_dir's colors.toml, falling back to
# THEME_KIDS_FALLBACK when that tool, a theme, or the key itself isn't
# available. Three more names beyond the required six exist purely for
# share/sddm-theme/theme.conf's three tile-surface roles (tileColor,
# tileHighlightColor, parentTileColor), which need shades distinct from
# plain background/accent to read as tiles at all: surface maps to
# omarchy-theme-color's own "lighter_background" (a raised-card shade
# already derived from background), surface_muted to "dark_background"
# (a quieter shade, for the smaller parent tile), highlight to
# "selection" (Omarchy's own "this is the selected/current thing" color)
# — all three are real omarchy-theme-color keys, not invented here.
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

# theme_font — the family name Omarchy's own shell resolves the
# "monospace" fontconfig alias to right now (shell/Commons/Style.qml's
# fcMatchProc, tag v4.0.2: `fc-match -f '%{family[0]}' monospace`), so
# kid-facing text uses whatever font `omarchy font set` last picked.
# THEME_KIDS_HOME has no effect here on purpose: fontconfig resolves
# per-process from $HOME/.config/fontconfig (and system config), and
# there is no supported way to ask "what would fc-match return for a
# different account" — good enough for the portal's own use (root has no
# meaningful fontconfig of its own to prefer over the shipped fallback)
# and for every Quickshell surface (which always runs as the account
# whose font actually matters). Falls back to this repo's own default
# (theme.conf's original hardcoded value) when fc-match isn't installed.
theme_font() {
    local family
    if command -v fc-match >/dev/null 2>&1; then
        family="$(fc-match -f '%{family[0]}' monospace 2>/dev/null || true)"
    fi
    [[ -n "${family:-}" ]] || family="$THEME_KIDS_FALLBACK_FONT"
    printf '%s\n' "$family"
}
