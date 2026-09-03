# shellcheck shell=bash
# lib/tui.sh — one screen renderer over gum for the parent wizard
# (SPEC.md R-WIZ-9, Appendix A; issue #18: "screens as data, one renderer").
#
# A screen is data, not code: a title, an optional Omy line (the
# first-person voice — spec v1.1 says Omy speaks only on Welcome and Done;
# every other screen passes an empty Omy line and gets the plain header),
# body lines, and, for tui_screen_choose, a list of "value|label|reason"
# choices. This file is the one renderer over that data — callers never
# call gum directly.
#
# Every prompt follows the installer's status contract, vendored here as
# knowledge (not code) from upstream's install/provisioning/setup-form.sh:
#
#   0    the screen has an answer; $TUI_REPLY holds it
#   1    Esc — go back one screen, nothing written
#   130  Ctrl+C — the human confirmed leaving; exit 130, nothing written
#
# Two ways to answer a prompt:
#   - a real terminal: gum asks, a human answers (or hits Esc/Ctrl+C, which
#     gum itself reports as exit 1/130 — see setup-form.sh's own comment on
#     why: Ctrl+C arrives as a byte in raw mode, never a SIGINT)
#   - OMARCHY_KIDS_TUI_ANSWERS=<file>: one answer per line, consumed in
#     order starting at tui_init. Two reserved lines stand in for keys a
#     file can't press: `@esc` (Esc) and `@ctrlc` (Ctrl+C — for
#     tui_screen_choose/tui_screen_input this consumes one more line,
#     `yes` or `no`, for the leave confirmation). This is how tests and
#     the acceptance harness drive the whole wizard with no one at the
#     keyboard. Every screen is still rendered to stdout in this mode, the
#     same as an interactive run, so a recorded session reads the same way.
#
# Not meant to be executed directly; source it from a command:
#   source "$DIR/lib/tui.sh"

# lib/theme.sh's theme_color, for tui_init's colors (below). Sourced here
# rather than left to each caller, matching how every existing caller of
# this file only ever sources lib/tui.sh itself (bin/omarchy-kids-tui-demo).
# shellcheck source=./theme.sh
source "$(dirname "${BASH_SOURCE[0]}")/theme.sh"

TUI_ANS_ESC="@esc"
TUI_ANS_CTRLC="@ctrlc"

TUI_FOOTER_DEFAULT="Enter continue · Esc back · Ctrl+C leave (nothing changes)"
# shellcheck disable=SC2034 # for callers' first screen (no Esc target yet), not used here
TUI_FOOTER_FIRST="Enter continue · Ctrl+C leave (nothing changes)"

TUI_MODE=""      # "interactive" or "file", set by tui_init
TUI_HAVE_GUM=0
TUI_REPLY=""     # the answer from the last tui_screen_* call
TUI_NEXT_ANSWER="" # scratch: set by _tui_next_answer, read right after
declare -a TUI_ANSWERS=()
TUI_ANSWERS_I=0

# Colors tui_init resolves via lib/theme.sh's theme_color, in the hex form
# gum's --foreground and --border-foreground already accept. theme_color's
# own fallback palette (lib/theme.sh) covers a machine with no theme read
# yet — its "accent" fallback (#8fb8ff) is a close cousin of upstream's own
# prompt accent (setup-form.sh's --prompt.foreground="#845DF9"), close
# enough that nothing here hardcodes a second fallback of its own.
TUI_C_ACCENT=""
TUI_C_FG=""
TUI_C_MUTED=""
TUI_C_ERROR=""

