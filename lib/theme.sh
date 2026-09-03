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

# theme_current_name — the display name of theme_dir's own theme
# (bin/omarchy-theme-current's own source: one line, no [General]
# wrapper, at .../current/theme.name beside the theme directory itself —
# this file's "Ground truth" header above). Empty, not an error, when
# that account has never run/received a theme yet. Respects
# THEME_KIDS_HOME the same way theme_dir does.
theme_current_name() {
    local f
    f="$(dirname "$(theme_dir)")/theme.name"
    [[ -r "$f" ]] && cat "$f" || true
}

# theme_account_home ACCOUNT — resolves ACCOUNT's $HOME: a real `getent
# passwd` lookup first (the account already exists by the time anything
# here is called), falling back to OMARCHY_KIDS_HOME_ROOT-prefixed
# "/home/<account>" for tests and for a box where the lookup fails —
# the exact shape bin/omarchy-kids-provision's own parent_home_dir and
# lib/posture.sh's posture_parent_home already use for the parent
# specifically; this is the same lookup, generalized once here (AGENTS.md:
# "no duplicated helpers") so posture_parent_home below just calls it and
# theme_apply_for/theme_reload_if_live (issue #53) can resolve *any*
# account's $HOME, not only the parent's.
theme_account_home() {
    local account="$1" home
    if command -v getent >/dev/null 2>&1; then
        home="$(getent passwd "$account" 2>/dev/null | cut -d: -f6)"
        [[ -n "$home" ]] && { printf '%s\n' "$home"; return 0; }
    fi
    printf '%s/home/%s\n' "${OMARCHY_KIDS_HOME_ROOT:-}" "$account"
}

