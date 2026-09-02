# Working in omarchy-kids-sandbox

Read this, then `SPEC.md`, before touching anything. The spec is the source of truth; issues
reference its requirement ids (`R-WEB-3`). If a ticket and the spec disagree, the spec wins and
the ticket gets a comment.

## What this is

The sandbox path of Omarchy Kids Mode: an app on a normal Omarchy install. One real Unix account
per kid, the parent never restricted, one parent password. Hub and decisions:
<https://github.com/markcuda/omarchy-kids-mode> (`PATH-SANDBOX.md`).

## Rules that override everything

1. **The parent's account is never restricted** (spec I-1). If your change touches the parent's
   session, home, browser, or DNS, stop.
2. **Nothing about a child leaves the machine** (I-2). No network calls from anything but the
   package manager and the DoH template inside the kids browser policy.
3. **Locks are root-owned and live outside every home** (I-3). Never make a plugin, a dotfile, or
   anything user-writable responsible for enforcement.
4. **Fail closed at kid login, fail safe in early boot** (I-4, I-9).
5. **Keyboard-complete** (I-5). Every screen you build must work with no pointer.
6. **Honest UI** (I-6). Do not ship a control that is not enforced. Label fences as fences.
7. **Core untouched** (I-7). Never edit a file owned by the `omarchy` or `omarchy-settings`
   packages. Use drop-ins, hooks, session entries, themes, policy folders, our package.
8. **Never run `--apply`, `provision`, or anything that writes under `/etc` on a development
   machine.** Dry-run is the default everywhere; real runs happen on the test laptop or in a VM.
9. **Nothing about a real child.** No names, ages, photos, or transcripts in code, tests, docs,
   fixtures, or commit messages. Fixtures use `kid-ada` with band `6-8` and nothing else.

## Layout

| Path | What goes there |
| --- | --- |
| `bin/omarchy-kids-*` | Commands (spec R-BUILD-4). One file per command, bash, `set -euo pipefail`, `DRY_RUN=1` default where it writes |
| `lib/*.sh` | Shared shell: settings helpers (vendored from upstream's `install/helpers/parent.sh`), the `run` dry-run wrapper, logging |
| `share/bands/bands.toml`, `share/packs/<band>.toml` | Data (Appendix C) |
| `share/hyprland/L{1,2,3}.lua`, `share/hyprland/band-*.lua` | Root-owned level configs and band overlays (Appendix E) |
| `share/tui/screens/*.toml`, `lib/tui.sh` | Screens as data, one renderer (R-WIZ-9, Appendix A) |
| `share/policy/*.json` | Chromium policy templates (R-WEB-2, R-WEB-3) |
| `share/avatars/*.svg` | Twelve CC0 animals (Q18) |
| `share/menu/*.jsonc` | Trimmed-menu extension for Levels 1 and 2 (R-DESK-4) |
| `share/sddm-theme/` | The portal (R-LOGIN) |
| `initcpio/` | The early-boot hook and its install script (R-BOOT) |
| `systemd/` | Units and timers |
| `polkit/`, `sudoers/` | Drop-ins written by `omarchy-kids-provision` and `omarchy-kids-assert` (kept as templates here) |
| `test/shell.d/*-test.sh` | One test file per command, Omarchy's `test/shell.d` style; `test/all` runs them |
| `test/acceptance.d/` | VM-only tests (spec §8) |
| `docs/phase1/V*.md` | Results of the Phase 1 checks, one file each |
| `PKGBUILD` | The package; file paths in spec §5.1 |

## How to work

- Pick an issue in milestone order. Read its spec ids. Post a one-line plan on the issue before
  a large change.
- Shell: bash 5, `shellcheck` clean, quoted heredocs for anything root writes, passwords only
  ever on stdin, never argv, never logged.
- Every command supports `--help` and, where it writes, `DRY_RUN=1` (default) printing the plan.
- Tests before merge: `test/all`. Tests that need root use `unshare --user --map-root-user` when
  available and skip otherwise, as upstream does.
- Match Omarchy's look and idiom: gum, the installer's header, Esc back, Ctrl+C leave, the
  0/1/130 status contract from upstream's `install/provisioning/setup-form.sh`.
- Commit messages: what and why, one topic per commit. AI-assisted work is welcome; say so in
  the PR, and a human reads every line.
- Anything a kid could use to get around a lock is a security issue: report it privately per the
  hub's `SECURITY.md`, not in a public issue.

## Test machines

The test laptop (2019 MacBook Air, T2) is reached over Tailscale SSH; see
`docs/laptop-runbook.md`. Boot-level checks (disk prompt, portal, two sessions, the early-boot
hook) run in QEMU on that laptop, never on its real disk. Real-hardware checks (Wi-Fi, captive
portals, firmware) run on the laptop itself.
