#!/bin/bash
# Tests bin/omarchy-kids-wifi, bin/omarchy-kids-wifid, and the picker's
# refusal path (SPEC.md R-WIFI-1..4; issue #26).
#
# Four independent sections, in order:
#   A. bin/omarchy-kids-wifid's request parsing and exact `nmcli` argument
#      vectors, tested by importing the file as a Python module and
#      calling its functions directly (docs/wifi.md explains why this is
#      more direct than driving the real daemon over a socket for this
#      part: faking SO_PEERCRED from a test harness is far more machinery
#      than a fake `nmcli` on $PATH and a monkeypatched run_nmcli). Runs
#      everywhere Python 3 does, including macOS.
#   B. The real daemon over a real socket, authorized by this test
#      process's own real uid (SO_PEERCRED can't be spoofed without
#      root, so the fixture profile is written under this process's own
#      account name). Linux-only (SO_PEERCRED); SKIPs elsewhere.
#   C. bin/omarchy-kids-wifi's own `require_helper` pre-check — refusal
#      for wifi=parent and for no profile at all — against scratch
#      OMARCHY_KIDS_ETC/OMARCHY_KIDS_SHARE trees, no daemon involved.
#   D. bin/omarchy-kids-wifi portal's temporary-allow and systemd-run
#      restore commands, in DRY_RUN=1 (the default) — printed, never
#      executed (AGENTS.md rule 8).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/tree.sh"
WIFID="$DIR/bin/omarchy-kids-wifid"
WIFI="$DIR/bin/omarchy-kids-wifi"
CONF_BIN="$DIR/bin/omarchy-kids-conf"

if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP wifi-test.sh: python3 not found"
  exit 0
fi

fail=0
check() { # got want label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else echo "FAIL $3 (want '$2', got '$1')"; fail=1; fi
}
check_contains() { # haystack needle label
  if [[ "$1" == *"$2"* ]]; then echo "ok   $3"; else echo "FAIL $3 (want to find '$2' in '$1')"; fail=1; fi
}
check_status() { # got_status want_status label
  if [[ "$1" == "$2" ]]; then echo "ok   $3"; else echo "FAIL $3 (want exit $2, got $1)"; fail=1; fi
}

# =====================================================================
# A. omarchy-kids-wifid: request parsing and nmcli argument vectors
# =====================================================================

PYTEST="$(mktemp)"
cat > "$PYTEST" <<'PYEOF'
import importlib.util
import os
import subprocess
import sys
import tempfile
import textwrap
from importlib.machinery import SourceFileLoader

