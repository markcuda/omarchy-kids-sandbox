#!/bin/bash
# Regression for issue #172: R-WIZ-3, I-5, I-6.
# The Advanced app row must keep the complete value readable without changing
# the CSV used by the picker or the row's selectable value.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BAND=6-8
ALLOWLIST_IDS='gcompris,tuxpaint,ktuberling,blinken,supertux,supertuxkart,klettres,kanagram'

app_label_for() {
  case "$2" in
    gcompris) printf 'GCompris' ;;
    tuxpaint) printf 'Tux Paint' ;;
    ktuberling) printf 'KTuberling' ;;
    blinken) printf 'Blinken' ;;
    supertux) printf 'SuperTux' ;;
    supertuxkart) printf 'SuperTuxKart' ;;
    klettres) printf 'KLettres' ;;
    kanagram) printf 'Kanagram' ;;
  esac
}

# shellcheck disable=SC1091
source "$ROOT/lib/wizard-advanced.sh"
# Avoid the pack reader here; the production row and formatter remain real.
adv_default() {
  [[ "$1" == allowlist ]] && printf '%s' "$ALLOWLIST_IDS" || adv_get "$1"
}

row="$(adv_row_line allowlist)"
[[ "$row" == *$'\n'* ]] || { echo 'FAIL long app row was not wrapped'; exit 1; }
[[ "$(printf '%s\n' "$row" | wc -l | tr -d ' ')" == 3 ]] || {
  echo 'FAIL app row did not produce three readable lines'
  exit 1
}
for label in GCompris 'Tux Paint' KTuberling Blinken SuperTux SuperTuxKart KLettres Kanagram; do
  [[ "$row" == *"$label"* ]] || { echo "FAIL app row lost $label"; exit 1; }
done
[[ "$(adv_get allowlist)" == "$ALLOWLIST_IDS" ]] || {
  echo 'FAIL display formatting changed the underlying allowlist'
  exit 1
}
printf '%s\n' 'PASS Advanced app row wraps complete labels and preserves CSV selection'
