# Changelog

Seeded from `git log`'s merge commits, one entry per merged issue branch, in build order.
There has been no tagged release yet, so everything below sits under `[Unreleased]` — see
`docs/packaging.md`'s "AUR readiness" section for the `pkgver` scheme this will start following
once there is one. Regenerate or extend this by hand; it is not produced by a script.

## [Unreleased]

### Added

- Package skeleton: `PKGBUILD`, `omarchy-kids.install`, the pacman hook, desktop entries, command
  stubs (#8)
- `omarchy-kids-conf`, `bands.toml`, and the starter packs (#9)
- `omarchy-kids-provision add/remove/list` with the posture writers (#10)
- `omarchy-kids-session`: the launcher with fail-closed checks, ask-grownup placeholder (#11)
- `omarchy-kids-assert`: re-asserts every lock; the boot-time unit (#12)
- Level 1/2/3 Hyprland configs, band overlays, the Level 1 launcher, `session-start` (#13)
- The login portal: SDDM greeter theme with face tiles (#14)
- `lib/tui.sh`: the screens-as-data `gum` renderer shared by the wizard and panel (#18)
- The parent wizard's Easy path, then reworked screen by screen against SPEC.md Appendix A (#19)
- The wizard's Advanced path: a grouped checklist over every Appendix B cell (#20)
- The parent panel: Home, Kid, and Requests screens; the Remove row hands off to
  `omarchy-kids-remove` (#21)
- Web: per-band Chromium policy, starter allow lists, fail-closed web tile (#22)
- The screen-time engine: root ledger, kid-side daemon, budget/lights-out warnings (#23)
- Apps: starter-pack installs, launcher allowlist, hide-from-mine (#24)
- "Ask a parent": the modal, the queue, `-ask-grownup` collect, panel verbs (#25)
- Wi-Fi for kids: `omarchy-kids-wifi` + `omarchy-kids-wifid` (#26)
- Remove Kids Mode: `omarchy-kids-remove` (#30)
- Early-boot LUKS-unlock hook and per-boot autologin, tested on Arch (#36)
- The parent-password verifier, `omarchy-kids-authd`/`-parent-auth`, tested on Arch (#35)
- The exit modal, parent-unlock PAM lines, the triple-Super-tap gesture (#16)
- Portal polish: display names, parent detection via `theme.conf.user`, avatars via
  `.face.icon` (#39)
- `assert`'s `limine-snapshots` lock, hiding pre-Kids-Mode Snapper boot entries (#38)

### Fixed

- `--apply` never crosses `sudo`; every command's own exit code drives the wizard/panel dashboard
  instead of assuming success
- The exit modal's parent-unlock check reads one line instead of waiting for EOF, which had left
  the verifier hanging
- `omarchy-kids-time`'s timer unit now names its ledger service, and the `units` assert lock
  starts sockets/timers on a live system rather than only enabling them
- `omarchy-provision-user` failing inside `omarchy-kids-provision add` is a warning with a
  migrations fallback, not a failed add (no offline Node tarball in the VM)

### Changed

- Time's Up's "Ask a grown-up" button opens the real R-ASK-1 modal (`omarchy-kids-ask time 15`);
  `omarchy-kids-time ask-grownup`, a placeholder that showed the "this desktop can't start safely"
  screen instead, is gone (2026-09-03 maintainer-eye review)
- `omarchy-kids-ask-grownup` is now `omarchy-kids-blocked`: the "ask a grown-up" screen a kid
  sees when a check refuses to start their session. `omarchy-kids-time ask-grownup` keeps its
  name; it is a different action (#56)
- `omarchy-kids-tui-demo` moved to `scripts/` and is no longer packaged (#56)
- Comments in `bin/` and `lib/` trimmed to one-line whys (18% -> 12% of lines); the mechanics
  and audit trails moved into the matching `docs/<command>.md` (#56)

### Security (round-two review, #58)

- **One trust boundary, enforced by a test.** No environment variable, and nothing a kid can
  write, selects which code runs or whether a root check happens. `$OMARCHY_KIDS_LIB` (read by all
  21 commands, including the `pam_exec` verifier — a kid could source their own `sock.sh` and
  unlock the screen with any password), every `*_BIN`/`*_PY` override, both socket paths, and the
  four `*_REQUIRE_ROOT` escapes are gone. `test/shell.d/trust-boundary-test.sh` walks `bin/` and
  `lib/` and fails on a new one; `AGENTS.md` rule 9 states the rule.
- A kid-written `asked_at` no longer reaches bash arithmetic in the parent's panel: `lib/ask.py`
  validates it on both sides of the queue, and `lib/panel-requests.sh` refuses a non-integer.
- Root no longer follows a kid-controlled path: `lib/data.py`'s `fold-launches` opens the kid's
  runtime log `O_NOFOLLOW` and checks the open descriptor (regular file, owned by that kid), and
  the root-owned `launches.log` is 0640 root:`omarchy-parents`, not world-readable.
- `lib/posture.sh`'s name guard aborts the write and reports FAIL instead of silently installing
  an empty polkit admin rule (which made every admin action ask for *root*'s password).
- `omarchy-kids-time` tracks its overlays by pidfile, not `pgrep -f`, so a kid cannot wedge
  lights-out shut with a decoy process.
- `omarchy-kids-wifid` applies R-WIFI-2's DNS lockdown *before* activating a connection, validates
  the SSID and password, puts `--` before every client value, and deletes the profile on any
  failure. `omarchy-kids-wifi portal` is removed: a kid could never have run it.
- `omarchy-kids-authd` caps concurrent client threads, so a kid cannot loop connections until the
  verifier dies.
- `README.md`'s "What works today" now says which of those controls are advisory (lights-out for
  bands with a terminal; the exit modal's password), and `test/live/05-unit-tests-on-vm.sh` runs
  `test/all` on the VM so the password-verifier and SO_PEERCRED tests actually execute.

### Known gaps

See `docs/phase1/DECISIONS-NEEDED.md` and `docs/phase1/BLOCKED.md` for what still needs a human
decision (Pause/fast-user-switch, the Limine snapshot default) or is blocked on real hardware
(Wi-Fi, captive portals, firmware password). Each command's own doc has a "Verified live" section
naming exactly what has and hasn't run against real Hyprland/Quickshell/SDDM yet.
