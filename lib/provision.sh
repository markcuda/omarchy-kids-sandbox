#!/bin/bash
# Host-side Kids Mode: one desktop UID, kid password not in shadow,
# namespaced home, family DNS, Wi-Fi helper, sudo DNS requires parent password.
set -euo pipefail
DRY_RUN="${DRY_RUN:-1}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWNER="${OMARCHY_KIDS_OWNER:-${SUDO_USER:-}}"
KID_USER="${OWNER:-}" # same UID; name kept for check script compatibility

run() { if [[ "$DRY_RUN" == "0" ]]; then "$@"; else echo "  [dry-run] $*"; fi; }

require_owner() {
  [[ -n "$OWNER" ]] || { echo "set OMARCHY_KIDS_OWNER or run via sudo from the desktop user" >&2; exit 1; }
  id "$OWNER" >/dev/null
}

create_kid_account() {
  require_owner
  echo "▸ Namespaced kid home for '$OWNER' (no second Unix user)"
  run install -d -m 0755 /var/lib/omarchy-kids /etc/omarchy-kids /run/omarchy-kids
  run bash -c "printf '%s\n' '$OWNER' > /etc/omarchy-kids/owner"
  run chmod 0644 /etc/omarchy-kids/owner
  OMARCHY_KIDS_OWNER="$OWNER" run "$REPO/bin/omarchy-kids-session" setup || \
    run env OMARCHY_KIDS_OWNER="$OWNER" "$REPO/bin/omarchy-kids-session" setup
}

set_kid_password_hash() {
  local hash="${1:-}"
  [[ -n "$hash" ]] || { echo "kid password hash missing" >&2; exit 1; }
  echo "▸ Kid login hash (not in /etc/shadow)"
  run bash -c "printf '%s\n' '$hash' > /etc/omarchy-kids/kid.passwd"
  run chmod 0600 /etc/omarchy-kids/kid.passwd
}

install_session_dispatch() {
  echo "▸ Session dispatch + PAM kid password"
  run install -m 0755 "$REPO/lib/pam-kid-auth" /usr/local/libexec/omarchy-kids-pam-auth
  run install -m 0755 "$REPO/bin/omarchy-kids-dispatch" /usr/local/bin/omarchy-kids-dispatch
  run install -m 0755 "$REPO/bin/omarchy-kids-session" /usr/local/bin/omarchy-kids-session
  run install -m 0755 "$REPO/lib/omarchy-kids-denied" /usr/local/libexec/omarchy-kids-denied
  run install -m 0755 "$REPO/bin/omarchy-kids-wifi" /usr/local/bin/omarchy-kids-wifi
  run install -m 0755 "$REPO/libexec/omarchy-kids-wifi-connect" /usr/local/libexec/omarchy-kids-wifi-connect
  run install -m 0644 "$REPO/share/org.omarchy.kids.policy" /usr/share/polkit-1/actions/org.omarchy.kids.policy
  run install -m 0644 "$REPO/share/omarchy.desktop" /usr/share/wayland-sessions/omarchy.desktop

  if [[ "$DRY_RUN" == "0" ]]; then
    if [[ -f /etc/pam.d/sddm ]] && ! grep -q omarchy-kids-pam-auth /etc/pam.d/sddm; then
      local tmp
      tmp="$(mktemp)"
      { cat "$REPO/share/sddm-pam-head"; grep -v '^#%PAM-1.0' /etc/pam.d/sddm || true; } >"$tmp"
      install -m 0644 "$tmp" /etc/pam.d/sddm
      rm -f "$tmp"
    fi
    local s
    for s in hyprland-uwsm.desktop hyprland.desktop; do
      local f="/usr/share/wayland-sessions/$s"
      [[ -f "$f" ]] || continue
      if [[ ! -f "$f.omarchy-kids-bak" ]]; then
        cp "$f" "$f.omarchy-kids-bak"
      fi
      sed -i 's|^Exec=.*|Exec=/usr/local/bin/omarchy-kids-dispatch|' "$f"
    done
  else
    echo "  [dry-run] prepend PAM kid-auth to /etc/pam.d/sddm"
    echo "  [dry-run] point wayland sessions at omarchy-kids-dispatch"
  fi
}

apply_web_safety() {
  echo "▸ Family DNS on the host resolver (kid cannot call omarchy-dns without parent password)"
  run install -d -m 0755 /etc/systemd/resolved.conf.d
  run install -m 0644 "$REPO/share/30-omarchy-kids-family.conf" /etc/systemd/resolved.conf.d/30-omarchy-kids-family.conf
  run install -m 0440 "$REPO/share/zz-omarchy-kids-sudoers" /etc/sudoers.d/zz-omarchy-kids
  run visudo -c
  run systemctl restart systemd-resolved

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
  echo "▸ Boot: Limine editor off; mask getty@tty1; lock root"
  if [[ "$DRY_RUN" == "0" && -w /boot/limine.conf ]]; then
    grep -q '^editor_enabled' /boot/limine.conf || echo 'editor_enabled: no' >>/boot/limine.conf
  else
    echo "  [dry-run] editor_enabled: no -> /boot/limine.conf"
  fi
  run systemctl mask getty@tty1.service
  run passwd -l root
  echo "  [manual] Firmware password is still on you."
}

install_polkit_denies() {
  echo "▸ Wi-Fi helper is passwordless; NM DNS/settings stay parent-gated via sudo + filtered bus"
}

remove_kid_mode() {
  echo "▸ Removing Kids Mode host files (kid store kept)"
  run rm -f /etc/systemd/resolved.conf.d/30-omarchy-kids-family.conf \
    /etc/sudoers.d/zz-omarchy-kids \
    /etc/chromium/policies/managed/omarchy-kids.json \
    /usr/share/polkit-1/actions/org.omarchy.kids.policy \
    /usr/share/wayland-sessions/omarchy.desktop
  run systemctl unmask getty@tty1.service
  run systemctl restart systemd-resolved
  local s
  for s in hyprland-uwsm.desktop hyprland.desktop; do
    local f="/usr/share/wayland-sessions/$s"
    if [[ -f "$f.omarchy-kids-bak" ]]; then
      run mv "$f.omarchy-kids-bak" "$f"
    fi
  done
  echo "  (PAM line in /etc/pam.d/sddm left in place — remove manually if you want a clean revert)"
}
