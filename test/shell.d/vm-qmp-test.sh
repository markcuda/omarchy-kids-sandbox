#!/bin/bash
# Regression for #178: QMP colon typing and response errors.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="${QMP_HELPER:-$ROOT/scripts/vm-qmp.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat >"$STUBS/socat" <<'SOCAT'
#!/bin/bash
cat >>"${QMP_REQUESTS:?QMP_REQUESTS must be set}"
call=$((($(wc -l <"$QMP_REQUESTS") - 1) / 2 + 1))
case "${QMP_RESULT:-ok}" in
  ok) printf '%s\n%s\n%s\n%s\n' '{"QMP":{}}' '{"event":"RESET"}' "{\"return\":{},\"id\":\"omarchy-kids-${call}-capabilities\"}" "{\"return\":{},\"id\":\"omarchy-kids-${call}-command\"}" ;;
  error) printf '%s\n%s\n%s\n' "{\"return\":{},\"id\":\"omarchy-kids-${call}-capabilities\"}" "{\"return\":{},\"error\":{\"class\":\"GenericError\"},\"id\":\"omarchy-kids-${call}-command\"}" '{"event":"RESET"}' ;;
  malformed) printf '%s\n%s\n' "{\"return\":{},\"id\":\"omarchy-kids-${call}-capabilities\"}" "{\"return\": {oops},\"id\":\"omarchy-kids-${call}-command\"}" ;;
  misleading) printf '%s\n%s\n' "{\"return\":{},\"id\":\"omarchy-kids-${call}-capabilities\"}" "{\"message\":\"return\",\"id\":\"omarchy-kids-${call}-command\"}" ;;
  duplicate) printf '%s\n%s\n%s\n' "{\"return\":{},\"id\":\"omarchy-kids-${call}-capabilities\"}" "{\"return\":{},\"id\":\"omarchy-kids-${call}-capabilities\"}" "{\"return\":{},\"id\":\"omarchy-kids-${call}-command\"}" ;;
  mismatch) printf '%s\n%s\n' "{\"return\":{},\"id\":\"omarchy-kids-${call}-capabilities\"}" "{\"return\":{},\"id\":\"other-command\"}" ;;
  transport) exit 7 ;;
  *) exit 8 ;;
esac
SOCAT
chmod +x "$STUBS/socat"
export PATH="$STUBS:$PATH"
export VM_DIR="$TMP/vm" QMP_REQUESTS="$TMP/requests"
mkdir -p "$VM_DIR"

printf '21:00' | bash "$HELPER" type
request="$(cat "$QMP_REQUESTS")"
[[ $(jq -s -r '[.[] | select(.execute == "send-key") | .arguments.keys | map(.data) | join("+")] | join("|")' <<<"$request") == '2|1|shift+semicolon|0|0' ]]
if grep -Fq '"data":":"' <<<"$request"; then
  echo "FAIL colon was sent as a raw qcode" >&2
  exit 1
fi
: >"$QMP_REQUESTS"
[[ $(bash "$HELPER" status) == '{"return":{},"id":"omarchy-kids-1-command"}' ]]

: >"$QMP_REQUESTS"
if printf '2@' | bash "$HELPER" type >/dev/null 2>&1; then
  echo "FAIL unsupported input succeeded" >&2
  exit 1
fi
[[ ! -s $QMP_REQUESTS ]]

for result in error malformed misleading duplicate mismatch transport; do
  : >"$QMP_REQUESTS"
  if printf ':' | QMP_RESULT="$result" bash "$HELPER" type >/dev/null 2>&1; then
    echo "FAIL QMP $result succeeded" >&2
    exit 1
  fi
done

echo "PASS vm-qmp colon, invalid-input, QMP-error, malformed, and transport checks"
