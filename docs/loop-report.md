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

## Round two (after Mark's note)

Mark asked for DHH-grade code, Omarchy's own conventions and per-theme styling, and UX work
from screenshots. Done since:

- `docs/style.md` and a Conventions section in `AGENTS.md`, derived from omacom/omarchy v4.0.2.
- An antagonistic review (`docs/reviews/2026-09-03-antagonistic.md`) and its security fixes
  (#51): approvals are root's decision, verifier paths are absolute and ignore the kid's
  environment, the Limine editor lock no longer hides behind the boot hook, secrets never reach
  a preview, the interactive commands run for real, boot-login uses the profile registry. A
  live attack pass confirmed the forged-approval and socket-redirect paths are closed; the real
  on-the-spot grant needed two more fixes found live (a minutes field and the verifier's line
  reader) plus writable state paths in the service unit.
- Theme plumbing (#47): the portal and the wizard follow the owner's theme, verified under
  tokyo-night and catppuccin-latte; kid surfaces use the kid's own theme (#53 inherits the
  parent's at provision time).
- Starter packs audited against the official repos (#52) and installed for real; GCompris
  launched from the launcher.
- Launcher with real app icons and a centred grid (#54); the wizard as one rounded card per
  step in the theme's colours (#50); uninstalled tiles hidden (#42); grid navigation fixed (#43).
- The live harness ran all seven scenarios green in one run after these merges.
- The structural refactor (#49) merged and passed the full live harness; the second
  antagonistic review (`docs/reviews/2026-09-03-antagonistic-round-two.md`) found that it had
  re-created the same class of hole it closed (an environment variable selecting which library
  loads, even for the PAM-wired verifier), plus an arithmetic injection and a root read that
  follows a kid's symlink. Its verdict: not mergeable upstream until one trust boundary is
  stated and enforced by a test, the authorization tests run on Linux instead of skipping, and
  no unenforced control ships. All of that landed as #58: one trust boundary stated in
  `AGENTS.md`, every environment override gone (including the one the PAM verifier read), a
  static test that walks `bin/` and `lib/` and fails on a new one, root reads with
  `O_NOFOLLOW`, and the Wi-Fi portal window removed rather than shipped unenforced.
- Light themes fixed in every standalone Quickshell surface (#57); the style follow-ups (#56)
  cut comments in `bin/` and `lib/` from 18% to 12% of lines, renamed `ask-grownup` to
  `omarchy-kids-blocked`, and moved the TUI demo out of the package.
- The live harness gained scenario 05, which copies the checkout to the VM and runs the unit
  suite there. Run 5: the seven behaviour scenarios green, and scenario 05 found the real gap of
  the night: 61 checks in 16 test files fail on Arch. The suite had only ever run on the Mac and
  assumed a host with no Omarchy tools on PATH, no package installed, and BSD `stat`. Nothing in
  the product broke; the tests did. Fixing that on branch `vmtests`, with a new rule in
  `AGENTS.md`: the suite must be green on an Omarchy box with the package installed, and
  scenario 05 is the gate.
- A third review is reading the repo with a maintainer's eye (taste and conventions, not
  security); its notes will be `docs/reviews/2026-09-03-maintainer-eye.md`.

## Round three (the morning after)

- The unit suite now runs on the VM as live scenario 05, and it is the gate: 61 checks in 16
  files had only ever passed on the Mac (BSD `stat`, tools assumed absent from `PATH`, the
  package assumed uninstalled). `test/shell.d/lib.sh` gives every test one portable `stat` and
  a sealed `PATH`. The same run found four real Linux-only bugs: `check --live` aborted on
  `pkcheck`'s non-zero "not authorized", `omarchy-kids-wifi` died silently when `socat` found
  no socket, an account without `colors.toml` got a black parent tile on the portal, and
  `kids_bin`'s `/usr/bin` fallback made "not installed yet" untestable on an installed box.
- A maintainer-eye review (`docs/reviews/2026-09-03-maintainer-eye.md`, taste and conventions
  rather than security) found 33 things; about 30 are applied. The visible ones: every panel
  screen now shows its facts inside the card instead of echoing them above a menu that cleared
  the screen (verified by screenshot under tokyo-night and catppuccin-latte); Time's Up's
  "Ask a grown-up" opens the real ask modal; a wrong parent password shows on the redrawn card;
  Omy's welcome is two sentences; the PKGBUILD reads like code with its reasoning in
  `docs/packaging.md`; one `account_home`, one `is_in`, no `TIME_CONF_BIN` handshake, no
  `PY` aliases, `apps list --json` instead of parsing a table by column offset.
- Harness run 6 after all of that: six of eight scenarios green in one run; the two failures
  were SSH timeouts through the laptop, and both scenarios passed on their own straight after.
- Afternoon finds, all from screenshots and the fresh-greeter probes, all fixed and verified on
  the VM: the greeter's Left and Right died after a password field had been opened and closed
  once (focus stayed on the hidden field; a parent could not arrow from a kid's tile to their
  own); the harness's "session is live" check counted its own SSH login, so scenario 20 had
  been passing while the screen showed the portal; and behind that, the real V7 gap: nothing
  ever recorded the parent's LUKS slot, so a boot unlocked with the parent's disk password
  landed on the portal instead of the parent's desktop. `omarchy-kids-conf machine set parent`
  now writes the `0=<parent>` line, and a cold boot with the owner's password lands on the
  owner's desktop again.
- The kid session now starts Hyprland through `start-hyprland -- --config`, Hyprland's own
  watchdog launcher, which removes the red "started without start-hyprland" banner every kid
  saw at login. Arguments must follow `--`; without it the launcher drops the config, which is
  the kind of thing only a live run catches.
- Panel polish from the screenshots: no step counter on single screens, facts without the
  account prefix, an honest footer (`q` never quit), "lights-out at 19:30" instead of "next
  boundary: lights-out at 19:30", and a stronger scrim so the Time's Up card fades behind the
  Ask modal.
- Three harness lessons, each now a line of code: a session exists before its keybinds do (the
  Super taps must wait for the launcher), the owner's boot now autologs the owner so a portal
  reset must wait for that session before exiting it cleanly, and a kid whose daily budget
  earlier scenarios used up gets Time's Up at login, which swallows the exit keystrokes.
- Harness run 7, after all of that: all eight scenarios green in one run. Then the launcher,
  the exit modal, the Ask modal and Time's Up were screenshotted with catppuccin-latte as the
  kid's own theme: all four read well on light. Setting that theme under `sudo` had died on an
  unset variable left by a review refactor; fixed with a test that runs it unset.
- One more harness lesson: the exit modal preselects Finish while Pause has no mechanism (the
  honest-UI rule), and the scenario's extra Tab was moving the selection onto Pause, which the
  modal refuses. The launcher change was never at fault; scenario 30 passes with the launcher
  frame clean of the banner.
- README and the parent card were reread as a parent would: the Phase 1 status line still said
  V1 was in progress (it finished and failed, which is why Pause is not built), the card
  promised a fast user switch that does not exist, and two spec citations became plain words.
  Every other claim in both checked out against the code.
- Harness run 8 over the end-of-day main: all eight scenarios green again.
- The wizard's first six screens screenshotted under catppuccin-latte on the owner's desktop:
  themed and readable; two nits fixed from them (the input box no longer repeats the card's hint
  as its placeholder, and the avatar list no longer pages at ten rows).
- The portal follows the owner's theme: after switching the owner to catppuccin-latte and
  re-asserting, the greeter came up light with the theme's blue on the selected tile.
- From 17:00, at your request, Codex (gpt-5.6-luna, high) writes the first draft of every
  ticket, headless from the shell in its own clone; I brief, gate and merge. Its first two jobs:
  an AUR-maintainer pass over `docs/install.md` and `docs/packaging.md` (merged after checking
  every claim it wrote against the files) and a maintainer review of main (running).
- Codex's review (`docs/reviews/2026-09-03-codex-maintainer.md`) would not bless the repo yet:
  16 findings, ten high. The real ones: the kid-facing launchers still read path prefixes from
  the environment (the same class round two closed for the verifier, allowed through as "scratch
  tree" variables), the launcher runs a kid-writable exec string through a shell, screen time
  is enforced from the kid's own process, and the group assert accepts a kid who is also in
  wheel. Filed as #59 to #63; Codex is drafting #59 and #60 now, #61 rides with #59, #62 next.
- Architecture review (`docs/reviews/2026-09-03-architecture.md`): keep the stack, rebuild three
  shapes (a root-written session manifest, root-enforced screen time, one config schema), then one
  kid shell for the speed you can feel, and two deepenings in place. Per your direction the
  pipeline from here is: gpt-5.6-sol writes a spec per candidate in `docs/specs/` with a ticket
  breakdown, the tickets are filed, gpt-5.6-luna drafts each one, I gate and merge.
- Six specs are in `docs/specs/` (written by gpt-5.6-sol, checked against the code), and their
  24 tickets are issues #64 to #87, four per spec, in order. Codex is drafting #64, the session
  manifest builder. Codex's launcher fix (#60) merged after both suites; its first cold boot
  showed an empty launcher because the boot-time assert runs with no HOME and the builder wrote
  an empty map silently; fixed the same hour with two rules that now have tests: root-side
  builders never replace state on failure, and root paths are exercised with an empty
  environment.
- Codex's fixes for its own review are in: #60 (root-owned launcher map, no shell evaluation),
  #59 (no environment-selected paths in any kid-facing command, absolute Quickshell, the home
  from getent, /tmp and /dev/shm fail closed, all six gettys masked) and #61 (exact group
  allowlist, root checks at the entry of ask's root verbs). Each was gated on both suites and
  the live login scenario; #59 needed two rebases and one Linux-only test fix on the way.
  Spec 01's first ticket (#64, the session manifest builder) is the first spec-driven merge.
- Spec-driven merges so far, each drafted by Codex and gated on both suites: #64 and #65 (the
  session manifest builder and the kid's own validated read of it), #68 and #69 (the root ledger
  tick now decides budget and lights-out from root-owned data and ends the session itself; the
  kid-side overlay only warns). #66 (session startup reads one manifest, no scans, no runtime
  exec strings: session-start went from 253 lines to 108) passed both suites, was merged, and
  was reverted the same hour: nothing built the manifest on a provisioned machine yet, so a kid
  got a black screen, and scenario 10 had passed because it only checked that the session was
  live. Two rules came out of it and are now code: a consumer never merges before its producer
  is wired, and a live scenario asserts the launcher is running, not that a session exists.
  Ticket 4 re-lands it with the wiring.
- The community scan is done: `docs/research/2026-09-03-community-scan.md` reads the whole
  #omarchy-kids channel (64 messages, the design thread) and ten repos. Short version: nobody
  else has per-kid accounts, a login portal, browser policy or a live harness; two things are
  worth borrowing (a signed, single-use ask-a-parent protocol from omarchy-parentapproval, and
  the hardened root-helper shape from omarchy-clarity and omarchy-pisafe), one needs a written
  decision (our per-kid-account model against Pete's one-shared-account installer path, which is
  DHH's own spec). Filed as #88, #89, #90. Discord text stayed on the Mac.
- After midnight: #66 and #67 landed together (session startup reads one root-built manifest;
  assert and provision build it), and the first real boots found three root-only bugs that the
  Mac suite cannot see: the launcher map read a file mode's owner digit as the world bit and
  refused every root-owned 755 app, a kid without a theme of their own could not get a manifest,
  and a settings change made the next login fail closed on a stale manifest until the next
  assert. All three fixed with tests; `omarchy-kids-conf set` now rebuilds the manifest itself.
- The standing order and the definition of done are written down in `docs/GOAL.md`.
- Still open for you: the same list as before (#2 #4 #17 #26 #28 #32 #33, hub PR #3). One
  thing to know: an agent installed Homebrew bash 5.3 on the Mac without being asked; it is
  harmless and still there.

## What is open

- `#2` V1 and `#17` Pause: SDDM on 4.0.2 cannot open a second greeter; a design decision.
- `#4` V3: the captive-portal window needs a real captive portal to test.
- `#26` `#28` `#32` `#33`: real Wi-Fi hardware, a populated plugins catalog, the AUR upload and
  the upstream notes need the laptop or you.
- The greeter arrow-key focus question and the scenario-20 assertion (round three, above).

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
repo clone. After the real Remove run the wizard re-provisioned Cy for real and a cold boot with Cy's
password landed on the launcher again, which closes the cycle; the older kids' files are under
the owner's "Kids Mode" folder; the owner `kid-vm` is in `omarchy-parents` and has the bar widget enabled. The
scratchpad on the Mac holds only the driving scripts; every screenshot was deleted after viewing.

## 2026-09-04, small hours: the Air itself becomes the target

Mark's order at 03:30: no AUR upload, no hub PR; install on the Air itself, dogfood on real
hardware, spawn gpt-5.6-sol agents, best work. GOAL.md's definition of done changed to match.

- #70 (spec 02 ticket 3, the kid path is display only) merged after the VM gate passed twice;
  the first failure was a host-coupled conf test (it scanned the VM's real desktop entries), now
  isolated with `OMARCHY_KIDS_ROOT`. #71 is being drafted; #72 (config schema) is in a
  review loop: a sol maintainer review said FIX FIRST (package-owned schema path, band-derived
  dns/history sources, parent-theme source, strict schema validation, missing reject tests) and
  luna is fixing.
- First two walkthrough videos recorded on the VM from QMP frames: the kid's day (delivered)
  and the parent's setup (not delivered yet: the take ran while the VM was busy with the unit
  gate, so gum screens rendered late and one keystroke landed on the wrong screen; the apply
  step then showed a sudo prompt in the terminal). Re-recording on an idle VM before judging.
- sol wrote the Air install plan and its verdict is the important finding of the night: the
  package's disk path (LUKS slot per kid, initramfs hook, UKI rebuild, Limine entry, run from
  assert on every pacman transaction once a kid exists) is a boot risk on an encrypted laptop
  whose passphrase nobody will type for us, and the boot-login unit forces the portal by
  writing an empty `User=` when no slot is recorded, contrary to its own comment. There is no
  supported way to run Kids Mode without the disk path.
- Decision (mine, under Mark's "I trust you fully"): make a portal-only boot mode first class
  instead of hand-quarantining units on the Air. sol is writing docs/specs/07-boot-mode.md: a
  root-owned `boot=disk|portal` machine setting, read by provision, assert, boot-login, remove and
  the pacman hook, chosen by the wizard from detection and overridable; it also fixes the
  boot-login bug, the wizard's passwordless-sudo password check (accepts anything), and the
  apply step's second prompt. The Air install follows spec 07's first tickets, in portal mode.
