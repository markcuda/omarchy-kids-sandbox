#!/bin/bash
# Regression for issue #182: R-WIZ-9, I-5, I-6.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat >"$STUBS/gum" <<'GUM'
#!/bin/bash
printf 'argv:' >>"${GUM_LOG:?}"
printf ' <%q>' "$@" >>"${GUM_LOG:?}"
printf '\n' >>"${GUM_LOG:?}"
if [[ "${1:-}" == confirm ]]; then
  # Gum's documented Prompt default is "Are you sure?" when no prompt arg is
  # supplied. Model that behavior so the regression catches omission of -- "".
  if (( $# == 5 )); then printf '%s\n' 'Are you sure?' | tee -a "$GUM_LOG"; fi
  exit "${GUM_RC:-0}"
fi
exit 0
GUM
cat >"$STUBS/clear" <<'CLEAR'
#!/bin/bash
:
CLEAR
cat >"$STUBS/tput" <<'TPUT'
#!/bin/bash
[[ "${1:-}" == cols ]] && printf '%s\n' 80
TPUT
chmod +x "$STUBS"/*
export PATH="$STUBS:$PATH" GUM_LOG="$TMP/gum.log" GUM_RC=0

# shellcheck disable=SC1091
source "$ROOT/lib/tui.sh"
TUI_MODE=interactive TUI_HAVE_GUM=1
TUI_C_ACCENT=accent TUI_C_FG=foreground TUI_C_MUTED=muted TUI_C_ERROR=error
TUI_FOOTER_DEFAULT='Enter continue · Esc back · Ctrl+C leave (nothing changes)'
# shellcheck disable=SC2034 # passed by name to tui_screen_confirm
body=('Include GCompris in Ben starter apps?')
unset OMARCHY_KIDS_TUI_PLAIN
tui_screen_confirm 'GCompris' 9 15 0 '' body 'Apply "q" \\, ' 'Decline,'
[[ $? == 0 && $TUI_REPLY == yes ]]
printf -v affirm_q '%q' 'Apply "q" \\, '
printf -v decline_q '%q' 'Decline,'
grep -Fq "argv: <confirm> <--affirmative> <$affirm_q> <--negative> <$decline_q> <--> <''>" "$GUM_LOG"
if grep -Fq 'Are you sure?' "$GUM_LOG"; then exit 1; fi
printf '%s\n' 'PASS card confirm supplies an explicit empty Gum prompt'

: >"$GUM_LOG"
export OMARCHY_KIDS_TUI_PLAIN=1
prompt='Question "q" \\, '
tui_screen_confirm "$prompt" 1 1 0 '' body 'Apply' 'Decline'
[[ $? == 0 && $TUI_REPLY == yes ]]
printf -v prompt_q '%q' "$prompt"
grep -Fq "argv: <confirm> <--affirmative> <Apply> <--negative> <Decline> <--> <$prompt_q>" "$GUM_LOG"
printf '%s\n' 'PASS non-card confirm keeps its prompt'

GUM_RC=1
unset OMARCHY_KIDS_TUI_PLAIN
set +e
tui_screen_confirm 'Decline' 1 1 0 '' body 'Yes' 'No'
rc=$?
set -e
[[ $rc == 1 && $TUI_REPLY == no ]]
printf '%s\n' 'PASS confirm preserves Gum negative status'

TUI_MODE=file TUI_HAVE_GUM=0 TUI_ANSWERS=(yes) TUI_ANSWERS_I=0
tui_screen_confirm 'File question' 1 1 0 '' body 'Yes' 'No'
[[ $? == 0 && $TUI_REPLY == yes ]]
printf '%s\n' 'PASS file confirm preserves its answer-file behavior'

GUM_RC=130
unset OMARCHY_KIDS_TUI_PLAIN
TUI_MODE=interactive TUI_HAVE_GUM=1
set +e
tui_screen_confirm 'Cancel' 1 1 0 '' body 'Yes' 'No'
rc=$?
set -e
[[ $rc == 130 ]]
printf '%s\n' 'PASS card confirm preserves cancellation status'