# tui_init — call once before any tui_screen_* call. Resolves colors and
# picks how prompts get answered (see the file header). Returns 2 (does
# not exit — that's the caller's call) when neither an answers file nor a
# terminal is available.
tui_init() {
    if command -v gum >/dev/null 2>&1; then TUI_HAVE_GUM=1; else TUI_HAVE_GUM=0; fi

    TUI_C_ACCENT="$(theme_color accent)"
    TUI_C_FG="$(theme_color foreground)"
    TUI_C_MUTED="$(theme_color muted)"
    TUI_C_ERROR="$(theme_color error)"

    if [[ -n "${OMARCHY_KIDS_TUI_ANSWERS:-}" ]]; then
        if [[ ! -r "$OMARCHY_KIDS_TUI_ANSWERS" ]]; then
            echo "tui: OMARCHY_KIDS_TUI_ANSWERS is set but not readable: $OMARCHY_KIDS_TUI_ANSWERS" >&2
            return 2
        fi
        TUI_ANSWERS=()
        local line
        while IFS= read -r line || [[ -n "$line" ]]; do
            TUI_ANSWERS+=("$line")
        done <"$OMARCHY_KIDS_TUI_ANSWERS"
        TUI_ANSWERS_I=0
        TUI_MODE="file"
    elif [[ -t 0 ]]; then
        TUI_MODE="interactive"
    else
        echo "tui: no terminal to ask, and OMARCHY_KIDS_TUI_ANSWERS is not set — nothing to answer prompts with" >&2
        return 2
    fi
    return 0
}

