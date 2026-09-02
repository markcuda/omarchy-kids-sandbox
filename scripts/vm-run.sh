#!/bin/bash
# Start the test VM. `install`: boot the ISO with the cidata drive; QEMU exits when the installer
# reboots. `boot`: boot the installed disk. `stop`: power it off. State lives in ~/vm.
set -euo pipefail
VM="${VM_DIR:-$HOME/vm}"; MODE="${1:-boot}"; MEM="${VM_MEM:-3072}"; SSH_PORT="${VM_SSH_PORT:-2222}"
cd "$VM"
case $MODE in
  stop) [[ -S qmp.sock ]] && printf '{"execute":"qmp_capabilities"}\n{"execute":"quit"}\n' | socat - UNIX-CONNECT:qmp.sock >/dev/null; rm -f qmp.sock; echo stopped; exit 0 ;;
  install) extra=(-drive file=omarchy-4.0.2.iso,media=cdrom,if=none,id=cd0 -device ide-cd,drive=cd0,bootindex=0
                  -drive file=cidata.img,format=raw,if=none,id=cidata -device virtio-blk-pci,drive=cidata -no-reboot) ;;
  boot) extra=() ;;
  *) echo "usage: vm-run.sh install|boot|stop"; exit 2 ;;
esac
rm -f qmp.sock
qemu-system-x86_64 -cpu host -enable-kvm -machine q35,accel=kvm -smp 2 -m "$MEM" \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=OVMF_VARS.fd \
  -drive file=disk.qcow2,format=qcow2,if=none,id=drive0 -device virtio-blk-pci,drive=drive0,bootindex=1 \
  -device virtio-vga -display none -vnc 127.0.0.1:5 -usb -device usb-tablet \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22 -device virtio-net-pci,netdev=net0 \
  -qmp unix:qmp.sock,server,nowait -serial file:serial-$MODE.log -pidfile qemu.pid -daemonize "${extra[@]}"
echo "VM started ($MODE): pid $(cat qemu.pid), vnc 127.0.0.1:5905, ssh -p $SSH_PORT, qmp $VM/qmp.sock"
