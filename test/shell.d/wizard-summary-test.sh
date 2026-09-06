#!/bin/bash
# Regression for issue #167: R-WIZ-3, I-5, I-6.
# Owns the blocking Ready? chooser and checks its current card, not historical
# stdout, after the chooser clears the prior summary.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
DISPLAY_BUFFER="$TMP/current-card"
export DISPLAY_BUFFER
cat >"$STUBS/gum" <<'GUM'
#!/bin/bash
case "${1:-}" in
  style)
    shift
    seen=0
    : >>"${DISPLAY_BUFFER:?DISPLAY_BUFFER must be set}"
    for arg in "$@"; do
      if ((seen)); then
        printf '%s\n' "$arg" >>"$DISPLAY_BUFFER"
        printf '%s\n' "$arg"
      fi
      [[ "$arg" == -- ]] && seen=1
    done
    ;;
  choose) printf '%s\n' "${GUM_OUTPUT:-apply}" ;;
  *) exit 0 ;;
esac
GUM
cat >"$STUBS/clear" <<'CLEAR'
#!/bin/bash
: >"${DISPLAY_BUFFER:?DISPLAY_BUFFER must be set}"
CLEAR
cat >"$STUBS/tput" <<'TPUT'
#!/bin/bash
[[ ${1:-} == cols ]] && echo 80
TPUT
chmod +x "$STUBS"/*
export PATH="$STUBS:$PATH"

# shellcheck disable=SC2034 # globals are read indirectly by the sourced production screen/renderer
setup_globals() {
  TUI_MODE="$1"
  TUI_HAVE_GUM="$2"
  TUI_C_ACCENT=accent TUI_C_FG=foreground TUI_C_MUTED=muted TUI_C_ERROR=error
  TUI_FOOTER_DEFAULT='Enter continue · Esc back · Ctrl+C leave (nothing changes)'
  TUI_REPLY='' TUI_PRESET_ERROR=''
  DISPLAY_NAME=kid-test ACCOUNT=kid-test AVATAR=fox BAND=3-5 MODE=simple
  WEB_MODE=garden BUDGET_MIN=30 BUDGET_MIN_WEEKEND=60 LIGHTS_OUT=20:00
  LIGHTS_OUT_WEEKEND=20:00 WIFI_MODE=parent LEVEL=1 ALLOWLIST_IDS=browser
  NO_PASSWORD=1 KID_PASSWORD='' TOTAL_STEPS=15
  DNS_MODE='' SITES='' MENU_MODE='' THEME='' HISTORY_VISIBLE=''
}

# Source the real renderer and production screen. Runtime dependencies used by
# screen_summary are owned here rather than replaced wholesale.
# shellcheck disable=SC1091
source "$ROOT/lib/tui.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/wizard-screens.sh"
band_field() { [[ $2 == label ]] && printf '6-8' || printf 'A short setup.'; }
friendly_allowlist() { printf 'Browser'; }
mark_if_changed() { printf '%s' "$2"; }
# shellcheck disable=SC2329 # invoked indirectly by screen_summary
adv_summary_extra_rows() { :; }
# shellcheck disable=SC2329 # invoked indirectly by screen_summary
screen_advanced_checklist() { return 0; }

setup_globals interactive 1
GUM_OUTPUT=apply
export GUM_OUTPUT
: >"$DISPLAY_BUFFER"
out="$TMP/card.out"
screen_summary >"$out" 2>&1
status=$?
[[ $status == 0 ]] || {
  echo "FAIL card summary returned $status"
  exit 1
}
current_card="$(cat "$DISPLAY_BUFFER")"
grep -q 'Screen time.*30 minutes a day' <<<"$current_card" || {
  echo 'FAIL current Ready card lost the formatted summary'
  exit 1
}
if grep -q '|' <<<"$current_card"; then
  echo 'FAIL current Ready card contains raw row separators'
  exit 1
fi
printf '%s\n' 'PASS Ready chooser current card retains formatted summary body'

setup_globals file 0
TUI_ANSWERS=(change @esc)
# shellcheck disable=SC2034 # consumed by the renderer globals
TUI_ANSWERS_I=0
# shellcheck disable=SC2329,SC2034 # invoked indirectly by screen_summary
screen_advanced_checklist() {
  BUDGET_MIN=45
  return 0
}
# shellcheck disable=SC2329,SC2034 # invoked indirectly by screen_summary
adv_summary_extra_rows() {
  local name="$1"
  eval "$name+=(\"Custom setting|Changed\")"
}
out="$TMP/change.out"
screen_summary >"$out" 2>&1
status=$?
[[ $status == 1 ]] || {
  echo "FAIL Change then Esc returned $status"
  exit 1
}
grep -q 'Screen time.*45 minutes a day' "$out" || {
  echo 'FAIL customized summary was not redrawn'
  exit 1
}
grep -q 'Custom setting.*Changed' "$out" || {
  echo 'FAIL customized extra row was not redrawn'
  exit 1
}
printf '%s\n' 'PASS Change loop redraws customized settings and does not apply'

setup_globals file 0
# shellcheck disable=SC2034 # consumed by the renderer globals
TUI_ANSWERS=(@ctrlc yes)
# shellcheck disable=SC2034 # consumed by the renderer globals
TUI_ANSWERS_I=0
out="$TMP/ctrlc.out"
screen_summary >"$out" 2>&1
status=$?
[[ $status == 130 ]] || {
  echo "FAIL Ctrl+C then Leave returned $status"
  exit 1
}
printf '%s\n' 'PASS Ctrl+C leave exits summary without applying'
