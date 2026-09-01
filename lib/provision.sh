#!/bin/bash
# Provisioning actions for Omarchy Kids Mode. DRY_RUN=1 by default: print, don't change.
# Verified facts these lean on are cited in the hub's research/ (reports 01, 03, 04).
set -euo pipefail
DRY_RUN="${DRY_RUN:-1}"
KID_USER="${KID_USER:-kid}"

run() { if [[ "$DRY_RUN" == "0" ]]; then "$@"; else echo "  [dry-run] $*"; fi; }

create_kid_account() {
  echo "▸ Kid account: '$KID_USER' — no sudo, no groups, locked-down home"
  run useradd -m -s /bin/bash "$KID_USER"
  run groupadd -f omarchy-kids
  run usermod -aG omarchy-kids "$KID_USER"
  # noexec home: downloads can't execute (report 03; VFS flags are per-mount even on btrfs)
  run bash -c "grep -q '/home/$KID_USER .*bind' /etc/fstab || echo '/home/$KID_USER /home/$KID_USER none bind,nosuid,nodev,noexec 0 0' >> /etc/fstab"
  run mount -o remount,bind,nosuid,nodev,noexec "/home/$KID_USER" || true
  install_polkit_denies
}

install_polkit_denies() {
  echo "▸ Polkit: deny package installs, network changes, mounts for the kid (no prompts → no lockout DoS)"
  # Action IDs verified with pkaction on the target before trusting this list (Phase 1).
  run install -o root -g polkitd -m 0644 /dev/stdin /etc/polkit-1/rules.d/10-omarchy-kids.rules <<'RULES'
polkit.addRule(function(action, subject) {
  if (subject.isInGroup("omarchy-kids")) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0 ||
        action.id.indexOf("org.freedesktop.udisks2.filesystem-mount") === 0 ||
        action.id.indexOf("org.freedesktop.udisks2.encrypted-unlock") === 0 ||
        action.id === "org.freedesktop.udisks2.loop-setup" ||
        action.id === "org.freedesktop.systemd1.manage-units" ||
        action.id.indexOf("org.freedesktop.Flatpak.") === 0) {
      return polkit.Result.NO;
    }
  }
});
RULES
  run systemctl restart polkit
}

apply_web_safety() {
  echo "▸ Web safety: family DNS (strict DoT) + locked Chromium policy"
  # DNS: Omarchy 4.x pins DNS via NetworkManager global-dns + systemd-resolved (verified from bin/omarchy-dns).
  run install -m 0644 /dev/stdin /etc/NetworkManager/conf.d/20-omarchy-kids-dns.conf <<'NM'
[global-dns-domain-*]
servers=1.1.1.3,1.0.0.3
NM
  run install -m 0644 /dev/stdin /etc/systemd/resolved.conf.d/10-omarchy-kids.conf <<'RESOLVED'
[Resolve]
DNS=1.1.1.3#family.cloudflare-dns.com 1.0.0.3#family.cloudflare-dns.com
FallbackDNS=94.140.14.15#family.adguard-dns.com
DNSOverTLS=yes
Domains=~.
RESOLVED
  run systemctl restart NetworkManager systemd-resolved
  run install -d -m 0755 /etc/chromium/policies/managed
  run install -m 0644 /dev/stdin /etc/chromium/policies/managed/omarchy-kids.json <<'POLICY'
{
  "DnsOverHttpsMode": "off",
  "ForceGoogleSafeSearch": true,
  "ForceYouTubeRestrict": 2,
  "IncognitoModeAvailability": 1,
  "DeveloperToolsAvailability": 2,
  "ExtensionInstallBlocklist": ["*"],
  "BrowserSignin": 0,
  "DownloadRestrictions": 1,
  "SafeBrowsingProtectionLevel": 1
}
POLICY
}

harden_boot() {
  echo "▸ Boot: Limine editor off (+ note: re-apply after omarchy-refresh-limine; hook comes later)"
  run bash -c "grep -q '^editor_enabled' /boot/limine.conf || echo 'editor_enabled: no' >> /boot/limine.conf"
  echo "▸ TTY: mask getty@tty1, lock root (Omarchy sets root pw = owner's — report 03)"
  run systemctl mask getty@tty1.service
  run passwd -l root
  echo "  [manual] Firmware password + boot order: see the printed parent card. Cannot be scripted."
}

remove_kid_mode() {
  echo "▸ Removing kid provisioning (keeps the kid's files)"
  run rm -f /etc/polkit-1/rules.d/10-omarchy-kids.rules \
        /etc/NetworkManager/conf.d/20-omarchy-kids-dns.conf \
        /etc/systemd/resolved.conf.d/10-omarchy-kids.conf \
        /etc/chromium/policies/managed/omarchy-kids.json
  run systemctl unmask getty@tty1.service
  run systemctl restart polkit NetworkManager systemd-resolved
  echo "  (kid user and home left in place; delete manually if wanted)"
}
