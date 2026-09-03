#!/bin/bash
# V6 Limine driver (runs on the Mac; SSH_CFG with host `air`): reboot the VM, stop the boot menu
# timer, screenshot the menu and the entry editor for the default entry and for a snapshot entry,
# then boot the default entry and type the disk password.
# Usage: SSH_CFG=<path> scripts/v6-limine.sh <disk-password> [shots-dir]
set -uo pipefail
CFG="${SSH_CFG:?set SSH_CFG}"; PW="${1:?disk password}"; OUT="${2:-/tmp}"
air(){ ssh -F "$CFG" air "$@"; }
qmp(){ air "bash ~/omarchy-kids-sandbox/scripts/vm-qmp.sh $*"; }
shot(){ air "bash ~/omarchy-kids-sandbox/scripts/vm-qmp.sh shot /tmp/$1.png >/dev/null"; scp -q -F "$CFG" "air:/tmp/$1.png" "$OUT/$1.png"; air "rm -f /tmp/$1.png"; echo "shot: $OUT/$1.png"; }
air 'cd ~/omarchy-kids-sandbox; bash scripts/vm-run.sh stop >/dev/null 2>&1; t=0; until ! pgrep -x qemu-system-x86 >/dev/null || [ $t -ge 60 ]; do sleep 3; t=$((t+3)); done; bash scripts/vm-run.sh boot | tail -1'
# Limine's menu auto-boots after its default 5 s; the first keypress stops the countdown.
# Start pressing early and keep pressing until the menu has surely been reached.
sleep 1.5; for i in $(seq 1 10); do qmp key down >/dev/null 2>&1; sleep 0.4; done; qmp key up; sleep 1; shot v6-menu
echo "== editor on the default entry =="; qmp key e; sleep 2; shot v6-editor-default; qmp key esc; sleep 1
echo "== expand and inspect the last entry (snapshots live at the bottom) =="; for i in 1 2 3 4 5 6; do qmp key down; done; sleep 1; shot v6-menu-bottom; qmp key ret; sleep 1; shot v6-menu-bottom-open; qmp key e; sleep 2; shot v6-editor-bottom; qmp key esc; sleep 1
echo "== boot the default entry =="; for i in 1 2 3 4 5 6 7 8; do qmp key up; done; qmp enter; sleep 45; qmp type "$PW"; qmp enter; sleep 60; shot v6-after-boot
