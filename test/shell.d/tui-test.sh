#!/bin/bash
# Tests lib/tui.sh and bin/omarchy-kids-tui-demo (issue #18: SPEC.md
# R-WIZ-9, Appendix A).
#
# Every scenario runs in its own subshell (lib/tui.sh sourced fresh each
# time) so one test's TUI_MODE/TUI_ANSWERS_I/etc. never leak into the
# next. gum is a fake on a stub PATH that logs every invocation to
# $GUM_LOG and, for `style`, prints back the text after the literal `--`
# separator -- the same convention lib/tui.sh's real gum calls use -- so
# rendering can be checked without a real terminal.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TUI_LIB="$ROOT/lib/tui.sh"
DEMO="$ROOT/bin/omarchy-kids-tui-demo"

pass() { echo "PASS  $*"; }
fail() {
    echo "FAIL  $*"
    rc=1
}
rc=0

check_contains() { # haystack needle label
    if [[ "$1" == *"$2"* ]]; then pass "$3"; else fail "$3 (want to find '$2' in: $1)"; fi
}
check_not_contains() { # haystack needle label
    if [[ "$1" != *"$2"* ]]; then pass "$3"; else fail "$3 (did not want '$2' in: $1)"; fi
}
check_eq() { # got want label
    if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want '$2', got '$1')"; fi
}

TMP="$(mktemp -d)"
# shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

STUBS="$TMP/stubs"
mkdir -p "$STUBS"
GUM_LOG="$TMP/gum.log"
cat >"$STUBS/gum" <<'EOF'
#!/bin/bash
# Fake gum: records every call (argv, space-joined) to $GUM_LOG, and for
# `style` prints back everything after the literal "--" separator -- one
# line per text argument, same as real gum style with lib/tui.sh's calls.
LOG="${GUM_LOG:?GUM_LOG must be set}"
printf '%s\n' "$*" >>"$LOG"
case "${1:-}" in
    style)
        shift
        seen=0
        for a in "$@"; do
            if [[ $seen == 1 ]]; then printf '%s\n' "$a"; fi
            [[ "$a" == "--" ]] && seen=1
        done
        ;;
    *)
        exit "${GUM_EXIT:-0}"
        ;;
esac
EOF
chmod +x "$STUBS/gum"
export PATH="$STUBS:$PATH"
export GUM_LOG

answers_file() { # writes $1's remaining args, one per line, returns its path
    local f="$TMP/answers.$RANDOM"
    printf '%s\n' "$@" >"$f"
    printf '%s' "$f"
}

# --- non-tty, no answers file: tui_init fails closed with exit 2 -----------

out="$(
    {
        unset OMARCHY_KIDS_TUI_ANSWERS
        # shellcheck source=/dev/null
        source "$TUI_LIB"
        tui_init
        echo "tui_init rc=$?"
    } 2>&1
)" </dev/null
check_contains "$out" "tui_init rc=2" "tui_init: no terminal and no answers file exits 2"
check_contains "$out" "nothing to answer prompts with" "tui_init: exit-2 message explains why"

# --- answers file drives tui_init into file mode ----------------------------

f="$(answers_file begin)"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    echo "rc=$? mode=$TUI_MODE"
)" </dev/null
check_contains "$out" "rc=0 mode=file" "tui_init: an answers file selects file mode and returns 0"

# --- Omy header appears only when asked -------------------------------------

: >"$GUM_LOG"
out="$(
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init 2>/dev/null  # no answers file here; the test overrides TUI_MODE below
    TUI_MODE="file"
    tui_header "Some Screen" 2 5 0 "should never print"
)" </dev/null
check_not_contains "$out" "Omy" "tui_header show_omy=0: no Omy glyph"
check_not_contains "$out" "should never print" "tui_header show_omy=0: no Omy line"
check_contains "$out" "step 2 of 5" "tui_header: step counter always renders"
check_contains "$out" "Some Screen" "tui_header: title always renders"

