#!/bin/bash
# Regression for issue #176: R-WIZ-2, R-WIZ-3, R-WIZ-9, I-5, I-6.
# Advanced number/time editors show their current value without changing the
# shared password/name input contract or answers-file behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUBS="$TMP/stubs"
RENDER_LOG="$TMP/render.log"
INPUT_LOG="$TMP/input.log"
mkdir -p "$STUBS"
export RENDER_LOG
export INPUT_LOG
cat >"$STUBS/gum" <<'GUM'
#!/bin/bash
printf '%s\n' "$@" >>"${RENDER_LOG:?}"
case "${1:-}" in
  input)
    printf '%s\n' "$@" >"${INPUT_LOG:?}"
    if [[ "${GUM_RC:-0}" != 0 ]]; then exit "$GUM_RC"; fi
    printf '%s' "${GUM_OUTPUT:?}"
    ;;
  style) : ;;
esac
GUM
chmod +x "$STUBS/gum"
export PATH="$STUBS:$PATH"
export OMARCHY_KIDS_TUI_PLAIN=1

# shellcheck disable=SC1091
source "$ROOT/lib/tui.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/wizard-advanced.sh"
TUI_MODE=interactive TUI_HAVE_GUM=1
TUI_C_ACCENT=accent TUI_C_FG=foreground TUI_C_MUTED=muted TUI_C_ERROR=error
TUI_FOOTER_DEFAULT='Enter continue · Esc back · Ctrl+C leave (nothing changes)'
BAND=6-8 BUDGET_MIN=60 LIGHTS_OUT=19:30 BUDGET_MIN_WEEKEND=60 LIGHTS_OUT_WEEKEND=20:00
validate_budget_minutes() { [[ "$1" =~ ^[0-9]+$ && "$1" -ge 1 && "$1" -le 1440 ]]; }
validate_lights_out() { [[ "$1" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; }

: >"$RENDER_LOG"
export GUM_OUTPUT
GUM_RC=0
export GUM_RC
GUM_OUTPUT=60
adv_edit_number budget_min_weekend "Weekend minutes" 13 15
awk 'prev == "--value" { found = ($0 == "60") } { prev = $0 } END { exit !found }' "$INPUT_LOG" || {
  echo 'FAIL current minutes did not reach Gum input'; exit 1;
}
grep -q 'Current value: 60' "$RENDER_LOG" || { echo 'FAIL current minutes were not rendered'; exit 1; }
[[ "$BUDGET_MIN_WEEKEND" == 60 ]] || { echo 'FAIL unchanged minutes were not retained'; exit 1; }

: >"$RENDER_LOG"
GUM_OUTPUT=20:00
adv_edit_time lights_out_weekend "Weekend bedtime" 13 15
awk 'prev == "--value" { found = ($0 == "20:00") } { prev = $0 } END { exit !found }' "$INPUT_LOG" || {
  echo 'FAIL current bedtime did not reach Gum input'; exit 1;
}
grep -q 'Current value: 20:00' "$RENDER_LOG" || { echo 'FAIL current bedtime was not rendered'; exit 1; }

GUM_OUTPUT=75
adv_edit_number budget_min_weekend "Weekend minutes" 13 15
[[ "$BUDGET_MIN_WEEKEND" == 75 ]] || { echo 'FAIL submitted minutes were not saved'; exit 1; }
GUM_OUTPUT=21:00
adv_edit_time lights_out_weekend "Weekend bedtime" 13 15
[[ "$LIGHTS_OUT_WEEKEND" == 21:00 ]] || { echo 'FAIL submitted bedtime was not saved'; exit 1; }
[[ "$BUDGET_MIN" == 60 && "$LIGHTS_OUT" == 19:30 ]] || {
  echo 'FAIL weekend edits changed weekday values'; exit 1;
}

GUM_OUTPUT=@esc
if adv_edit_number budget_min_weekend "Weekend minutes" 13 15; then
  echo 'FAIL Esc unexpectedly changed minutes'; exit 1
fi
[[ "$BUDGET_MIN_WEEKEND" == 75 ]] || { echo 'FAIL Esc changed minutes'; exit 1; }
if adv_edit_time lights_out_weekend "Weekend bedtime" 13 15; then
  echo 'FAIL time Esc unexpectedly changed bedtime'; exit 1
fi
[[ "$LIGHTS_OUT_WEEKEND" == 21:00 ]] || { echo 'FAIL time Esc changed bedtime'; exit 1; }

GUM_RC=1
GUM_OUTPUT=ignored
if adv_edit_number budget_min_weekend "Weekend minutes" 13 15; then
  echo 'FAIL Gum cancel unexpectedly succeeded for minutes'; exit 1
fi
if adv_edit_time lights_out_weekend "Weekend bedtime" 13 15; then
  echo 'FAIL Gum cancel unexpectedly succeeded for bedtime'; exit 1
fi
GUM_RC=0
[[ "$BUDGET_MIN_WEEKEND" == 75 && "$LIGHTS_OUT_WEEKEND" == 21:00 ]] || {
  echo 'FAIL Gum cancel changed current values'; exit 1
}

: >"$RENDER_LOG"
GUM_OUTPUT=secret
tui_screen_input "Password" 1 1 0 "" password "" "" "" secret
grep -q -- '--password' "$RENDER_LOG" || { echo 'FAIL password input lost password mode'; exit 1; }
if grep -qx -- '--value' "$RENDER_LOG" || grep -q 'Current value: secret' "$RENDER_LOG"; then
  echo 'FAIL password input received non-password initial value'; exit 1
fi

: >"$INPUT_LOG"
GUM_OUTPUT=Ben
tui_screen_input "Name" 1 1 0 "" text "First name" "" ""
if grep -qx -- '--value' "$INPUT_LOG"; then
  echo 'FAIL ordinary text input received an initial value'; exit 1
fi

TUI_MODE="file"
TUI_ANSWERS=(55)
TUI_ANSWERS_I=0
TUI_REPLY=''
tui_screen_input "Minutes" 1 1 0 "" text "A number" validate_budget_minutes
[[ "$TUI_REPLY" == 55 ]] || { echo 'FAIL answers-file input changed behavior'; exit 1; }
TUI_MODE="interactive"

printf '%s\n' 'PASS Advanced numeric/time editors render and seed current values safely'
