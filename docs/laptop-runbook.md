# Test laptop runbook — 2019 MacBook Air 13" (T2)

From zero to a remote-controlled Omarchy test box. Steps 1–4 need hands on the machine; after
that, everything happens over SSH.

## 0. What you need

- The flashed USB stick (the M1 Mac side is scripted — see below)
- Wired network: USB-Ethernet dongle, or iPhone USB tethering (only if the live installer has no Wi-Fi)

## 1. Firmware — the T2 step people miss

Boot into recovery (hold **Cmd+R** at the chime) → Utilities → **Startup Security Utility**:

- Secure Boot: **No Security**
- External Boot: **Allow booting from external media**

Omarchy requires Secure Boot off; T2 Macs also block USB boot until you allow it here. The
ISO boots the t2 kernel, so the internal keyboard and trackpad work in the installer; the old
external-keyboard advice no longer applies.

## 2. Boot the stick

Shut down. Hold **Option** while powering on → pick the orange EFI/USB entry.

## 3. Install Omarchy

- At the disk screen: wipe the whole disk.
- **Press Ctrl+C at the disk confirmation to skip encryption.** A test box must reboot
  unattended; LUKS would demand a passphrase at every boot. (The LUKS-specific checks get their
  own encrypted install later.)
- Choose **Me**. User: `mark`, a password you will type a lot. Finish, pull the stick, reboot.

## 4. Bring-up (last hands-on step): Tailscale

Get online first. Omarchy 4.0.2 installs `apple-bcm-firmware` with the T2 kernel, so Wi-Fi
should work on the installed system; if the installer's live environment has no Wi-Fi, use
iPhone USB tethering (Settings → Personal Hotspot; Linux picks it up with no setup) or an
Ethernet dongle just for the install. Then, in the Omarchy menu: **Install → Service →
Tailscale**, and in a terminal:

```bash
sudo tailscale up --ssh
```text

Open the printed link on your phone and sign in. The laptop is now reachable from any machine
on the same Tailscale account, with no SSH keys to manage: Tailscale SSH authenticates through
the tailnet.

## 5. From the Mac, forever after

Install Tailscale on the Mac (App Store or `brew install --cask tailscale`), sign in with the
same account, then:

```bash
ssh mark@<laptop-name>        # the name Tailscale shows for the Air
```text

If Wi-Fi is still dead after install, Method 5 of the t2linux guide needs no macOS: run their
`firmware.sh` on the laptop and pick the download option.
<https://wiki.t2linux.org/guides/wifi-bluetooth/>

## 6. Driving the desktop remotely

Everything below runs over SSH inside the live session (export `WAYLAND_DISPLAY` and
`HYPRLAND_INSTANCE_SIGNATURE` from the session's environment first):

| Need | Tool (all shipped by Omarchy) |
| --- | --- |
| Screenshot | `omarchy-capture-screenshot` / `grim` |
| Screen recording | `omarchy-capture-screenrecording` |
| Type text, press chords | `wtype` |
| Focus, workspaces, exec | `hyprctl dispatch …` |
| Read the kid's screen state | `hyprctl clients -j` |

## 7. Boot-level checks live in VMs

The disk prompt, the portal, two live sessions, and the early-boot hook are tested in QEMU on
the laptop, never on its own disk. The Omarchy ISO repo ships the harness (`bin/omarchy-vm`,
`bin/omarchy-iso-test`, unattended `cidata` installs). From the VM monitor you can type at the
disk prompt, screenshot the login screen, and reboot without risk.

First jobs on the box: confirm Wi-Fi, then `test/verify-phase1.sh`, then the Milestone 0
checks in `SPEC.md` §7.

## What still needs hands

The Limine boot menu, firmware password tests, snapshot-entry checks, and the later encrypted
install. Everything else is remote.
