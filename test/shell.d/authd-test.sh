#!/bin/bash
# Tests bin/omarchy-kids-authd and bin/omarchy-kids-parent-auth (R-SEC-1, R-SEC-2).
# Self-contained, runs on macOS or Linux. Skips (exit 0) if this host's
# libcrypt.so.1 isn't loadable, since the daemon can't do anything without it.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUTHD="$DIR/bin/omarchy-kids-authd"
CLIENT="$DIR/bin/omarchy-kids-parent-auth"

if ! python3 -c 'import ctypes; next(l for n in ("libcrypt.so.2","libcrypt.so.1") for l in [__import__("ctypes").CDLL(n)])' >/dev/null 2>&1; then
  echo "SKIP authd-test.sh: libcrypt.so.1 not loadable on this host"
  exit 0
fi

TMP="$(mktemp -d)"
DAEMON_PID=""
# shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
cleanup() {
  [[ -n "$DAEMON_PID" ]] && kill "$DAEMON_PID" >/dev/null 2>&1
  [[ -n "$DAEMON_PID" ]] && wait "$DAEMON_PID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

PARENT="testparent"
# $6$saltsalt$... is a fixed sha512-crypt hash of "secret123" (openssl passwd
# -6 -salt saltsalt secret123). The $6$ format is glibc/libxcrypt-standard,
# so this string verifies the same on any Linux box regardless of how it was
# produced.
SHADOW="$TMP/shadow"
cat > "$SHADOW" <<'EOF'
testparent:$6$saltsalt$4wxWeHqpAHNNJcQMSu6jvr3dQTQoGoqMQhPAP0o5Ygzna6vr4y0u6.EZzboAAqg6dXU4q/OfcYqdrvZixR76r0:19000:0:99999:7:::
EOF
chmod 600 "$SHADOW"
SOCK="$TMP/auth.sock"

fail=0
check() { # got want label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else echo "FAIL $3 (want '$2', got '$1')"; fail=1; fi
}

send() { # candidate -> prints daemon's reply, trimmed
  printf '%s\n' "$1" | python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(5)
s.connect(sys.argv[1]); s.sendall(sys.stdin.buffer.read()); s.shutdown(socket.SHUT_WR)
sys.stdout.write(s.recv(4096).decode(errors="replace").strip())
' "$SOCK"
}

python3 "$AUTHD" --socket "$SOCK" --shadow "$SHADOW" --parent "$PARENT" &
DAEMON_PID=$!
for _ in $(seq 1 50); do [[ -S "$SOCK" ]] && break; sleep 0.1; done
if [[ ! -S "$SOCK" ]]; then
  echo "FAIL authd-test.sh: daemon never created $SOCK"
  exit 1
fi

check "$(send secret123)" "ok" "correct password -> ok"
check "$(send wrongpass)" "no" "wrong password -> no"

LONG="$(python3 -c 'print("a" * 600)')"
check "$(send "$LONG")" "no" "overlong line -> no (and doesn't count as a miss)"

if OMARCHY_KIDS_AUTH_SOCK="$SOCK" bash -c "echo secret123 | '$CLIENT'"; then
  echo "ok   client exits 0 on correct password"
else
  echo "FAIL client exits 0 on correct password"; fail=1
fi
if OMARCHY_KIDS_AUTH_SOCK="$SOCK" bash -c "echo wrongpass | '$CLIENT'"; then
  echo "FAIL client should exit 1 on wrong password"; fail=1
else
  echo "ok   client exits 1 on wrong password"
fi
if OMARCHY_KIDS_AUTH_SOCK="$SOCK" PAM_TYPE=account bash -c "echo secret123 | '$CLIENT'"; then
  echo "FAIL client should exit 1 when PAM_TYPE != auth"; fail=1
else
  echo "ok   client exits 1 when PAM_TYPE=account"
fi

# Two more misses cross the "three wrongs" threshold (one miss already spent
# above); a correct password offered while locked must still come back "no".
send bad1 >/dev/null
send bad2 >/dev/null
check "$(send secret123)" "no" "correct password while locked (3 misses) -> no"

kill "$DAEMON_PID" >/dev/null 2>&1
wait "$DAEMON_PID" 2>/dev/null
DAEMON_PID=""

exit $fail
