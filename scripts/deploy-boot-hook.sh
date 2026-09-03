#!/bin/bash
# TEST MACHINES ONLY (a VM, or the test laptop): install the early-boot slot hook and the per-boot
# autologin pieces from this checkout, the way the package will, and rebuild the boot image.
# Usage: sudo scripts/deploy-boot-hook.sh [--remove]   (run from the repo root)
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ ${1:-} == --remove ]]; then
  rm -f /usr/lib/initcpio/hooks/omarchy-kids-unlock /usr/lib/initcpio/install/omarchy-kids-unlock /usr/lib/initcpio/omarchy-kids-open \
    /etc/mkinitcpio.conf.d/omarchy_kids.conf /usr/bin/omarchy-kids-boot-login /etc/sddm.conf.d/zz-omarchy-kids-autologin.conf
  systemctl disable --now omarchy-kids-boot-login.service omarchy-kids-boot-login-cleanup.service 2>/dev/null || true
  rm -f /etc/systemd/system/omarchy-kids-boot-login.service /etc/systemd/system/omarchy-kids-boot-login-cleanup.service
  systemctl daemon-reload
  mkinitcpio -P 2>&1 | grep -E "Image generation|WARNING|ERROR" | head -6
  echo "removed"
  exit 0
fi
install -m 755 "$R/initcpio/hooks/omarchy-kids-unlock" /usr/lib/initcpio/hooks/omarchy-kids-unlock
install -m 755 "$R/initcpio/install/omarchy-kids-unlock" /usr/lib/initcpio/install/omarchy-kids-unlock
install -m 755 "$R/initcpio/omarchy-kids-open" /usr/lib/initcpio/omarchy-kids-open
install -m 644 "$R/etc/mkinitcpio.conf.d/omarchy_kids.conf" /etc/mkinitcpio.conf.d/omarchy_kids.conf
install -m 755 "$R/bin/omarchy-kids-boot-login" /usr/bin/omarchy-kids-boot-login
install -m 644 "$R/systemd/omarchy-kids-boot-login.service" "$R/systemd/omarchy-kids-boot-login-cleanup.service" /etc/systemd/system/
install -d -m 700 /etc/omarchy-kids
touch /etc/omarchy-kids/luks-slots
chmod 600 /etc/omarchy-kids/luks-slots
systemctl daemon-reload
systemctl enable omarchy-kids-boot-login.service omarchy-kids-boot-login-cleanup.service >/dev/null 2>&1
echo "Rebuilding the boot image with the hook in place..."
mkinitcpio -P 2>&1 | grep -E "Image generation|WARNING|ERROR|omarchy-kids" | head -8
UKI=$(ls -t /boot/EFI/Linux/*.efi 2>/dev/null | head -1)
if [[ -n $UKI ]]; then
  objcopy -O binary --only-section=.initrd "$UKI" /tmp/ir.img && echo "hook files in the boot image: $(lsinitcpio /tmp/ir.img | grep -c 'omarchy-kids')"
  rm -f /tmp/ir.img
fi
echo "deployed. Map slots in /etc/omarchy-kids/luks-slots as 'N=account' or 'N=account:session', then reboot."