: >"$GUM_LOG"
out="$(
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init 2>/dev/null  # no answers file here; the test overrides TUI_MODE below
    TUI_MODE="file"
    tui_header "Welcome" 1 3 1 "Hi, I'm Omy."
)" </dev/null
check_contains "$out" "Omy" "tui_header show_omy=1: Omy glyph renders"
check_contains "$out" "Hi, I'm Omy." "tui_header show_omy=1: Omy line renders"
check_contains "$(cat "$GUM_LOG")" "style" "tui_header: rendering goes through the real gum style call"

# --- tui_screen_choose renders title, body, choices, and the reasons -------

f="$(answers_file garden)"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    web_choices=(
        "garden|Only sites you choose|A short list you can grow."
        "filtered|Filtered open web|Adult content blocked."
    )
    tui_screen_choose "What can K see?" 2 3 0 "" web_choices "garden"
    echo "rc=$? reply=$TUI_REPLY"
)" </dev/null
check_contains "$out" "What can K see?" "tui_screen_choose: title renders"
check_contains "$out" "Only sites you choose" "tui_screen_choose: choice label renders"
check_contains "$out" "A short list you can grow." "tui_screen_choose: choice reason renders"
check_contains "$out" "Filtered open web" "tui_screen_choose: second choice renders"
check_contains "$out" "rc=0 reply=garden" "tui_screen_choose: the matching answer resolves to its value"

# a bare 1-based number also resolves
f="$(answers_file 2)"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    web_choices=("garden|Only sites you choose|reason one" "filtered|Filtered open web|reason two")
    tui_screen_choose "T" 1 1 0 "" web_choices
    echo "rc=$? reply=$TUI_REPLY"
)" </dev/null
check_contains "$out" "rc=0 reply=filtered" "tui_screen_choose: a number-key answer resolves by position"

# --- Esc goes back one screen, exit 1, nothing consumed beyond that line ---

f="$(answers_file "@esc" garden)"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    web_choices=("garden|Only sites you choose|r" "filtered|Filtered open web|r")
    tui_screen_choose "T" 1 1 0 "" web_choices
    echo "rc=$?"
)" </dev/null
check_contains "$out" "rc=1" "tui_screen_choose: @esc returns 1 (Esc = back)"

# --- Ctrl+C asks to leave; declining redraws and re-reads the next answer --

f="$(answers_file "@ctrlc" no garden)"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    web_choices=("garden|Only sites you choose|r" "filtered|Filtered open web|r")
    tui_screen_choose "T" 1 1 0 "" web_choices
    echo "rc=$? reply=$TUI_REPLY"
)" </dev/null
check_contains "$out" "rc=0 reply=garden" "tui_screen_choose: @ctrlc + no stays, next line answers the screen"

f="$(answers_file "@ctrlc" yes)"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    web_choices=("garden|Only sites you choose|r" "filtered|Filtered open web|r")
    tui_screen_choose "T" 1 1 0 "" web_choices
    echo "rc=$?"
)" </dev/null
check_contains "$out" "rc=130" "tui_screen_choose: @ctrlc + yes leaves, exit 130"

# The same Esc/Ctrl+C contract on tui_screen_input.
f="$(answers_file "@esc")"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    tui_screen_input "Name" 1 1 0 "" text "hint" ""
    echo "rc=$?"
)" </dev/null
check_contains "$out" "rc=1" "tui_screen_input: @esc returns 1"

f="$(answers_file "@ctrlc" yes)"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    tui_screen_input "Name" 1 1 0 "" text "hint" ""
    echo "rc=$?"
)" </dev/null
check_contains "$out" "rc=130" "tui_screen_input: @ctrlc + yes leaves, exit 130"

# --- tui_screen_input validation retries instead of accepting a bad value --

cat >"$TMP/lower_only.sh" <<'EOF'
lower_only() {
    if [[ "$1" =~ ^[a-z]+$ ]]; then return 0; fi
    echo "letters only"
    return 1
}
EOF
f="$(answers_file "BAD1" "ok")"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    # shellcheck source=/dev/null
    source "$TMP/lower_only.sh"
    tui_init
    tui_screen_input "Name" 1 1 0 "" text "" lower_only
    echo "rc=$? reply=$TUI_REPLY"
)" </dev/null
check_contains "$out" "letters only" "tui_screen_input: a failed validator's message is shown"
check_contains "$out" "rc=0 reply=ok" "tui_screen_input: retries until the validator accepts"

