#!/bin/bash
# Tests R-WIZ-1/R-WIZ-9 name backtracking: only the editable name is restored.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
GUM_LOG="$TMP/gum.log"
export GUM_LOG
cat >"$STUBS/gum" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${GUM_LOG:?}"
case "$1" in
  input) printf '%s\n' "${GUM_INPUT_OUTPUT:?}" ;;
  choose) printf '%s\n' "${GUM_INPUT_OUTPUT:?}" ;;
  style) : ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$STUBS/gum"
cat >"$STUBS/omarchy-kids-conf" <<'EOF'
#!/bin/bash
[[ "$1" == slug ]] || exit 1
printf 'kid-%s\n' "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
EOF
chmod +x "$STUBS/omarchy-kids-conf"

export PATH="$STUBS:$PATH"
export TUI_HAVE_GUM=1 TUI_MODE=interactive TUI_C_ACCENT=blue
export TUI_FOOTER_DEFAULT=back
export CONF_BIN=omarchy-kids-conf
export TOTAL_STEPS=15
export SHARE="$ROOT/share"
validate_kid_name() { [[ "$1" =~ ^[A-Za-z]+$ ]]; }
source "$ROOT/lib/tui.sh"
source "$ROOT/lib/wizard-screens.sh"
tui_init

export GUM_INPUT_OUTPUT=Test
DISPLAY_NAME=""
screen_name
[[ "$DISPLAY_NAME" == Test && "$ACCOUNT" == kid-test ]] || exit 1
grep -Fq -- 'input --placeholder  --prompt.foreground ' "$GUM_LOG" || exit 1
! grep -Fq -- '--value' "$GUM_LOG" || exit 1

: >"$GUM_LOG"
export GUM_INPUT_OUTPUT=@esc
screen_face
face_rc=$?
[[ "$face_rc" == 1 ]] || exit 1

export GUM_INPUT_OUTPUT=Dot
screen_name
[[ "$DISPLAY_NAME" == Dot && "$ACCOUNT" == kid-dot ]] || exit 1
grep -Fq -- '--value Test' "$GUM_LOG" || exit 1

export GUM_INPUT_OUTPUT=fox
screen_face
[[ "$DISPLAY_NAME" == Dot && "$ACCOUNT" == kid-dot && "$AVATAR" == fox ]] || exit 1

: >"$GUM_LOG"
export GUM_INPUT_OUTPUT=secret
tui_screen_input Password 1 1 0 "" password "" "" back secret
! grep -Fq -- '--value secret' "$GUM_LOG" || exit 1

printf '%s\n' 'wizard name back: initial value, editable slug, and password non-prefill passed'
