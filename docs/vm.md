# The test VM

Boot-level checks (disk prompt, portal, two sessions, the early-boot hook, Limine, snapshots)
run in a QEMU/KVM guest on the test laptop, never on its own disk. The recipe is three scripts.

| Script | Does |
| --- | --- |
| `scripts/vm-build.sh` | Creates `~/vm/disk.qcow2` (40 G), UEFI vars, and `cidata.img`: a FAT drive labeled `cidata` with the installer's answer files, generated from the same template the Omarchy configurator writes (full-disk, encrypted, user `kid-vm`, password `omarchy`, your SSH key authorized) |
| `scripts/vm-run.sh install` | Boots the ISO with the cidata drive attached; the ISO installs itself with no keyboard and QEMU exits when the installer reboots |
| `scripts/vm-run.sh boot` | Boots the installed disk. SSH: `ssh -p 2222 kid-vm@127.0.0.1` on the laptop. VNC: `127.0.0.1:5905` |
| `scripts/vm-qmp.sh` | `shot out.png` screenshots the console; `type omarchy` and `enter` type at the disk prompt; `quit` powers off |

Facts this rests on, read from `omacom/omarchy-iso` on 2026-09-02: the autoinstall trigger is any
drive labeled `cidata` holding `user_configuration.json` and `user_credentials.json`; the
partition math and JSON come from the configurator's full-disk writer; the QEMU device layout
(q35, virtio-blk with bootindex, virtio-vga, usb-tablet, user networking with an SSH forward,
QMP socket, serial to file) is `bin/omarchy-iso-test`'s. The ISO carries its own package mirror,
so the install needs no network.

The VM disk is encrypted on purpose: V4 and V7 need LUKS. At boot the guest waits at the disk
prompt until `vm-qmp.sh type omarchy` and `vm-qmp.sh enter`.

## Driving it from the Mac

The Mac-side drivers (`scripts/v1-two-sessions.sh`, `scripts/v6-limine.sh`) expect an ssh config
with two hosts, passed as `SSH_CFG`:

```text
Host air
  HostName omarky-air
  User omarky-air
  IdentityFile ~/.ssh/omarchy_kids_ed25519
Host vm
  HostName 127.0.0.1
  Port 2222
  User kid-vm
  ProxyJump air
  IdentityFile ~/.ssh/omarchy_kids_ed25519
  UserKnownHostsFile ~/.ssh/known_hosts_vm
```

Inside the VM, `sudo` wants the password: `printf 'omarchy\n' | sudo -S -p '' <cmd>`. Ten wrong
attempts trip faillock for two minutes, so never call `sudo` without feeding it.
