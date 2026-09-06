#!/bin/bash
# Regression for issue #174: R-WIZ-2, R-WIZ-3, I-5, I-6.
# The Simple chooser, Advanced checklist, and Ready card use the same
# descriptive desktop-level words while retaining numeric values and markers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BAND=6-8 DISPLAY_NAME=kid-ada ACCOUNT=kid-ada AVATAR=fox MODE=simple
WEB_MODE=garden DNS_MODE=cloudflare-family SITES=''
BUDGET_MIN=60 BUDGET_MIN_WEEKEND=60 LIGHTS_OUT=19:30 LIGHTS_OUT_WEEKEND=20:00
# shellcheck disable=SC2034 # theme is read indirectly by Advanced state helpers
ALLOWLIST_IDS='' WIFI_MODE=parent LEVEL=1 MENU_MODE=trimmed THEME=tokyo-night
HISTORY_VISIBLE=yes NO_PASSWORD=1 TOTAL_STEPS=15 TUI_REPLY=''
TUI_FOOTER_DEFAULT='Enter continue · Esc back · Ctrl+C leave (nothing changes)'

band_field() {
  case "$2" in
    level) printf '1' ;;
    budget_min) printf '60' ;;
    budget_min_weekend) printf '60' ;;
    lights_out) printf '19:30' ;;
    lights_out_weekend) printf '20:00' ;;
    label) printf '6-8' ;;
    blurb) printf 'A short setup.' ;;
    *) printf '%s' "$1" ;;
  esac
}
app_label_for() { printf '%s' "$2"; }
friendly_web_mode() { printf '%s' "$1"; }
friendly_wifi_mode() { printf '%s' "$1"; }

# shellcheck disable=SC1091
source "$ROOT/lib/wizard-advanced.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/wizard-screens.sh"

adv_default() {
  case "$1" in
    level) printf '1' ;;
    allowlist) printf '' ;;
    *) adv_get "$1" ;;
  esac
}
adv_summary_extra_rows() { :; }

captured_choices=()
tui_screen_choose() {
  local array_name="$6"
  # shellcheck disable=SC1087 # array name is the production nameref idiom
  eval "captured_choices=(\"\${$array_name[@]}\")"
  if [[ "$1" == 'Ready?' ]]; then
    TUI_REPLY=apply
  else
    TUI_REPLY="${LEVEL_REPLY:-1}"
  fi
  return 0
}
tui_screen_summary() {
  local array_name="$6"
  # shellcheck disable=SC1087 # array name is the production nameref idiom
  eval "captured_summary=(\"\${$array_name[@]}\")"
  return 0
}

for LEVEL_REPLY in 1 2 3; do
  screen_level
  [[ "${captured_choices[LEVEL_REPLY-1]}" == "$LEVEL_REPLY|$(friendly_desktop_level "$LEVEL_REPLY")|"* ]] || {
    echo "FAIL Simple level $LEVEL_REPLY label"; exit 1;
  }
done

LEVEL=2
[[ "$(adv_friendly level 2)" == 'Two things side by side' ]] || {
  echo 'FAIL Advanced level wording'; exit 1
}
row="$(adv_row_line level)"
[[ "$row" == *'now: Two things side by side (changed)'* ]] || {
  echo 'FAIL Advanced changed-level wording'; exit 1
}

captured_summary=()
screen_summary >/dev/null
summary_level=''
for row in "${captured_summary[@]}"; do
  [[ "$row" == Desktop\|* ]] && summary_level="${row#Desktop|}"
done
[[ "$summary_level" == 'Two things side by side (custom)' ]] || {
  echo 'FAIL Ready card level wording or custom marker'; exit 1
}

printf '%s\n' 'PASS issue #174 level wording stays aligned across Simple, Advanced, and Ready'