# _tui_next_answer — sets TUI_NEXT_ANSWER to the next answers-file line
# and advances the cursor, or prints a message and returns 2 if the file
# ran out. Every file-mode read in this library goes through this one
# place. Deliberately NOT called as `x="$(_tui_next_answer)"`: that would
# run it in a subshell, and the TUI_ANSWERS_I bump would be lost the
# moment the subshell exited, replaying the same line forever. Call it
# plain, then read TUI_NEXT_ANSWER.
_tui_next_answer() {
    if ((TUI_ANSWERS_I >= ${#TUI_ANSWERS[@]})); then
        echo "tui: ${OMARCHY_KIDS_TUI_ANSWERS:-<answers file>} ran out of lines, but a screen still needs one" >&2
        return 2
    fi
    TUI_NEXT_ANSWER="${TUI_ANSWERS[TUI_ANSWERS_I]}"
    TUI_ANSWERS_I=$((TUI_ANSWERS_I + 1))
}

# _tui_array_copy DEST SRC_ARRAYNAME — copies the array named SRC_ARRAYNAME
# into the local array variable DEST. Every tui_screen_* function below
# takes its choices/rows/steps array "by name" (a caller passes the
# array's variable name as a string) and calls this to read it. Written
# with eval instead of a nameref (`local -n`, bash 4.3+) because
# test/all also has to run under plain macOS bash (3.2) — this is the
# same indirect-array idiom pre-4.3 bash has always used for "pass an
# array by name".
_tui_array_copy() {
    local __tui_dest="$1" __tui_src="$2"
    # shellcheck disable=SC1087 # $__tui_src[@] is the array-name being
    # built for eval, not an expansion shellcheck can see through
    eval "$__tui_dest=(\"\${$__tui_src[@]+\"\${$__tui_src[@]}\"}\")"
}

# _tui_style FLAGS... -- TEXT... — the one place gum style is called.
# Without gum (a dev machine that hasn't installed it yet — PKGBUILD
# depends on it, so a real install always has it) this drops straight to
# plain text so nothing here ever hard-depends on gum being present.
_tui_style() {
    local -a flags=() text=()
    local sep=0 a
    for a in "$@"; do
        if ((!sep)) && [[ "$a" == "--" ]]; then
            sep=1
            continue
        fi
        if ((sep)); then text+=("$a"); else flags+=("$a"); fi
    done
    if ((TUI_HAVE_GUM)); then
        gum style "${flags[@]+"${flags[@]}"}" -- "${text[@]+"${text[@]}"}"
    else
        printf '%s\n' "${text[@]+"${text[@]}"}"
    fi
}

_tui_footer() {
    _tui_style --foreground "$TUI_C_MUTED" -- "$1"
}

# tui_header TITLE STEP TOTAL SHOW_OMY [OMY_LINE]
# The Omy glyph and voice line only render when SHOW_OMY is 1 — spec v1.1:
# Omy speaks on Welcome and Done, every other screen is plain. The bordered
# "Kids Mode / step n of N / title" box under it renders on every screen.
tui_header() {
    local title="$1" step="$2" total="$3" show_omy="$4" omy_line="${5:-}"

    if [[ "$show_omy" == 1 ]]; then
        _tui_style --foreground "$TUI_C_ACCENT" --bold -- "🦉 Omy"
        if [[ -n "$omy_line" ]]; then
            local -a f=(--italic)
            [[ -n "$TUI_C_FG" ]] && f+=(--foreground "$TUI_C_FG")
            _tui_style "${f[@]}" -- "$omy_line"
        fi
    fi

    _tui_style --border rounded --padding "0 1" \
        --foreground "$TUI_C_ACCENT" --border-foreground "$TUI_C_ACCENT" -- \
        "Kids Mode" "step ${step} of ${total}" "$title"
}

# _tui_confirm_leave — the Ctrl+C contract itself: "Leave setup? Nothing
# has been changed yet." Returns 0 (leave) or 1 (stay, redraw the screen
# that was interrupted). A second Ctrl+C right here also means leave —
# nobody gets trapped in a confirmation loop by mashing the same key.
_tui_confirm_leave() {
    local msg="Leave setup? Nothing has been changed yet."
    if [[ "$TUI_MODE" == file ]]; then
        local ans
        _tui_next_answer || { echo "tui: answers file ran out during the leave confirmation" >&2; exit 2; }
        ans="$TUI_NEXT_ANSWER"
        case "$ans" in
            yes | y | Yes | Y) return 0 ;;
            *) return 1 ;;
        esac
    elif ((TUI_HAVE_GUM)); then
        gum confirm -- "$msg"
        local rc=$?
        [[ $rc == 0 || $rc == 130 ]] && return 0 || return 1
    else
        local a
        read -r -p "$msg [y/N] " a
        [[ "$a" =~ ^[Yy] ]] && return 0 || return 1
    fi
}

# tui_screen_choose TITLE STEP TOTAL SHOW_OMY OMY_LINE CHOICES_ARRAYNAME \
#                    [DEFAULT_VALUE] [FOOTER]
# CHOICES_ARRAYNAME holds "value|label|reason" strings — one choice per
# screen's worth of options, each with its one-line reason (R-WIZ-3). An
# answer may be the value, the label, the whole rendered line, or a plain
# 1-based number (the "number keys" the footer advertises).
tui_screen_choose() {
    local title="$1" step="$2" total="$3" show_omy="$4" omy_line="$5"
    local -a _tui_choices
    _tui_array_copy _tui_choices "$6"
    local default_value="${7:-}"
    local footer="${8:-$TUI_FOOTER_DEFAULT}"

    local -a values=() labels=() display=()
    local c rest label reason i=0
    for c in "${_tui_choices[@]+"${_tui_choices[@]}"}"; do
        local value="${c%%|*}"
        rest="${c#*|}"
        label="${rest%%|*}"
        if [[ "$rest" == "$label" ]]; then reason=""; else reason="${rest#*|}"; fi
        i=$((i + 1))
        values+=("$value")
        labels+=("$label")
        if [[ -n "$reason" ]]; then
            display+=("$(printf '%d) %s — %s' "$i" "$label" "$reason")")
        else
            display+=("$(printf '%d) %s' "$i" "$label")")
        fi
    done

    local default_display=""
    for i in "${!values[@]}"; do
        [[ "${values[i]}" == "$default_value" ]] && default_display="${display[i]}"
    done

    while true; do
        tui_header "$title" "$step" "$total" "$show_omy" "$omy_line"
        local d
        for d in "${display[@]+"${display[@]}"}"; do _tui_style -- "$d"; done
        _tui_footer "$footer"

        local chosen
        if [[ "$TUI_MODE" == file ]]; then
            _tui_next_answer || return 2
            chosen="$TUI_NEXT_ANSWER"
        elif ((TUI_HAVE_GUM)); then
            local -a gflags=(--header "$title")
            [[ -n "$default_display" ]] && gflags+=(--selected "$default_display")
            chosen="$(gum choose "${gflags[@]}" -- "${display[@]+"${display[@]}"}")"
            case $? in
                1) return 1 ;;
                130)
                    if _tui_confirm_leave; then return 130; else continue; fi
                    ;;
            esac
        else
            for d in "${display[@]+"${display[@]}"}"; do echo "$d"; done
            read -r -p "> " chosen
        fi

        if [[ "$chosen" == "$TUI_ANS_ESC" ]]; then return 1; fi
        if [[ "$chosen" == "$TUI_ANS_CTRLC" ]]; then
            if _tui_confirm_leave; then return 130; else continue; fi
        fi

        # Resolve to a value: exact value/label/rendered-line match, or a
        # bare 1-based number.
        local match="" j
        for j in "${!values[@]}"; do
            if [[ "$chosen" == "${values[j]}" || "$chosen" == "${labels[j]}" || "$chosen" == "${display[j]}" ]]; then
                match="${values[j]}"
                break
            fi
        done
        if [[ -z "$match" && "$chosen" =~ ^[0-9]+$ ]]; then
            local idx=$((chosen - 1))
            if ((idx >= 0 && idx < ${#values[@]})); then match="${values[idx]}"; fi
        fi

        if [[ -z "$match" ]]; then
            echo "tui: '$chosen' does not match any choice on '$title'" >&2
            return 2
        fi

        TUI_REPLY="$match"
        return 0
    done
}

# tui_screen_input TITLE STEP TOTAL SHOW_OMY OMY_LINE KIND PLACEHOLDER \
#                   [VALIDATOR] [FOOTER]
# KIND is "text" or "password". VALIDATOR, if given, is a function name
# called as `VALIDATOR "$candidate"`: it should print nothing and return 0
# for a valid answer, or print a one-line reason and return non-zero to
# have the screen redraw and ask again (spec's per-field validation, e.g.
# the name and password screens).
tui_screen_input() {
    local title="$1" step="$2" total="$3" show_omy="$4" omy_line="$5"
    local kind="$6" placeholder="${7:-}" validator="${8:-}"
    local footer="${9:-$TUI_FOOTER_DEFAULT}"

    while true; do
        tui_header "$title" "$step" "$total" "$show_omy" "$omy_line"
        [[ -n "$placeholder" ]] && _tui_style --foreground "$TUI_C_MUTED" -- "$placeholder"
        _tui_footer "$footer"

        local ans
        if [[ "$TUI_MODE" == file ]]; then
            _tui_next_answer || return 2
            ans="$TUI_NEXT_ANSWER"
        elif ((TUI_HAVE_GUM)); then
            local -a gflags=(--placeholder "$placeholder")
            [[ "$kind" == password ]] && gflags+=(--password)
            ans="$(gum input "${gflags[@]}")"
            case $? in
                1) return 1 ;;
                130)
                    if _tui_confirm_leave; then return 130; else continue; fi
                    ;;
            esac
        else
            if [[ "$kind" == password ]]; then
                read -r -s -p "> " ans
                echo
            else
                read -r -p "> " ans
            fi
        fi

        if [[ "$ans" == "$TUI_ANS_ESC" ]]; then return 1; fi
        if [[ "$ans" == "$TUI_ANS_CTRLC" ]]; then
            if _tui_confirm_leave; then return 130; else continue; fi
        fi

        if [[ -n "$validator" ]]; then
            local err
            if ! err="$("$validator" "$ans")"; then
                _tui_style --foreground "$TUI_C_ERROR" -- "${err:-That is not valid. Try again.}"
                continue
            fi
        fi

        TUI_REPLY="$ans"
        return 0
    done
}

