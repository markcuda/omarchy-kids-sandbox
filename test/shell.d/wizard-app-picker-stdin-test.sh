#!/bin/bash
# Regression for issue #180: R-WIZ-3, R-WIZ-9, I-5, I-6.
# App-list iteration must leave the interactive input channel available to
# Gum and must propagate real confirm errors through both callers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat >"$STUBS/gum" <<'GUM'
#!/bin/bash
case "${1:-}" in
  style) exit 0 ;;
  confirm)
    [[ "${GUM_RC:-0}" == 0 ]] || exit "$GUM_RC"
    [[ -t 0 ]] || exit 1
    exit 0
    ;;
  *) exit 0 ;;
esac
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
export PATH="$STUBS:$PATH"
GUM_RC=0
export GUM_RC

if [[ "${1:-}" == "" ]]; then
  script -q /dev/null bash "$0" --pty >"$TMP/pty.out" 2>&1
  grep -q 'PASS interactive app picker retains Gum stdin' "$TMP/pty.out"
  grep -q 'PASS confirm error propagates through both callers' "$TMP/pty.out"
  printf '%s\n' 'PASS PTY reproduction completed'
  exit 0
fi

extract_apps_pick_walk() {
  awk '
    /^apps_pick_walk\(\) \{/ { inside=1 }
    inside {
      opens=gsub(/\{/, "{")
      closes=gsub(/\}/, "}")
      depth += opens - closes
      print
      if (depth == 0) exit
    }
  ' "$ROOT/bin/omarchy-kids-wizard"
}
eval "$(extract_apps_pick_walk)"
BAND=6-8 DISPLAY_NAME=kid-ben
TOTAL_STEPS=10
pack_field() { printf '%s\n' gcompris tuxpaint; }
app_label_for() { printf '%s' "$2"; }

# The actual renderer owns the confirm call; the Gum fixture refuses a pipe,
# reproducing the process-substitution collision on the old implementation.
# shellcheck disable=SC1091
source "$ROOT/lib/tui.sh"
TUI_C_ACCENT=accent TUI_C_FG=foreground TUI_C_MUTED=muted TUI_C_ERROR=error
TUI_FOOTER_DEFAULT='Enter continue · Esc back · Ctrl+C leave (nothing changes)'
export OMARCHY_KIDS_TUI_PLAIN=1

if [[ "${1:-}" == "--file" ]]; then
  TUI_MODE="file"
  TUI_HAVE_GUM="0"
  TUI_ANSWERS=(yes no)
  TUI_ANSWERS_I=0
  TUI_REPLY=''
  if ! apps_pick_walk 1 1; then
    echo 'FAIL file app picker returned an unexpected error'; exit 1
  fi
  [[ "$TUI_REPLY" == gcompris ]] || {
    echo 'FAIL file answers did not follow app rows'; exit 1
  }
  printf '%s\n' 'PASS file answers remain available to app picker'
  exit 0
fi

TUI_MODE=interactive TUI_HAVE_GUM=1
TUI_REPLY=''
apps_pick_walk 1 1
[[ "$TUI_REPLY" == gcompris,tuxpaint ]] || {
  echo 'FAIL interactive app picker lost selections'; exit 1
}
printf '%s\n' 'PASS interactive app picker retains Gum stdin'

GUM_RC=2
if apps_pick_walk 1 1; then
  echo 'FAIL Gum confirm error was swallowed'; exit 1
fi

GUM_RC=130
if apps_pick_walk 1 1; then
  echo 'FAIL Gum cancellation was swallowed'; exit 1
fi

# Both production callers must preserve their existing selection on a real
# picker error instead of assigning an empty TUI_REPLY.
# shellcheck disable=SC1091
source "$ROOT/lib/wizard-advanced.sh"
# shellcheck disable=SC1091
source "$ROOT/lib/wizard-screens.sh"
apps_pick_walk() { return 2; }
tui_screen_choose() { TUI_REPLY=pick; return 0; }
ALLOWLIST_IDS=gcompris
if screen_apps; then
  echo 'FAIL Simple caller swallowed picker error'; exit 1
fi
[[ "$ALLOWLIST_IDS" == gcompris ]] || { echo 'FAIL Simple caller cleared selection'; exit 1; }
if adv_edit_allowlist 1 1; then
  echo 'FAIL Advanced caller swallowed picker error'; exit 1
fi
[[ "$ALLOWLIST_IDS" == gcompris ]] || { echo 'FAIL Advanced caller cleared selection'; exit 1; }
printf '%s\n' 'PASS confirm error propagates through both callers'
