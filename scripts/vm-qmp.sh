#!/bin/bash
# Talk to the running test VM over QMP. shot <file.png> | type | key <qcode>... | status | quit
set -euo pipefail
VM="${VM_DIR:-$HOME/vm}"
S="$VM/qmp.sock"
qmp() {
  local response last
  if ! response="$(printf '{"execute":"qmp_capabilities"}\n{"execute":%s}\n' "$1" | socat -t 3 - "UNIX-CONNECT:$S")"; then
    echo "QMP transport failed" >&2
    return 1
  fi
  last="${response##*$'\n'}"
  last="${last//$'\r'/}"
  if [[ -z $last || $last != *'"return"'* || $last == *'"error"'* ]]; then
    echo "QMP command failed: $last" >&2
    return 1
  fi
  printf '%s\n' "$last"
}
case ${1:-} in
  shot)
    qmp "\"screendump\", \"arguments\": {\"filename\": \"$2\", \"format\": \"png\"}" >/dev/null
    echo "$2"
    ;;
  key)
    shift
    keys=$(printf '{"type":"qcode","data":"%s"},' "$@")
    qmp "\"send-key\", \"arguments\": {\"keys\": [${keys%,}]}" >/dev/null
    ;;
  type)
    (($# == 1)) || {
      echo "type reads text from stdin" >&2
      exit 2
    }
    text="$(cat)"
    for ((i = 0; i < ${#text}; i++)); do
      c=${text:i:1}
      case $c in
        [a-z0-9]) k=$c ;; [A-Z]) k="shift-${c,,}" ;; ' ') k='spc' ;; '-') k='minus' ;; '.') k='dot' ;; '/') k='slash' ;; '_') k="shift-minus" ;; ':') k="shift-semicolon" ;; *) echo "unsupported type character: $c" >&2; exit 2 ;; esac
      if [[ $k == shift-* ]]; then
        qmp "\"send-key\", \"arguments\": {\"keys\": [{\"type\":\"qcode\",\"data\":\"shift\"},{\"type\":\"qcode\",\"data\":\"${k#shift-}\"}]}" >/dev/null
      else qmp "\"send-key\", \"arguments\": {\"keys\": [{\"type\":\"qcode\",\"data\":\"$k\"}]}" >/dev/null; fi
      sleep 0.05
    done
    ;;
  enter) qmp "\"send-key\", \"arguments\": {\"keys\": [{\"type\":\"qcode\",\"data\":\"ret\"}]}" >/dev/null ;;
  status) qmp '"query-status"' ;;
  quit) qmp '"quit"' >/dev/null ;;
  *)
    echo "usage: vm-qmp.sh shot <png> | type (reads stdin) | enter | key <qcode>... | status | quit"
    exit 2
    ;;
esac
