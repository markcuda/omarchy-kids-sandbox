# Decisions the loop could not make alone

| Date | Topic | Where | Options |
| --- | --- | --- | --- |
| 2026-09-02 | Pause (fast user switch) cannot use SDDM on Omarchy 4.0.2: a second greeter fails with `HELPER_TTY_ERROR` on both the VM and the laptop | `docs/phase1/V1.md`, issue #2 | (1) start the parent's session on a spare VT through PAM without SDDM, as a new ticket with its own check; (2) ship Pause as lock-and-logout for v1; (3) wait for upstream multi-user. Note: the failed SDDM call also revoked the laptop's input devices until a udev re-trigger, so it is not a safe thing to ship even as a fallback |

## 3. Limine snapshot entries bypass every lock (V6) — decided 2026-09-04

Decided under Mark's standing order ("i trust you fully"): default hide while any kid profile
exists (`MAX_SNAPSHOT_ENTRIES=0`) with a conf toggle to show them, in disk boot mode only;
portal mode (docs/specs/07-boot-mode.md) never touches Limine, so nothing to hide there.
The wizard's summary names it in disk mode. Tracked in spec 07 ticket 2 (#93) and the
assert gate (#93/#95).

A pre-Kids-Mode Snapper snapshot boots its own frozen UKI (no unlock hook) and its own system
files (no locks, stock owner autologin) on the live home. Anyone with a disk password can pick
it from the boot menu. Recommendation: hide snapshot entries while any kid profile exists
(`MAX_SNAPSHOT_ENTRIES=0`), with a conf toggle to show them again. This touches the parent's
boot menu, not the parent's account: rollback stays available with `snapper rollback` and the
toggle. Your call: default hide, default show with a warning in the wizard, or something else.
Evidence: docs/phase1/V6.md.

## 4. Publish to the AUR, and the package name — closed 2026-09-04

Mark, 2026-09-04: "no need to upload the package or hub PR". Out of the definition of done
(docs/GOAL.md). The tree stays AUR-ready.

Everything for a first AUR upload is in the tree (`PKGBUILD`, `.SRCINFO` to regenerate with
`makepkg --printsrcinfo`, `CHANGELOG.md`, `docs/install.md`, `PRIVACY.md`). Publishing is
outward-facing and yours: the package name (`omarchy-kids` today), the maintainer line, and
whether to wait for the laptop round (Wi-Fi on real hardware, the lock screen's parent unlock)
before the first upload.

## 5. Upstream notes for Pete's PR (#33)

The findings worth sending upstream are written up (the `ignore-auto-dns` Wi-Fi helper,
`success=done` parent-unlock PAM line placement, SDDM's no-greeter-after-hard-terminate
behaviour, the Limine snapshot-entry bypass). Posting on omacom/omarchy#9750 is yours.