# tui_screen_confirm TITLE STEP TOTAL SHOW_OMY OMY_LINE BODY_ARRAYNAME \
#                     [AFFIRM] [DECLINE] [FOOTER]
# A plain yes/no screen (the summary's "Apply this?" and similar). $TUI_REPLY
# is "yes" or "no" on success (0); a decline is also reported as exit 1
# (Esc and "No" are the same outcome for a confirm screen: don't proceed).
tui_screen_confirm() {
    local title="$1" step="$2" total="$3" show_omy="$4" omy_line="$5"
    local -a _tui_body
    _tui_array_copy _tui_body "$6"
    local affirm="${7:-Yes}" decline="${8:-No}"
    local footer="${9:-$TUI_FOOTER_DEFAULT}"

    tui_header "$title" "$step" "$total" "$show_omy" "$omy_line"
    local b
    for b in "${_tui_body[@]+"${_tui_body[@]}"}"; do _tui_style -- "$b"; done
    _tui_footer "$footer"

    local ans
    if [[ "$TUI_MODE" == file ]]; then
        _tui_next_answer || return 2
        ans="$TUI_NEXT_ANSWER"
        case "$ans" in
            "$TUI_ANS_CTRLC")
                TUI_REPLY=""
                return 130
                ;;
            "$TUI_ANS_ESC" | no | n | No | N)
                TUI_REPLY="no"
                return 1
                ;;
            yes | y | Yes | Y)
                TUI_REPLY="yes"
                return 0
                ;;
            *)
                echo "tui: '$ans' is not yes/no for '$title'" >&2
                return 2
                ;;
        esac
    elif ((TUI_HAVE_GUM)); then
        gum confirm --affirmative "$affirm" --negative "$decline" -- "$title"
        local rc=$?
        if [[ $rc == 0 ]]; then
            TUI_REPLY="yes"
        else
            TUI_REPLY="no"
        fi
        return $rc
    else
        read -r -p "$title [$affirm/$decline] " ans
        if [[ "$ans" =~ ^[Yy] ]]; then
            TUI_REPLY="yes"
            return 0
        else
            # shellcheck disable=SC2034 # TUI_REPLY is read by the caller, not here
            TUI_REPLY="no"
            return 1
        fi
    fi
}