# omarchy-kids-wifid has no .py suffix, so spec_from_file_location can't
# guess a loader from the extension alone -- build one explicitly.
wifid_path = sys.argv[1]
loader = SourceFileLoader("omarchy_kids_wifid", wifid_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
wifid = importlib.util.module_from_spec(spec)
loader.exec_module(wifid)

fail = False


def check(got, want, label):
    global fail
    if got == want:
        print(f"ok   {label}")
    else:
        print(f"FAIL {label} (want {want!r}, got {got!r})")
        fail = True


# --- parse_request -------------------------------------------------------
check(wifid.parse_request(b"LIST\n"), ("LIST", "", ""), "parse_request: LIST")
check(wifid.parse_request(b"STATUS\n"), ("STATUS", "", ""), "parse_request: STATUS")
check(wifid.parse_request(b"JOIN HomeNet\nhunter2\n"), ("JOIN", "HomeNet", "hunter2"),
      "parse_request: JOIN with password")
check(wifid.parse_request(b"JOIN OpenNet\n\n"), ("JOIN", "OpenNet", ""),
      "parse_request: JOIN open network (empty password line)")
check(wifid.parse_request(b"FORGET HomeNet\n"), ("FORGET", "HomeNet", ""), "parse_request: FORGET")
check(wifid.parse_request(b"join homenet\n"), ("JOIN", "homenet", ""),
      "parse_request: command is case-insensitive (upper-cased)")

try:
    wifid.parse_request(b"")
    check("no exception", "Failed", "parse_request: empty request raises Failed")
except wifid.Failed:
    print("ok   parse_request: empty request raises Failed")

# --- kids_connection_name --------------------------------------------------
check(wifid.kids_connection_name("HomeNet"), "kids-HomeNet", "kids_connection_name: prefixes with kids-")

# --- cmd_join builds the exact nmcli argument vectors, in order -----------
calls = []


def fake_run_nmcli(nmcli, args, allow_failure=False):
    calls.append(list(args))
    return ""


wifid.run_nmcli = fake_run_nmcli

calls.clear()
wifid.cmd_join("/usr/bin/nmcli", "HomeNet", "hunter2")
check(calls[0], ["connection", "delete", "--", "kids-HomeNet"],
      "cmd_join: clears any stale kids- profile first")
check(calls[1],
      ["connection", "add", "type", "wifi", "con-name", "kids-HomeNet",
       "autoconnect", "no", "ifname", "*", "ssid", "--", "HomeNet"],
      "cmd_join: builds the profile with autoconnect off, SSID after a -- separator")
check(calls[2],
      ["connection", "modify", "kids-HomeNet",
       "wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", "--", "hunter2"],
      "cmd_join: the password goes on after a -- separator too")
check(calls[3],
      ["connection", "modify", "kids-HomeNet",
       "ipv4.ignore-auto-dns", "yes", "ipv6.ignore-auto-dns", "yes",
       "ipv4.dns", "", "ipv6.dns", ""],
      "cmd_join: forces ignore-auto-dns on both stacks and clears connection DNS (R-WIFI-2)")
check(calls[4], ["connection", "up", "kids-HomeNet"], "cmd_join: brings it up LAST")
check(len(calls), 5, "cmd_join: exactly 5 nmcli calls, no more")
dns_at = calls.index([
    "connection", "modify", "kids-HomeNet",
    "ipv4.ignore-auto-dns", "yes", "ipv6.ignore-auto-dns", "yes",
    "ipv4.dns", "", "ipv6.dns", ""])
up_at = calls.index(["connection", "up", "kids-HomeNet"])
check(dns_at < up_at, True,
      "cmd_join: R-WIFI-2's DNS lockdown is applied BEFORE activation (review §3.11)")

calls.clear()
wifid.cmd_join("/usr/bin/nmcli", "OpenNet", "")
check(calls[1], ["connection", "add", "type", "wifi", "con-name", "kids-OpenNet",
                 "autoconnect", "no", "ifname", "*", "ssid", "--", "OpenNet"],
      "cmd_join: open network (empty password) sets no wifi-sec key at all")
check(len(calls), 4, "cmd_join: open network is one call shorter")

# A failed activation must not leave a half-built profile behind: the kid
# would be connected on the network's own DNS (review §3.11).
def failing_run_nmcli(nmcli, args, allow_failure=False):
    calls.append(list(args))
    if args[:2] == ["connection", "up"] and not allow_failure:
        raise wifid.Failed("activation failed")
    return ""

wifid.run_nmcli = failing_run_nmcli
calls.clear()
try:
    wifid.cmd_join("/usr/bin/nmcli", "HomeNet", "hunter2")
    check("no exception", "Failed", "cmd_join: a failed activation raises")
except wifid.Failed:
    print("ok   cmd_join: a failed activation raises")
check(calls[-1], ["connection", "delete", "--", "kids-HomeNet"],
      "cmd_join: a failed activation deletes the profile instead of leaving it (fail closed)")
wifid.run_nmcli = fake_run_nmcli

# Neither value from the socket can become an nmcli flag (review §3.10).
for bad, label in ((("-x", "hunter2"), "an SSID starting with '-'"),
                   (("A" * 33, "hunter2"), "an SSID longer than 32 bytes"),
                   (("Ok", "p" * 65), "a password longer than 64 bytes"),
                   (("Ok\nJOIN Other", "hunter2"), "an SSID with a newline")):
    try:
        wifid.cmd_join("/usr/bin/nmcli", bad[0], bad[1])
        check("no exception", "Refused", f"cmd_join: refuses {label}")
    except wifid.Refused:
        print(f"ok   cmd_join: refuses {label}")

# --- cmd_forget only ever touches kids-<ssid>, never a bare SSID -----------
calls.clear()
wifid.cmd_forget("/usr/bin/nmcli", "HomeNet")
check(calls, [["connection", "delete", "--", "kids-HomeNet"]],
      "cmd_forget: deletes kids-<ssid> only, never a bare-named connection this daemon didn't create")

# --- cmd_list / cmd_status: fixed, terse argv -------------------------------
calls.clear()
wifid.cmd_list("/usr/bin/nmcli")
check(calls, [["-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE", "device", "wifi", "list"]],
      "cmd_list: terse nmcli argv, fixed field list")

calls.clear()
wifid.cmd_status("/usr/bin/nmcli")
check(calls, [["-t", "-f", "NAME,TYPE,DEVICE,STATE", "connection", "show", "--active"]],
      "cmd_status: terse nmcli argv, fixed field list")

# --- wifi_mode: resolves through the real omarchy-kids-conf shape ----------
# (a fake conf_bin here, not the real binary -- this section is testing
# wifid's own subprocess call and return-value handling, not
# omarchy-kids-conf's precedence logic, which conf-test.sh already owns).
fake_dir = tempfile.mkdtemp()
fake_conf = os.path.join(fake_dir, "fake-conf")
with open(fake_conf, "w") as f:
    f.write(textwrap.dedent("""\
        #!/bin/sh
        case "$2" in
          kid-helper) echo helper ;;
          kid-parent) echo parent ;;
          *) exit 2 ;;
        esac
    """))
os.chmod(fake_conf, 0o755)

check(wifid.wifi_mode("kid-helper", fake_conf), "helper", "wifi_mode: reads 'helper' from omarchy-kids-conf")
check(wifid.wifi_mode("kid-parent", fake_conf), "parent", "wifi_mode: reads 'parent' from omarchy-kids-conf")
check(wifid.wifi_mode("kid-nobody", fake_conf), None, "wifi_mode: no resolvable profile -> None")
check(wifid.wifi_mode("kid-nobody", "/no/such/conf-bin"), None, "wifi_mode: unrunnable conf_bin -> None, not a crash")

sys.exit(1 if fail else 0)
PYEOF

if python3 "$PYTEST" "$WIFID"; then
  :
else
  fail=1
fi
rm -f "$PYTEST"

# =====================================================================
# B. The real daemon over a real socket (Linux only: SO_PEERCRED)
# =====================================================================

if ! python3 -c "import socket, sys; sys.exit(0 if hasattr(socket, 'SO_PEERCRED') else 1)"; then
  echo "SKIP wifi-test.sh section B: SO_PEERCRED not available on this platform (Linux only)"
else
  TMP="$(mktemp -d)"
  DAEMON_PID=""
  # shellcheck disable=SC2329 # invoked via `trap ... EXIT`, not called directly
  cleanup_b() {
    [[ -n "$DAEMON_PID" ]] && kill "$DAEMON_PID" >/dev/null 2>&1
    [[ -n "$DAEMON_PID" ]] && wait "$DAEMON_PID" 2>/dev/null
    rm -rf "$TMP"
  }
  trap cleanup_b EXIT

  ETC="$TMP/etc"
  SHARE="$TMP/share"
  mkdir -p "$ETC/kids" "$SHARE/bands" "$SHARE/packs"
  cp "$DIR/share/bands/bands.toml" "$SHARE/bands/"
  cp "$DIR"/share/packs/*.toml "$SHARE/packs/"

  # SO_PEERCRED reports THIS process's own real uid -- there is no way
  # to make the daemon see any other account without root, so the
  # fixture profile has to live under this test's own account name.
  WHOAMI="$(id -un)"
  cat > "$ETC/kids/$WHOAMI.conf" <<EOF
name=Test
avatar=fox
band=9-12
wifi=helper
EOF

  # Fake nmcli: logs its argv (one call per line, space-joined) and
  # replies with fixed, deterministic output for the two read commands.
  FAKE_NMCLI="$TMP/nmcli"
  ARGV_LOG="$TMP/nmcli-argv.log"
  cat > "$FAKE_NMCLI" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$ARGV_LOG"
case "\$1 \$2 \$3" in
  "-t -f SSID,SIGNAL,SECURITY,IN-USE") echo "SchoolNet:80:WPA2:" ;;
  "-t -f NAME,TYPE,DEVICE,STATE") echo "kids-SchoolNet:802-11-wireless:wlan0:activated" ;;
esac
exit 0
EOF
  chmod +x "$FAKE_NMCLI"

  SOCK="$TMP/wifi.sock"
  export OMARCHY_KIDS_ETC="$ETC" OMARCHY_KIDS_SHARE="$SHARE"
  python3 "$WIFID" --socket "$SOCK" --conf-bin "$CONF_BIN" --nmcli "$FAKE_NMCLI" &
  DAEMON_PID=$!
  for _ in $(seq 1 50); do [[ -S "$SOCK" ]] && break; sleep 0.1; done
  if [[ ! -S "$SOCK" ]]; then
    echo "FAIL wifi-test.sh section B: daemon never created $SOCK"
    fail=1
  else
    # The client's socket path is a build-time constant now, and it
    # resolves omarchy-kids-conf beside itself -- nothing here is an env
    # override (AGENTS.md, "The trust boundary").
    kids_tree "$TMP/tree" "$DIR"
    WIFI="$TMP/tree/bin/omarchy-kids-wifi"
    kids_set_const "$WIFI" SOCK "$SOCK"

    out="$("$WIFI" list)"; st=$?
    check_status "$st" 0 "wifi list: exits 0 for wifi=helper"
    check_contains "$out" "SchoolNet" "wifi list: passes through nmcli's terse output"

    out="$(printf 'hunter2\n' | "$WIFI" join TestNet --password-stdin)"; st=$?
    check_status "$st" 0 "wifi join: exits 0"
    argv_log="$(cat "$ARGV_LOG")"
    check_contains "$argv_log" "connection add type wifi con-name kids-TestNet autoconnect no" \
      "wifi join: end-to-end add argv reaches nmcli via the daemon"
    check_contains "$argv_log" "connection modify kids-TestNet ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes" \
      "wifi join: end-to-end modify argv forces ignore-auto-dns"
    check_contains "$argv_log" "connection up kids-TestNet" \
      "wifi join: end-to-end activation happens after the DNS lockdown"

    : > "$ARGV_LOG"
    out="$("$WIFI" forget TestNet)"; st=$?
    check_status "$st" 0 "wifi forget: exits 0"
    check "$(cat "$ARGV_LOG")" "connection delete -- kids-TestNet" \
      "wifi forget: end-to-end argv only ever deletes kids-<ssid>"

    out="$("$WIFI" status)"; st=$?
    check_status "$st" 0 "wifi status: exits 0"
    check_contains "$out" "kids-SchoolNet" "wifi status: passes through nmcli's terse output"

    # The daemon's own refusal (SO_PEERCRED-based), bypassing this
    # script's own require_helper pre-check entirely -- talk to the
    # socket directly so a wifi=parent profile is refused server-side,
    # not just client-side.
    "$CONF_BIN" set "$WHOAMI" wifi parent >/dev/null
    reply="$(printf 'LIST\n' | python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(5)
s.connect(sys.argv[1]); s.sendall(sys.stdin.buffer.read()); s.shutdown(socket.SHUT_WR)
sys.stdout.write(s.recv(4096).decode(errors="replace"))
' "$SOCK")"
    check_contains "$reply" "REFUSED" "wifid: refuses LIST server-side once the profile is wifi=parent (not just the client's own pre-check)"
    "$CONF_BIN" set "$WHOAMI" wifi helper >/dev/null
  fi

  kill "$DAEMON_PID" >/dev/null 2>&1
  wait "$DAEMON_PID" 2>/dev/null
  DAEMON_PID=""
  trap - EXIT
  cleanup_b
fi

# =====================================================================
# C. omarchy-kids-wifi's own require_helper pre-check (no daemon)
# =====================================================================

TMP_C="$(mktemp -d)"
cleanup_c() { rm -rf "$TMP_C"; }
trap cleanup_c EXIT

ETC_C="$TMP_C/etc"
SHARE_C="$TMP_C/share"
mkdir -p "$ETC_C/kids" "$SHARE_C/bands" "$SHARE_C/packs"
cp "$DIR/share/bands/bands.toml" "$SHARE_C/bands/"
cp "$DIR"/share/packs/*.toml "$SHARE_C/packs/"

cat > "$ETC_C/kids/kid-helper.conf" <<'EOF'
name=Helper
avatar=fox
band=9-12
wifi=helper
EOF
cat > "$ETC_C/kids/kid-parent.conf" <<'EOF'
name=Parent-mode
avatar=owl
band=6-8
EOF

# The account comes from `id -un` and the socket from a constant, so the
# scratch copy + an `id` stub replace what used to be two env vars.
STUBS_C="$TMP_C/stubs"
mkdir -p "$STUBS_C"
kids_id_stub "$STUBS_C" kid-helper "$(id -u)"
kids_tree "$TMP_C/tree" "$DIR"
WIFI_C="$TMP_C/tree/bin/omarchy-kids-wifi"
kids_set_const "$WIFI_C" SOCK "$TMP_C/no-such.sock"

run_wifi_c() { # ACCOUNT SUBCOMMAND... -> combined output on stdout; exit status is the command's
  local account="$1"; shift
  PATH="$STUBS_C:$PATH" KIDS_TEST_ACCOUNT="$account" \
  OMARCHY_KIDS_ETC="$ETC_C" OMARCHY_KIDS_SHARE="$SHARE_C" \
    "$WIFI_C" "$@" 2>&1
}

out="$(run_wifi_c kid-parent list)"; st=$?
check_status "$st" 3 "wifi list: refuses (exit 3) for wifi=parent"
check_contains "$out" "grown-up" "wifi list: refusal message is a plain sentence (I-6)"

out="$(run_wifi_c kid-parent join TestNet)"; st=$?
check_status "$st" 3 "wifi join: refuses (exit 3) for wifi=parent"
out="$(run_wifi_c kid-parent status)"; st=$?
check_status "$st" 3 "wifi status: refuses (exit 3) for wifi=parent"
out="$(run_wifi_c kid-parent forget TestNet)"; st=$?
check_status "$st" 3 "wifi forget: refuses (exit 3) for wifi=parent"

out="$(run_wifi_c kid-nobody list)"; st=$?
check_status "$st" 1 "wifi list: exits 1 (not 3) when there's no profile at all"

out="$(run_wifi_c kid-helper list)"; st=$?
check_status "$st" 1 "wifi list: wifi=helper passes require_helper, then fails (exit 1) with no daemon running"
check_contains "$out" "no reply" "wifi list: 'no reply' message when the socket doesn't exist"

# picker: no Quickshell on PATH in this test environment either way, so
# only the refusal path (before it would try to exec quickshell at all)
# is checked here -- the real overlay is VM-only (docs/wifi.md).
out="$(run_wifi_c kid-parent picker)"; st=$?
check_status "$st" 3 "wifi picker: refuses (exit 3) for wifi=parent"
check_contains "$out" "grown-up" "wifi picker: falls back to a stderr message when Quickshell isn't available"

trap - EXIT
cleanup_c

# `omarchy-kids-wifi portal` used to be tested here. The command is gone
# (see this file's header): a kid could never have run it.
out="$("$WIFI" portal 2>&1)"; st=$?
check_status "$st" 2 "portal: the command a kid could never run is gone (I-6)"

# =====================================================================
# review S8: the Wi-Fi password is never echoed back to the caller
# =====================================================================
#
# `raise Failed(f"nmcli {' '.join(args)}: {exc}")` put the whole argv --
# including "password <secret>" on the JOIN path -- into a message the
# daemon sends straight back to the client. Unit-level, so it runs on
# every platform, including where SO_PEERCRED does not exist.

leak_out="$(python3 - "$DIR/bin/omarchy-kids-wifid" <<'PYEOF'
import importlib.machinery, importlib.util, sys
spec = importlib.util.spec_from_loader(
    "wifid", importlib.machinery.SourceFileLoader("wifid", sys.argv[1]))
wifid = importlib.util.module_from_spec(spec); spec.loader.exec_module(wifid)
args = ["device", "wifi", "connect", "HomeNet", "password", "S3cretWifiPw"]
try:
    wifid.run_nmcli("/nonexistent/nmcli", args)
except wifid.Failed as exc:
    print(str(exc))
except Exception as exc:  # noqa: BLE001
    print("UNEXPECTED " + type(exc).__name__ + ": " + str(exc))
PYEOF
)"
case "$leak_out" in
  *S3cretWifiPw*) echo "FAIL S8: the Wi-Fi password came back in the daemon's error text"; fail=1 ;;
  UNEXPECTED*)    echo "FAIL S8: run_nmcli raised the wrong thing ($leak_out)"; fail=1 ;;
  "")             echo "FAIL S8: run_nmcli did not fail on a missing nmcli"; fail=1 ;;
  *)              echo "ok   S8: a failed nmcli call never echoes the Wi-Fi password back" ;;
esac
case "$leak_out" in
  *device*) echo "ok   S8: the error still names the nmcli subcommand, so it is diagnosable" ;;
  *) echo "FAIL S8: the error names nothing useful ($leak_out)"; fail=1 ;;
esac

echo "wifi-test RESULT: $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit $fail
