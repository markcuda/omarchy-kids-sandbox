# shellcheck shell=bash
# lib/sock.sh -- one Unix-socket request/response client for every daemon
# this repo speaks to (bin/omarchy-kids-authd, bin/omarchy-kids-wifid),
# replacing three copies that had drifted. socat where it exists, python3
# otherwise, and a hard failure when neither does -- never a silent
# success, since every caller reads "no reply" as "refused".

# kids_sock_request SOCKET PAYLOAD [TIMEOUT] -- writes PAYLOAD, shuts the
# write side down, prints whatever comes back. Returns non-zero when
# there is no way to speak the protocol at all.
kids_sock_request() {
  local sock="$1" payload="$2" timeout="${3:-5}"
  if command -v socat >/dev/null 2>&1; then
    printf '%s' "$payload" | socat -T"$timeout" - "UNIX-CONNECT:$sock" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$payload" | python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(float(sys.argv[2]))
try:
    s.connect(sys.argv[1])
    s.sendall(sys.stdin.buffer.read())
    s.shutdown(socket.SHUT_WR)
    data = b""
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
    sys.stdout.buffer.write(data)
except OSError:
    pass
' "$sock" "$timeout" 2>/dev/null
  else
    return 1
  fi
}
