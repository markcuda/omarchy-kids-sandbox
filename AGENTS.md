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
   machine.** Real runs happen on the test laptop or in a VM. `DRY_RUN=1` is the default for
   every non-interactive command — `provision`, `assert`, `web`, `apps`, `remove` — and for every
   non-interactive *caller*. The two interactive commands are the exception: `omarchy-kids`,
   `omarchy-kids-panel` and `omarchy-kids-wizard` default to a **real** run when a human is
   driving them (a tty, or `desktop/omarchy-kids.desktop`, which sets `OMARCHY_KIDS_LAUNCHED_BY`),
   because the screen the parent confirms is the confirmation. With no tty — a test, a script,
   CI — they still default to `DRY_RUN=1`, and `--dry-run` always forces the preview.
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
| `share/qml/KidsTheme.qml`, `lib/theme.sh` | Per-theme colors/font, one resolver for QML and one for shell (docs/theming.md) |
| `initcpio/` | The early-boot hook and its install script (R-BOOT) |
| `systemd/` | Units and timers |
| `polkit/`, `sudoers/` | Drop-ins written by `omarchy-kids-provision` and `omarchy-kids-assert` (kept as templates here) |
| `test/shell.d/*-test.sh` | One test file per command, Omarchy's `test/shell.d` style; `test/all` runs them |
| `test/acceptance.d/` | VM-only tests (spec §8) |
| `docs/phase1/V*.md` | Results of the Phase 1 checks, one file each |
| `PKGBUILD`, `omarchy-kids.install` | The package and its post_install/post_upgrade/post_remove scriptlet; file paths in spec §5.1, walked in `docs/packaging.md` |
| `pacman/omarchy-kids.hook` | Template for `/usr/share/libalpm/hooks/omarchy-kids.hook`, the re-assert hook (R-TRUST-5) |
| `desktop/*.desktop` | Templates for the app entry and the kid Wayland session entry (R-FND-1, R-DESK-1) |

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

## Conventions

Match omacom/omarchy's own style, not just its tools. Full citations and gaps:
`docs/style.md`.

- Put `# omarchy:summary=<one line>` (and `# omarchy:args=`, `# omarchy:examples=` where useful)
  directly under the shebang of every `bin/omarchy-kids-*` command, before any prose.
- Shebang is always `#!/bin/bash`, never `#!/usr/bin/env bash`. Every command in `bin/` uses
  `set -euo pipefail` — no exceptions without a one-line note in that file's own header saying
  why (e.g. it `exec`s into another binary at every exit path).
- Comment density: explain the *why* in one line, not the *how* in paragraphs. A file-level
  rationale block belongs once, at the top of a shared `lib/*.sh`/`.lua`/`.qml` file (setup-form.sh-
  length is the ceiling); an individual command or function gets 0-2 lines, not an essay. Move
  mechanics, sourcing audits, and "confirmed vs. unverified" trails into that command's
  `docs/<command>.md` — leave one pointer comment in the source instead.
- Naming: hyphenated `omarchy-kids-*` commands, `lower_snake_case` functions and locals,
  `UPPER_SNAKE_CASE` constants. Keep any future purpose-prefix taxonomy (`refresh-`, `toggle-`,
  etc.) in exactly one table — never a second list that can drift.
- User-facing prompts: terse, concrete, second person implied. One accent color per screen,
  resolved from `omarchy-theme-color` (see `lib/tui.sh`), never a fresh hardcoded hex per caller.
- Root handling: no script re-derives its own `EUID`-or-`sudo` check. Share one `as_root`/
  `require_root` helper (add `lib/root.sh` if one doesn't exist yet) the way upstream's
  `install/helpers/as-root.sh` does.
- Config locations: locks stay root-owned under `/etc/omarchy-kids/` per spec rule I-3 — this is
  a deliberate inversion of upstream's `~/.config/omarchy/`, not a gap to "fix" by moving state
  into a home directory.
- Theme colour: QML never hardcodes a hex or `Qt.rgba(...)` literal for anything themeable — pull
  from `qs.Commons`' `Style`/`Color` singletons or an injected `bar.foreground`, the way
  `shell/Ui/BarWidget.qml` and `shell/plugins/panels/clock/BarWidget.qml` do upstream.
- Lua and QML: two-space indent, `lowerCamelCase` QML ids/functions, `lower_snake_case` Lua
  locals promoted onto a shared table (`o.foo = foo`).
- Tests: one `test/shell.d/<command>-test.sh` per command, opening with the SPEC.md requirement
  ids it covers, the same discipline upstream expects. VM-only checks stay in `test/acceptance.d/`.

## Test machines

The test laptop (2019 MacBook Air, T2) is reached over Tailscale SSH; see
`docs/laptop-runbook.md`. Boot-level checks (disk prompt, portal, two sessions, the early-boot
hook) run in QEMU on that laptop, never on its real disk. Real-hardware checks (Wi-Fi, captive
portals, firmware) run on the laptop itself.
