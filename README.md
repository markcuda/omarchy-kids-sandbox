# Omarchy Kids Mode - Sandbox Edition

The **sandbox path** of [Omarchy Kids Mode](https://github.com/markcuda/omarchy-kids-mode): Kids
Mode as an app on a normal Omarchy install. The parent keeps their own account and full desktop,
never restricted. Each kid gets a profile that is a real account underneath. A Super triple-tap
and the parent password get the parent back out. Core is untouched.

A spoke of the Kids Mode hub. The design lives there:
**[PATH-SANDBOX.md](https://github.com/markcuda/omarchy-kids-mode/blob/main/PATH-SANDBOX.md)**,
sixteen settled decisions, what we borrowed and from whom, and the Phase 1 checks.

The other path, chosen at install with one account and two passwords, is being built upstream by
Pete: see the hub's
[PATH-INSTALLER.md](https://github.com/markcuda/omarchy-kids-mode/blob/main/PATH-INSTALLER.md).
The two share the parent command and its feature commands.

## Status: v1 build in progress

The spec is **[SPEC.md](SPEC.md)**; the work is
[issues in six milestones](https://github.com/markcuda/omarchy-kids-sandbox/milestones), in build
order. Results of the Phase 1 checks live in [`docs/phase1/`](docs/phase1/): as of the evening of
2026-09-02, **V2, V4, V5 and V7 pass** (real hardware and the QEMU test VM described in
[`docs/vm.md`](docs/vm.md)); V1, V3 and the rest of V6 are in progress.

### What works today

Only what has actually run against a real Hyprland, Quickshell, and SDDM in the QEMU test VM —
each command's own doc under [`docs/`](docs/) has the full "Verified live" section this list is
drawn from; nothing here is drawn from the spec alone.

- The parent wizard runs start to finish over SSH with an answers file, provisions a real kid
  account (Unix account, LUKS slot, band, avatar), and a cold boot with that kid's own disk
  password lands straight on their Level 1 launcher — no manual step in between
  (`docs/wizard.md`, `docs/session.md`).
- The login portal shows one face tile per account and logs a kid straight into their own
  Hyprland session by keyboard alone (`docs/portal.md`).
- Super×3 and Super+Shift+K both open the exit modal; the parent password on **Finish** ends the
  kid's session cleanly and SDDM returns to the portal (`docs/exit.md`).
- Screen time counts real minutes while a kid's session is active, warns before it runs out, and
  the lights-out "Time's Up" overlay fires and finishes on its own after 60 seconds with no answer
  (`docs/time.md`).
- "Ask a parent" for more time opens over the launcher, and the parent password grants it on the
  spot — the grant shows up in the ledger within the minute (`docs/ask.md`).
- The parent panel's Home screen shows live per-kid minutes and grants more time for real, run
  over SSH with an answers file (`docs/panel.md`).
- A kid's Wi-Fi request is correctly refused by default, worded for a kid, and routed through the
  root helper when a kid is allowed to join on their own — confirmed without a wireless device, so
  a real join is still unverified (`docs/wifi.md`).

**Try it:** [`docs/install.md`](docs/install.md) — prerequisites, the one-command build, and the

The night the code landed is summarised in `docs/loop-report.md` (what is verified live, what is open, decisions waiting).
honest list of what isn't ready yet.

## What will be here

| Piece | What it does |
| --- | --- |
| Kids Mode app | Opens from the drawer. First run is the parent wizard; after that, a home screen with a settings gear into the panel |
| Parent wizard | Easy path (A-or-B chunks, preselected by age band) or Advanced (a table of toggles). Bash + gum in Omarchy's floating terminal, looks like the installer, Omy where the logo sits |
| Per-kid provisioning | Real account, no sudo, locked home, polkit denies, the installer path's privilege posture, a LUKS slot for the kid's password, a root-owned Hyprland config for the chosen level |
| Login portal | Face tiles then password, as an SDDM theme. Parent tile last |
| Exit modal | Super ×3: parent password, then **Pause** (kid's apps stay open) or **Finish** (closes them) |
| `omarchy-kids-*` | Feature commands: web policy, screen time, apps, Wi-Fi helper, ask-a-parent queue. `time`, `dns`, `apps` also exposed as `omarchy-parent-<feature>` for the upstream dispatcher |
| Safety check | Green/red, at the end of setup and at every kid login, failing closed |

## What is here now

| File | Note |
| --- | --- |
| `bin/omarchy-kids-check` | Green/red self-test, still the right shape |
| `test/verify-phase1.sh` | Collects facts for the hub's Phase 1 unknowns |
| `docs/` | Test-laptop runbook and a T2 MacBook note |

## Open pull request

[#1](https://github.com/markcuda/omarchy-kids-sandbox/pull/1), a one-uid kid session with a
namespaced home, is fine work for the installer path and is not being merged here; the sandbox
path needs one account per kid. Its Wi-Fi helper and filtered system bus are being borrowed with
credit. See the hub's installer page.

## Rules

MIT, same as Omarchy. Never collects anything about a child; nothing leaves the machine. A way for
a kid to get around this is a bug: report privately per the hub's
[SECURITY.md](https://github.com/markcuda/omarchy-kids-mode/blob/main/SECURITY.md). Everything
here must work from the keyboard alone. Not affiliated with DHH, 37signals, or the Omarchy project.
