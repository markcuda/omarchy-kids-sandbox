#!/bin/bash
# Undo scripts/test-box-autounlock.sh: remove the key slot, the key file, and the boot config.
set -euo pipefail
DEV="${1:-$(lsblk -no PATH,FSTYPE | awk '$2=="crypto_LUKS"{print $1; exit}')}"
KEY=/etc/omarchy/test-box.key
[[ -f $KEY ]] && sudo cryptsetup luksRemoveKey "$DEV" "$KEY" && echo "slot removed"
sudo rm -f "$KEY" /etc/mkinitcpio.conf.d/zz-test-box.conf /etc/limine-entry-tool.d/zz-test-box.conf
sudo mkinitcpio -P 2>&1 | grep -E "Image generation|WARNING|ERROR" | head -6
echo "DONE. The disk asks for its password at boot again."