# tui_screen_summary TITLE STEP TOTAL SHOW_OMY OMY_LINE ROWS_ARRAYNAME [FOOTER]
# A pure display screen (spec A13): ROWS_ARRAYNAME holds "label|value"
# strings, rendered as an aligned two-column table. Pair it with
# tui_screen_choose for the Apply / Change something buttons — this
# function has no prompt of its own.
tui_screen_summary() {
    local title="$1" step="$2" total="$3" show_omy="$4" omy_line="$5"
    local -a _tui_rows
    _tui_array_copy _tui_rows "$6"
    local footer="${7:-$TUI_FOOTER_DEFAULT}"

    tui_header "$title" "$step" "$total" "$show_omy" "$omy_line"

    local row label width=0
    for row in "${_tui_rows[@]+"${_tui_rows[@]}"}"; do
        label="${row%%|*}"
        ((${#label} > width)) && width=${#label}
    done
    local value
    for row in "${_tui_rows[@]+"${_tui_rows[@]}"}"; do
        label="${row%%|*}"
        value="${row#*|}"
        _tui_style -- "$(printf '%-*s  %s' "$width" "$label" "$value")"
    done

    _tui_footer "$footer"
}

# tui_progress STEPS_ARRAYNAME CURRENT_INDEX [TIP]
# Display-only (spec R-WIZ-5): one line per step (✓ done, ▸ current,
# · pending), a bar, and an optional tip. CURRENT_INDEX is 0-based;
# pass an index equal to the array length to mark every step done.
tui_progress() {
    local -a _tui_steps
    _tui_array_copy _tui_steps "$1"
    local current="$2" tip="${3:-}"
    local total=${#_tui_steps[@]}

    local i mark line
    for ((i = 0; i < total; i++)); do
        if ((i < current)); then
            mark="✓"
        elif ((i == current)); then
            mark="▸"
        else
            mark="·"
        fi
        line="  $mark ${_tui_steps[i]}"
        if ((i == current)); then
            _tui_style --foreground "$TUI_C_ACCENT" --bold -- "$line"
        elif ((i < current)); then
            _tui_style --foreground "$TUI_C_MUTED" -- "$line"
        else
            _tui_style -- "$line"
        fi
    done

    _tui_progress_bar "$current" "$total"
    [[ -n "$tip" ]] && _tui_style --foreground "$TUI_C_MUTED" --italic -- "Tip: $tip"
}

_tui_progress_bar() {
    local current="$1" total="$2" width=24 filled empty bar rest
    ((total > 0)) || total=1
    filled=$((current * width / total))
    ((filled > width)) && filled=$width
    empty=$((width - filled))
    printf -v bar '%*s' "$filled" ''
    bar="${bar// /█}"
    printf -v rest '%*s' "$empty" ''
    rest="${rest// /░}"
    _tui_style --foreground "$TUI_C_ACCENT" -- "${bar}${rest}"
}
