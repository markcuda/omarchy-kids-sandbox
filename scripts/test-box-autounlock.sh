#!/bin/bash
# TEST BOX ONLY. Lets an encrypted Omarchy machine unlock its own disk at boot, so it can be
# rebooted unattended over SSH. A random key file is added as a LUKS key slot and baked into the
# boot image; anyone with the boot partition can then open the disk. Never use on a real machine.
# Undo: scripts/test-box-autounlock-remove.sh
set -euo pipefail
DEV="${1:-$(lsblk -no PATH,FSTYPE | awk '$2=="crypto_LUKS"{print $1; exit}')}"
KEY=/etc/omarchy/test-box.key
[[ -n "$DEV" ]] || {
  echo "no LUKS device found"
  exit 1
}
echo "LUKS device: $DEV"
sudo install -d -m 755 /etc/omarchy
if ! sudo test -f "$KEY"; then
  sudo bash -c "head -c 64 /dev/urandom > $KEY"
  sudo chmod 600 "$KEY"
fi
if sudo cryptsetup open --test-passphrase --key-file "$KEY" "$DEV" 2>/dev/null; then
  echo "key file already opens the disk: OK"
else
  echo "Adding the key file as a new LUKS slot."
  echo "Type the DISK password, the one you type at boot (usually your login password). Up to 3 tries:"
  ok=0
  for i in 1 2 3; do
    if sudo cryptsetup luksAddKey "$DEV" "$KEY"; then
      ok=1
      break
    fi
    echo "That password did not open the disk. Try again ($i/3)."
  done
  [[ $ok == 1 ]] || {
    echo "Could not add the key. Nothing else was changed."
    exit 1
  }
  sudo cryptsetup open --test-passphrase --key-file "$KEY" "$DEV" && echo "key file opens the disk: OK"
fi
printf 'FILES+=(%s)\n' "$KEY" | sudo tee /etc/mkinitcpio.conf.d/zz-test-box.conf >/dev/null
printf 'KERNEL_CMDLINE[default]+=" cryptkey=rootfs:%s"\n' "$KEY" | sudo tee /etc/limine-entry-tool.d/zz-test-box.conf >/dev/null
echo "Rebuilding the boot image..."
sudo mkinitcpio -P 2>&1 | grep -E "Image generation|WARNING|ERROR" | head -8
UKI=$(ls -t /boot/EFI/Linux/*.efi | head -1)
sudo objcopy -O binary --only-section=.cmdline "$UKI" /tmp/cl.txt && grep -o 'cryptkey=[^ ]*' /tmp/cl.txt
sudo objcopy -O binary --only-section=.initrd "$UKI" /tmp/initrd.img && lsinitcpio /tmp/initrd.img | grep -q test-box.key && echo "key file is inside the boot image: OK"
sudo rm -f /tmp/cl.txt /tmp/initrd.img
echo "DONE. Next reboot should reach the desktop with no disk prompt. If it does prompt, type the disk password as before; nothing is lost."
