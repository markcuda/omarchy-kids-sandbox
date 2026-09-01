# Test laptop runbook — 2019 MacBook Air 13" (T2)

From zero to a remote-controlled Omarchy test box. Steps 1–4 need hands on the machine; after
that, everything happens over SSH.

## 0. What you need

- The flashed USB stick (the M1 Mac side is scripted — see below)
- An **external USB keyboard** (internal keyboard/trackpad may be dead in the installer on T2)
- Wired network: USB-Ethernet dongle, or iPhone USB tethering (T2 Wi-Fi needs firmware dialed in later)

## 1. Firmware — the T2 step people miss

Boot into recovery (hold **Cmd+R** at the chime) → Utilities → **Startup Security Utility**:

- Secure Boot: **No Security**
- External Boot: **Allow booting from external media**

Omarchy requires Secure Boot off; T2 Macs also block USB boot until you allow it here.

## 2. Boot the stick

Shut down. Hold **Option** while powering on → pick the orange EFI/USB entry.

## 3. Install Omarchy

- At the disk screen: wipe the whole disk.
- **Press Ctrl+C at the disk confirmation to skip encryption.** A test box must reboot
  unattended; LUKS would demand a passphrase at every boot. (The LUKS-specific checks get their
  own encrypted install later.)
- User: `mark`, a throwaway password. Finish, pull the stick, reboot.

## 4. Bring-up (last hands-on step)

Get the repo onto the box (USB stick, or `git clone` once network works), then:

```bash
bash scripts/bringup.sh "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFAcoHMSF7LmBLv6G9TBmiPg3DAv1O4wcXC5ySsHG4YY kids-test control key"
```

It sets hostname `kids-test`, enables sshd, installs the control key, prints the IP.

## 5. From the M1, forever after

```bash
ssh -i ~/.ssh/omarchy_kids_ed25519 mark@kids-test.local   # or the printed IP
```

First jobs on the box: `test/verify-phase1.sh`, then the T2 dial-in (`docs/t2-macbook.md`),
then wizard development.

## What still needs hands

The Limine boot menu, firmware password tests, snapshot-entry checks, and the later encrypted
install. Everything else is remote.
