#!/bin/bash
# Talk to the running test VM over QMP. shot <file.png> | type <text> | key <qcode>... | status | quit
set -euo pipefail
VM="${VM_DIR:-$HOME/vm}"; S="$VM/qmp.sock"
qmp(){ printf '{"execute":"qmp_capabilities"}\n{"execute":%s}\n' "$1" | socat -t 3 - "UNIX-CONNECT:$S" | tail -1; }
case ${1:-} in
  shot) qmp "\"screendump\", \"arguments\": {\"filename\": \"$2\", \"format\": \"png\"}" >/dev/null; echo "$2" ;;
  key) shift; keys=$(printf '{"type":"qcode","data":"%s"},' "$@"); qmp "\"send-key\", \"arguments\": {\"keys\": [${keys%,}]}" >/dev/null ;;
  type) text="$2"; for ((i=0;i<${#text};i++)); do c=${text:i:1}; case $c in
          [a-z0-9]) k=$c ;; [A-Z]) k="shift-${c,,}" ;; ' ') k=spc ;; '-') k=minus ;; '.') k=dot ;; '/') k=slash ;; '_') k="shift-minus" ;; *) k=$c ;; esac
          if [[ $k == shift-* ]]; then qmp "\"send-key\", \"arguments\": {\"keys\": [{\"type\":\"qcode\",\"data\":\"shift\"},{\"type\":\"qcode\",\"data\":\"${k#shift-}\"}]}" >/dev/null
          else qmp "\"send-key\", \"arguments\": {\"keys\": [{\"type\":\"qcode\",\"data\":\"$k\"}]}" >/dev/null; fi; sleep 0.05; done ;;
  enter) qmp "\"send-key\", \"arguments\": {\"keys\": [{\"type\":\"qcode\",\"data\":\"ret\"}]}" >/dev/null ;;
  status) qmp '"query-status"' ;;
  quit) qmp '"quit"' >/dev/null ;;
  *) echo "usage: vm-qmp.sh shot <png> | type <text> | enter | key <qcode>... | status | quit"; exit 2 ;;
esac
