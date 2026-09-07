#!/bin/bash
# Talk to the running test VM over QMP. shot <file.png> | type | key <qcode>... | status | quit
set -euo pipefail
VM="${VM_DIR:-$HOME/vm}"
S="$VM/qmp.sock"
QMP_SEQ=0
qmp() {
  local response parsed cap_id command_id
  QMP_SEQ=$((QMP_SEQ + 1))
  cap_id="omarchy-kids-${QMP_SEQ}-capabilities"
  command_id="omarchy-kids-${QMP_SEQ}-command"
  if ! response="$(printf '{"execute":"qmp_capabilities","id":"%s"}\n{"execute":%s,"id":"%s"}\n' "$cap_id" "$1" "$command_id" | socat -t 3 - "UNIX-CONNECT:$S")"; then
    echo "QMP transport failed" >&2
    return 1
  fi
  if ! parsed="$(printf '%s\n' "$response" | jq -c -e -s --arg cap "$cap_id" --arg command "$command_id" '
    ([.[] | select(type == "object" and (.id == $cap or .id == $command))]) as $matches |
    ([$matches[] | select(.id == $cap)] | length) as $caps |
    ([$matches[] | select(.id == $command)] | length) as $commands |
    if $caps == 1 and $commands == 1 and all($matches[]; has("return") and (has("error") | not))
    then [$matches[] | select(.id == $command)][0]
    else error("missing, duplicate, malformed, or failed QMP response")
    end')"; then
    echo "QMP command failed" >&2
    return 1
  fi
  printf '%s\n' "$parsed"
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
      case ${text:i:1} in
        [a-z0-9A-Z]) ;;
        ' ' | '-' | '.' | '/' | '_' | ':') ;;
        *) echo "unsupported type character: ${text:i:1}" >&2; exit 2 ;;
      esac
    done
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
