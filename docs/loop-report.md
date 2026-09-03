# Loop report, night of 2026-09-02

Written for Mark at the end of the autonomous loop. Everything below happened on the test
laptop's QEMU VM (`docs/vm.md`), never on the laptop's own account, and nothing left the two
machines except pushes to this repo and issue comments.

## What was built

Every ticket in Milestones 1 to 5 has code on `main`, merged from one agent branch each after
the unit suite (`bash test/all`, 28 files) passed: provisioning and the assert locks, the boot
hook and per-boot autologin, the verifier daemon and the parent-unlock PAM lines, the Level 1/2/3
configs and the Level 1 launcher, the SDDM portal theme, the Super x3 exit modal, the screen-time
engine, Ask a parent, Wi-Fi for kids, the wizard (Easy and Advanced), the panel, the bar widget,
recorded data, the plugins shelf, `omarchy-kids-check` v2, Remove Kids Mode, the live harness,
and the shipping docs (`docs/install.md`, `PRIVACY.md`, `docs/parent-card.md`, `.SRCINFO`,
`CHANGELOG.md`).

## What is verified live

Each command's doc has a "Verified live" section with the exact evidence. In one line each:

- Cold boot with a kid's disk password lands on that kid's Level 1 launcher; the owner's password
  lands on the owner's desktop; an unknown slot lands on the portal.
- The portal shows every account with names, face icons and a smaller parent tile; keyboard-only
  login works; the parent's password on a kid's tile opens the kid's session.
- Super x3 opens the exit modal; parent password + Finish ends the session cleanly and a fresh
  portal appears. The same works from root for the bar and panel.
- Screen time: the ledger ticks real minutes, toasts fire, Time's Up appears by budget and by
  lights-out, and auto-Finish returns the portal. Ask a grown-up grants minutes on the spot.
- The wizard provisions a kid through all fifteen Appendix A screens (answers file over
  `ssh -tt`); a cold boot as that kid works. The Advanced path writes exactly the changed cells.
- The panel shows live minutes per kid and grants time through one sudo prompt.
- The Chromium walled garden blocks non-allowed sites for a 6-8 kid; the Web tile launches
  Chromium without Omarchy's extension flags or the keyring prompt.
- The Wi-Fi helper refuses parent-managed kids and answers helper-mode kids over its socket.
- Kid sessions have private `noexec` `/tmp` and `/dev/shm` on both login stacks.
- `test/live/all` runs seven scenarios end to end against the VM and all pass.

## What is open

- `#2` V1 and `#17` Pause: SDDM on 4.0.2 cannot open a second greeter; a design decision.
- `#4` V3: the captive-portal window needs a real captive portal to test.
- `#24` `#26` `#28`: the real pack install, Wi-Fi on real hardware, and a populated plugins
  catalog need the laptop or upstream.
- `#45`: small leftovers from the real Remove Kids Mode run (the removal itself worked and the
  kids' files landed under the owner's "Kids Mode" folder).
- `#33`: the upstream notes for Pete's PR are written up; posting is yours.

Decisions waiting for you: `docs/phase1/DECISIONS-NEEDED.md` (Pause, snapshot entries, AUR
publish, upstream notes). Blocked items: `docs/phase1/BLOCKED.md`.

## Things learned the hard way

`docs/exit.md`, `docs/vm.md` and `docs/live-tests.md` carry the details; the short list: a
hard `loginctl terminate-session` or a killed greeter leaves SDDM with no greeter at all;
Hyprland 0.56 wants `hyprctl dispatch 'hl.dsp.exit()'`; a QEMU power cut two seconds after
`pacman -U` zeroed the unit files; `DRY_RUN=0` does not cross `sudo`; SDDM's autologin stack is
a separate PAM file; the greeter lists accounts alphabetically, not in our order.

## State of the machines

The laptop (`omarky-air`) was never rebooted and its own account was not touched beyond the
repo clone. After the real Remove run the VM holds no kid profiles (their files are under the owner's
"Kids Mode" folder); Cy is being re-provisioned by the wizard as the closing check; the owner `kid-vm` is in `omarchy-parents` and has the bar widget enabled. The
scratchpad on the Mac holds only the driving scripts; every screenshot was deleted after viewing.
