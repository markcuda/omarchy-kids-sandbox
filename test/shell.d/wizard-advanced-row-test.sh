#!/bin/bash
# Regression for issue #172: R-WIZ-3, I-5, I-6.
# The Advanced app row keeps the selectable item compact while the existing
# checklist card body shows the complete value without changing the CSV.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BAND=6-8
ALLOWLIST_IDS='gcompris,tuxpaint,ktuberling,blinken,supertux,supertuxkart,klettres,kanagram'
MARKER="$(mktemp)"
trap 'rm -f "$MARKER"' EXIT

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
    quote) printf 'Kid "Q" \\ \$(touch %s)' "$MARKER" ;;
  esac
}

# shellcheck disable=SC1091
source "$ROOT/lib/wizard-advanced.sh"
# Avoid the pack reader here; the production row and formatter remain real.
adv_default() {
  [[ "$1" == allowlist ]] && printf '%s' "$ALLOWLIST_IDS" || adv_get "$1"
}

row="$(adv_row_line allowlist)"
[[ "$row" == *'8 apps selected'* ]] || { echo 'FAIL app row lost selected count'; exit 1; }
[[ "$row" != *$'\n'* ]] || { echo 'FAIL selectable app row contains display newlines'; exit 1; }
[[ "${#row}" -lt 80 ]] || {
  echo 'FAIL selectable app row remains too wide'
  exit 1
}

body=()
adv_allowlist_body body "$ALLOWLIST_IDS"
[[ "${#body[@]}" == 9 ]] || {
  echo 'FAIL app detail body did not expose one line per selected app'
  exit 1
}
body_text="$(printf '%s\n' "${body[@]}")"
for label in GCompris 'Tux Paint' KTuberling Blinken SuperTux SuperTuxKart KLettres Kanagram; do
  [[ "$body_text" == *"$label"* ]] || { echo "FAIL app detail body lost $label"; exit 1; }
done
[[ "$(adv_get allowlist)" == "$ALLOWLIST_IDS" ]] || {
  echo 'FAIL display formatting changed the underlying allowlist'
  exit 1
}
quoted_body=()
adv_allowlist_body quoted_body 'quote'
printf '%s\n' "${quoted_body[1]}" | grep -Fq 'Kid "Q"' &&
printf '%s\n' "${quoted_body[1]}" | grep -Fq '$(' || {
  echo 'FAIL quoted app label was not preserved as data'
  exit 1
}
[[ ! -s "$MARKER" ]] || { echo 'FAIL app label triggered command substitution'; exit 1; }
printf '%s\n' 'PASS Advanced app detail is readable and preserves CSV selection'
