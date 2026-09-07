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
case "${QMP_RESULT:-ok}" in
  ok) printf '%s\n%s\n%s\n' '{"QMP":{}}' '{"return":{}}' '{"return":{}}' ;;
  error) printf '%s\n' '{"return":{},"error":{"class":"GenericError","desc":"bad key"}}' ;;
  malformed) printf '%s\n' '{"unexpected":true}' ;;
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
grep -Fq '"data":"shift"' <<<"$request"
grep -Fq '"data":"semicolon"' <<<"$request"
if grep -Fq '"data":":"' <<<"$request"; then
  echo "FAIL colon was sent as a raw qcode" >&2
  exit 1
fi
[[ $(bash "$HELPER" status) == '{"return":{}}' ]]

: >"$QMP_REQUESTS"
if printf '@' | bash "$HELPER" type >/dev/null 2>&1; then
  echo "FAIL unsupported input succeeded" >&2
  exit 1
fi
[[ ! -s $QMP_REQUESTS ]]

for result in error malformed transport; do
  : >"$QMP_REQUESTS"
  if printf ':' | QMP_RESULT="$result" bash "$HELPER" type >/dev/null 2>&1; then
    echo "FAIL QMP $result succeeded" >&2
    exit 1
  fi
done

echo "PASS vm-qmp colon, invalid-input, QMP-error, malformed, and transport checks"
