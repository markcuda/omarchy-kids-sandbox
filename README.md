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

## Status: design settled, spec next

Renamed from `omarchy-kids-setup` on 2026-09-02. **The scripts here predate the decisions** and
will be reshaped, not extended. The spec is **[SPEC.md](SPEC.md)**; the work is
[32 issues in six milestones](https://github.com/markcuda/omarchy-kids-sandbox/milestones), in
build order. Milestone 0 is six facts to verify on a real 4.0.x install before anything depends on
them; those are the best first contribution and need nothing but a VM or an old laptop.

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
| `bin/omarchy-kids-wizard` | Pre-decision skeleton: five screens, dry-run by default |
| `bin/omarchy-kids-check` | Green/red self-test, still the right shape |
| `lib/provision.sh` | Kid account, DNS, browser policy, boot hardening. The per-kid parts survive; the machine-wide DNS and Chromium policy do not (the parent is never restricted) |
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