# --- tui_screen_confirm: yes/no, and the Esc/No-are-the-same-outcome rule --

f="$(answers_file yes)"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    body=("Apply this?")
    tui_screen_confirm "Summary" 1 1 0 "" body "Apply" "Change something"
    echo "rc=$? reply=$TUI_REPLY"
)" </dev/null
check_contains "$out" "Apply this?" "tui_screen_confirm: body renders"
check_contains "$out" "rc=0 reply=yes" "tui_screen_confirm: yes returns 0"

f="$(answers_file "@esc")"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    body=("Apply this?")
    tui_screen_confirm "Summary" 1 1 0 "" body
    echo "rc=$? reply=$TUI_REPLY"
)" </dev/null
check_contains "$out" "rc=1 reply=no" "tui_screen_confirm: @esc is the same outcome as declining"

f="$(answers_file "@ctrlc")"
out="$(
    OMARCHY_KIDS_TUI_ANSWERS="$f"
    export OMARCHY_KIDS_TUI_ANSWERS
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    body=("Apply this?")
    tui_screen_confirm "Summary" 1 1 0 "" body
    echo "rc=$?"
)" </dev/null
check_contains "$out" "rc=130" "tui_screen_confirm: @ctrlc leaves directly, exit 130"

# --- tui_screen_summary: a pure table render, no prompt ---------------------

out="$(
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init 2>/dev/null  # no answers file here; the test overrides TUI_MODE below
    TUI_MODE="file"
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    rows=("Account|kid-ada" "Level|1 — one thing at a time")
    tui_screen_summary "Summary" 1 1 0 "" rows
)" </dev/null
check_contains "$out" "Account" "tui_screen_summary: row label renders"
check_contains "$out" "kid-ada" "tui_screen_summary: row value renders"
check_contains "$out" "Level" "tui_screen_summary: second row renders"

# --- tui_progress: done marks, current marker, and the tip -----------------

out="$(
    # shellcheck source=/dev/null
    source "$TUI_LIB"
    tui_init 2>/dev/null  # no answers file here; the test overrides TUI_MODE below
    TUI_MODE="file"
    # shellcheck disable=SC2034 # read by lib/tui.sh via _tui_array_copy (by name)
    steps=("Create account" "Install packages" "Apply settings")
    tui_progress steps 1 "Grab a coffee."
)" </dev/null
check_contains "$out" "✓" "tui_progress: a done step gets a check mark"
check_contains "$out" "▸" "tui_progress: the current step gets its marker"
check_contains "$out" "Create account" "tui_progress: step labels render"
check_contains "$out" "Grab a coffee." "tui_progress: the tip renders"

# --- the demo binary runs end to end from an answers file -------------------

f="$(answers_file begin garden kid)"
out="$(OMARCHY_KIDS_TUI_ANSWERS="$f" "$DEMO" </dev/null)"
demo_rc=$?
check_eq "$demo_rc" "0" "omarchy-kids-tui-demo: a full run exits 0"
check_contains "$out" "web=garden done=kid" "omarchy-kids-tui-demo: answers flow through all three screens"

f="$(answers_file begin "@ctrlc" yes)"
OMARCHY_KIDS_TUI_ANSWERS="$f" "$DEMO" >/dev/null </dev/null
check_eq "$?" "130" "omarchy-kids-tui-demo: Ctrl+C + confirming leave exits 130"

"$DEMO" --help >/dev/null </dev/null
check_eq "$?" "0" "omarchy-kids-tui-demo: --help exits 0"

# --- non-tty with no answers file exits 2 (checked once more through the ---
# --- real command, not just the sourced library) ----------------------------

unset OMARCHY_KIDS_TUI_ANSWERS
"$DEMO" </dev/null >/dev/null 2>"$TMP/err"
check_eq "$?" "2" "omarchy-kids-tui-demo: no tty and no answers file exits 2"
check_contains "$(cat "$TMP/err")" "nothing to answer prompts with" "omarchy-kids-tui-demo: exit-2 message reaches stderr"

echo "tui-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
