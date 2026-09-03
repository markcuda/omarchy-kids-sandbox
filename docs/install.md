# Installing Kids Mode

For a parent, on their own machine. If you'd rather read code than prose, `docs/packaging.md`
covers the same ground from the package's point of view.

## Before you start

- **Omarchy 4.0.x.** This is built and tested against Omarchy 4.0.2. Nothing here has run on
  4.1 or later.
- **An encrypted install.** Kids Mode gives each kid their own LUKS passphrase and reads which
  slot unlocked the disk to decide whose desktop to start (§R-BOOT). If your disk isn't
  encrypted, there is no slot to key off of and Kids Mode has nothing to install onto yet.
- **Your own login password**, the one you type to unlock your account. Kids Mode never asks for
  anything else — no `root` password, no separate admin password, nothing it stores itself
  (SPEC.md I-8). Every parent-only prompt checks what you type against your own account.

## Install

There is no AUR package yet — `.SRCINFO` is checked into this repo so publishing is one step,
but nobody has taken that step (`docs/packaging.md`'s "AUR readiness"). Until it's published,
build from a clone, the same way `docs/packaging.md` does:

```sh
git clone https://github.com/markcuda/omarchy-kids-sandbox
cd omarchy-kids-sandbox
makepkg -si
```

`-s` resolves and installs `depends` with pacman (you'll be asked for your password there, same
as any `pacman -S`); `-i` installs the built package once it's done. Don't run `makepkg` as root
or with `sudo` — it refuses to build that way, and `docs/packaging.md` explains why. Once this is
on the AUR, the same line becomes `yay -S omarchy-kids` (or whatever AUR helper you use) instead.

## Start it

```sh
omarchy-kids
```

Or open **Kids Mode** from the app drawer. The first run is the parent wizard: your password,
then one kid at a time — name, face, age, Simple (a handful of A-or-B choices, defaults
pre-picked by age) or Advanced (every setting on one screen), a password for the kid, a summary,
then Apply. Apply's last step is a green/red safety check; a red line means something didn't take
and names what to fix, rather than pretending it worked (SPEC.md I-6). Once at least one kid
exists, `omarchy-kids` opens the parent panel instead of the wizard — that's where you add more
kids, change anything, or check on a kid's screen time.

Everything the wizard offers to do is a **dry run until you choose Apply**. Nothing is written to
your disk before that screen.

## What changes on the machine

Full detail, lock by lock, is `docs/assert.md`'s "lock list" — this is the same list in plain
words. Every one of these is root-owned and re-checked on every update and every kid login
(SPEC.md I-3, I-4); nothing here is a setting a kid's own account could undo.

**Per kid, once they're added:**

- A real Unix account (`kid-<name>`), no `sudo`, not in `wheel`.
- Their home directory mounted so nothing in it can execute (`noexec,nosuid,nodev`), and their
  own private `/tmp` and `/dev/shm`.
- A LUKS passphrase slot on your disk, so their own password can unlock the machine and land them
  straight on their own desktop.
- A face tile on the login screen and their real name where the greeter shows it.

**Once, for the machine, while any kid exists:**

- A polkit rule that routes anything a kid's session needs your say-so for (installing a package,
  changing Wi-Fi, mounting a drive) to a native dialog asking for *your* password — and a second
  rule that silently refuses the handful of things no dialog should ever offer a kid.
- The login screen itself, replaced with face tiles (yours last).
- A line added to the PAM stacks your password already checks against (login and the lock
  screen), so Kids Mode's own prompts verify the same way your desktop already does — no second
  password, no new credential store.
- Text consoles tty2 through tty6 masked, so there's no console at the login screen to drop into.
- A handful of systemd units and sockets that run the screen-time ledger, the boot-time login
  chooser, and the two small verifier daemons.
- A Chromium policy file per age band (mode 0640 — the kid's browser reads it, yours never does).
- A line in your initramfs that makes the per-kid LUKS-slot lookup possible at boot at all.
- By default, pre-Kids-Mode Snapper snapshots hidden from the boot menu, so a kid who knows your
  disk password can't pick an unlocked, un-restricted snapshot from Limine and land on your old
  desktop. Turn this off with `omarchy-kids-conf` (`docs/conf.md`'s `boot.snapshot_entries`); your
  own `snapper rollback` from the running system is unaffected either way.

**Never:** anything in your own home, your own browser, your own DNS, or your own session —
SPEC.md's I-1 states this as flatly as the spec states anything. If a change ever seems to touch
your own account, that's a bug — see `SECURITY.md` on the hub for how to report it.

## Updating

`pacman -Syu` (or `omarchy update`) upgrades the package normally. A pacman hook runs
`omarchy-kids-assert` after *every* transaction, kid-related or not, and puts back anything an
unrelated update might have dropped — a kernel bump that needed a new initramfs, a config file
pacman overwrote. You should never need to run this by hand; the panel's safety check (or
`omarchy-kids-assert`, plain, from a terminal) shows the same list if you want to see it for
yourself.

## Removing

Two separate steps, on purpose — see `docs/remove.md` for the full walkthrough:

1. **Remove Kids Mode** from the panel (or `omarchy-kids remove-kids-mode`) first. This reverses
   every lock above, removes every kid account, and offers a Snapper snapshot before it starts —
   but it always **keeps every kid's files**, moved to
   `~/Kids Mode/<name>/` under your own home.
2. `sudo pacman -R omarchy-kids` afterwards removes the package itself. Skipping straight to this
   step leaves every lock, group, and kid account in place — `pacman -R` alone is not Remove Kids
   Mode.

## What isn't ready yet

This is early: the spec (SPEC.md) is further along than the build. Read this before you hand a
kid their password.

- **Pause** (fast switching back to your desktop without closing a kid's apps) isn't built.
  Omarchy 4.0.2's login screen can't open a second one while a session is live — see
  `docs/phase1/DECISIONS-NEEDED.md` — so today the exit modal only offers **Finish**, which closes
  everything and returns to the login screen. If a hard-terminate fallback ever fires, the screen
  can go black until someone runs `systemctl restart sddm`; a kid can't reach a terminal to do
  that themselves (their consoles are masked), so today that's on you — see `docs/parent-card.md`.
- **The firmware/BIOS password** is on you, entirely outside Kids Mode. A kid with a keyboard at
  boot and no firmware password can boot something else and bypass everything above. There's no
  software toggle tracking whether you've done this yet — `docs/parent-card.md` has the steps.
- **Wi-Fi for kids** has only run in a VM with no wireless device: the deny-by-default and the
  refusal message are confirmed, but a real join, forgetting a network, and the captive-portal
  helper window all still need a real Wi-Fi card (`docs/wifi.md`'s "Verified live").
- **The wrong-password shake and lockout**, on the login screen and the exit modal, haven't run
  live yet, nor has Esc-to-close on the exit modal (`docs/portal.md`, `docs/exit.md`).
- **Most of the panel** — Requests, Web, Apps, Password, Remove — is the same code path as Home,
  which has run live, but hasn't itself been exercised live yet (`docs/panel.md`).
- **"Ask later"** (queueing a request instead of asking on the spot) and asking for an app or a
  site (rather than more time) haven't run live yet (`docs/ask.md`).
- Phase 1's V1, V3, and part of V6 checks are still in progress — see the repo's `README.md` and
  `docs/phase1/` for where each one stands.

Every command's own doc under `docs/` has a "Verified live" section — that's the actual source
of truth for what has and hasn't run against real Hyprland, Quickshell, and SDDM, not this list
or any marketing language anywhere else in this repo.
