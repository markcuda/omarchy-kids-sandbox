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

### Known gaps

See `docs/phase1/DECISIONS-NEEDED.md` and `docs/phase1/BLOCKED.md` for what still needs a human
decision (Pause/fast-user-switch, the Limine snapshot default) or is blocked on real hardware
(Wi-Fi, captive portals, firmware password). Each command's own doc has a "Verified live" section
naming exactly what has and hasn't run against real Hyprland/Quickshell/SDDM yet.