# theme_list_installed — every theme name under the system themes dir
# ($OMARCHY_PATH/themes, the same OMARCHY_THEMES_PATH omarchy-theme-set
# reads system themes from), one per line, sorted. The wizard's Desktop
# group and the panel's Desktop screen (issue #53) both offer only these
# — never a kid- or parent-installed ~/.config/omarchy/themes/<name>,
# which theme_apply_for below deliberately doesn't overlay either (see
# its own header for why).
theme_list_installed() {
    local dir="$OMARCHY_PATH/themes" d
    [[ -d "$dir" ]] || return 0
    for d in "$dir"/*/; do
        [[ -d "$d" ]] || continue
        basename "$d"
    done | sort
}

# theme_apply_for ACCOUNT NAME — writes ACCOUNT's current theme in the
# same shape omarchy-theme-set builds for a live session (omacom/omarchy
# v4.0.2's bin/omarchy-theme-set, fetched 2026-09 — full text read
# directly): OMARCHY_THEMES_PATH="$OMARCHY_PATH/themes"; a fresh
# NEXT_THEME_PATH is populated with `cp -r "$OMARCHY_THEMES_PATH/$THEME_NAME/"*`;
# "Generate colors.toml from alacritty.toml if theme is missing colors.toml"
# (omarchy-theme-colors-from-alacritty); then "rm -rf $CURRENT_THEME_PATH;
# mv $NEXT_THEME_PATH $CURRENT_THEME_PATH"; then
# `echo "$THEME_NAME" >"$HOME/.local/state/omarchy/current/theme.name"`.
#
# Deliberately narrower than the real command: no
# ~/.config/omarchy/themes/<name> user-theme overlay (theme_list_installed
# above is the only source of valid NAMEs the wizard/panel ever offer —
# always one of $OMARCHY_PATH/themes' own names, never a kid- or
# parent-installed one), no background selection, and none of
# omarchy-theme-set's own post_theme_commands restarts — this repo has no
# session to restart for an account that may not even be logged in;
# theme_reload_if_live below is the "a session IS live" half of that,
# scoped to what a Kids Mode surface can actually ask for.
#
# Root-owned (root:root, 0644 files / 0755 dirs) inside the kid's own
# home — the same "root-owned file inside a kid-writable directory" shape
# bin/omarchy-kids-provision's install_kids_chromium_flags already uses,
# for the same reason: the kid still owns the containing directory
# (~/.local/state/omarchy/current/), so this alone can't stop a kid with
# a terminal (bands 9-12/13+) from deleting or replacing it — that's what
# the "theme:<account>" assert lock (bin/omarchy-kids-assert's theme_ok/
# theme_fix) is for: it notices drift and re-applies, the same
# eventually-fail-closed shape every other Kids Mode lock uses here, not
# an unbreakable barrier. chown/chmod failures are logged and otherwise
# ignored (the same "fine outside a real root run" shape
# install_kids_chromium_flags already uses), since every real run of this
# is root anyway.
theme_apply_for() {
    local account="$1" name="$2" home src current next tmp
    home="$(theme_account_home "$account")"
    src="$OMARCHY_PATH/themes/$name"
    if [[ ! -d "$src" ]]; then
        echo "theme_apply_for: no such theme '$name' under $OMARCHY_PATH/themes" >&2
        return 1
    fi

    current="$home/.local/state/omarchy/current/theme"
    next="$home/.local/state/omarchy/current/.next-theme.$$"
    install -d -m 0755 "$(dirname "$current")" || return 1
    rm -rf "$next"
    install -d -m 0755 "$next" || return 1
    cp -r "$src/." "$next/" 2>/dev/null

    if [[ ! -f "$next/colors.toml" && -f "$next/alacritty.toml" ]] \
        && command -v omarchy-theme-colors-from-alacritty >/dev/null 2>&1; then
        omarchy-theme-colors-from-alacritty "$next" >/dev/null 2>&1 || true
    fi

    if ! chown -R root:root "$next" >/dev/null 2>&1; then
        echo "theme_apply_for: could not chown $next to root:root (fine outside a real root run)" >&2
    fi
    find "$next" -type d -exec chmod 0755 {} + 2>/dev/null
    find "$next" -type f -exec chmod 0644 {} + 2>/dev/null

    rm -rf "$current"
    mv "$next" "$current" || return 1

    tmp="$(mktemp "$(dirname "$current")/.theme.name.XXXXXX")" || return 1
    printf '%s\n' "$name" > "$tmp"
    chown root:root "$tmp" >/dev/null 2>&1 || true
    chmod 0644 "$tmp"
    mv -f "$tmp" "$(dirname "$current")/theme.name"
}

# theme_reload_if_live ACCOUNT — best-effort live reload, the same IPC
# omarchy-theme-set's own shell_ipc uses (omacom/omarchy@v4.0.2
# bin/omarchy-theme-set: `timeout 2 omarchy-shell shell applyTheme
# "$colors_payload" "$shell_payload"`, base64 of the just-written
# colors.toml/shell.toml), run as ACCOUNT (via runuser) so it reaches
# that account's own shell IPC socket, not root's. Only attempted when
# ACCOUNT actually has a live session (a running Hyprland process owned
# by ACCOUNT); otherwise this is a no-op with one line explaining why —
# the theme is already applied on disk either way, so a kid who isn't
# logged in right now simply sees it at their next login (no restart
# needed), matching the issue's own "no session restart needed at next
# login; if a session is live, best-effort reload... else skip with a
# line" brief.
theme_reload_if_live() {
    local account="$1" current colors_b64="" shell_b64=""
    if ! pgrep -u "$account" -x Hyprland >/dev/null 2>&1; then
        echo "theme_reload_if_live: no live session for '$account' -- the new theme applies at next login" >&2
        return 0
    fi
    current="$(theme_account_home "$account")/.local/state/omarchy/current/theme"
    [[ -f "$current/colors.toml" ]] && colors_b64="$(base64 -w 0 "$current/colors.toml" 2>/dev/null || true)"
    [[ -f "$current/shell.toml" ]] && shell_b64="$(base64 -w 0 "$current/shell.toml" 2>/dev/null || true)"
    if command -v runuser >/dev/null 2>&1; then
        runuser -l "$account" -c "timeout 2 omarchy-shell shell applyTheme '$colors_b64' '$shell_b64'" >/dev/null 2>&1 \
            || echo "theme_reload_if_live: live reload failed for '$account' -- the theme is applied on disk, they will see it at next login" >&2
    fi
}
