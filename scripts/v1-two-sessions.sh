#!/bin/bash
# V1 driver (runs on the Mac; needs SSH_CFG with hosts `air` and `vm`, see docs/vm.md):
# with one graphical session live in the VM, ask SDDM for a greeter, log a second user in by
# typing on the console through QMP, and report what loginctl and the VTs show.
# Usage: SSH_CFG=<path> scripts/v1-two-sessions.sh <second-user> <second-password> [shots-dir]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${OMARCHY_KIDS_VM_DRIVER_LOCKED:-0}" != 1 ]]; then
  exec "$SCRIPT_DIR/vm-driver-lock" "$0" "$@"
fi
CFG="${SSH_CFG:?set SSH_CFG}"
U2="${1:?user}"
P2="${2:?password}"
OUT="${3:-/tmp}"
vm() { ssh -F "$CFG" vm "$@"; }
air() { ssh -F "$CFG" air "$@"; }
qmp() { air "bash ~/omarchy-kids-sandbox/scripts/vm-qmp.sh $*"; }
shot() {
  air "bash ~/omarchy-kids-sandbox/scripts/vm-qmp.sh shot /tmp/$1.png >/dev/null"
  scp -q -F "$CFG" "air:/tmp/$1.png" "$OUT/$1.png"
  air "rm -f /tmp/$1.png"
  echo "shot: $OUT/$1.png"
}
echo "== sessions before =="
vm 'loginctl list-sessions --no-legend'
first=$(vm 'loginctl list-sessions --no-legend | awk "\$5==\"user\" && \$7!=\"-\" {print \$3; exit}"')
echo "first graphical user: ${first:-?}"
echo "== asking SDDM for a greeter =="
vm 'dbus-send --system --print-reply --dest=org.freedesktop.DisplayManager /org/freedesktop/DisplayManager/Seat0 org.freedesktop.DisplayManager.Seat.SwitchToGreeter 2>&1 | tail -1'
sleep 12
shot v1-greeter
echo "== typing $U2 on the greeter =="
qmp type "$U2"
qmp key tab
qmp type "$P2"
qmp enter
sleep 40
shot v1-second-session
echo "== sessions after =="
vm 'loginctl list-sessions --no-legend; for s in $(loginctl list-sessions --no-legend | awk "{print \$1}"); do echo "session $s: $(loginctl show-session $s -p Name -p VTNr -p Active -p State --value | tr "\n" " ")"; done'
echo "== VT exposure: Ctrl+Alt+F1 then F2, screenshots =="
qmp key ctrl-alt-f1
sleep 4
shot v1-vt1
qmp key ctrl-alt-f2
sleep 4
shot v1-vt2
echo "== done; first user's session state =="
vm "loginctl list-sessions --no-legend | grep ' $first ' || true"
