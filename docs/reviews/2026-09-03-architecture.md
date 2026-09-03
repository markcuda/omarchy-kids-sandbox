# Architecture review — 2026-09-03

Question from Mark: for something fast, smooth, secure, expandable, easy to configure and easy
to contribute to, keep the sandbox as is or rebuild? Answer: keep the stack (bash + gum, two small
Python root daemons, Quickshell surfaces, the SDDM QML portal, Lua Hyprland configs); rebuild the
*shape* of three things; deepen two more in place. No language rewrite: the deletion test says a
Rust or other rewrite of the daemons would move complexity, not concentrate it.

Vocabulary (the `codebase-design` skill): a **module** has an interface and an implementation; a
module is **deep** when a lot of behaviour sits behind a small interface; a **seam** is where an
interface lives; **leverage** is what callers get from depth, **locality** what maintainers get.
The friction walk in the appendix was done by Codex (gpt-5.6-luna); the candidates and ranking are
Claude's. Specs for each candidate live in `docs/specs/` (written by gpt-5.6-sol), tickets follow
from the specs, and Codex (luna) drafts the code.

## Candidates, in the order to do them

### 1. One root-written session manifest (strong)

Files: `bin/omarchy-kids-session-start`, `bin/omarchy-kids-session`, `share/launcher/shell.qml`,
`lib/assert-locks.sh`, `share/packs/*.toml`, and the new `lib/launcher-map.sh` from #60.

Problem: the login path crosses config, Python, desktop files, JSON, QML and Hyprland in one
kid-side script, and two of its inputs were things a kid could write (Codex review 1, 2; #59, #60).
Solution: root builds one manifest per kid at provision and assert time
(`/etc/omarchy-kids/sessions/<kid>.json`: level, theme, tiles with fixed argv arrays, allowlist,
web policy id, budget); every kid-side module reads it and nothing else. The #60 launcher map is
the first slice of this; the manifest absorbs it. Wins: the trust boundary lives in one root
module; one manifest, six surfaces; tests hit one interface (the file); login stops scanning.

### 2. Screen time enforced by root (strong; issue #62)

Files: `bin/omarchy-kids-time-ledger`, `bin/omarchy-kids-time`, `bin/omarchy-kids-exit`,
`share/time/timesup.qml`.

Problem: budget and lights-out are decided and enforced in the kid's own process; the root tick
only counts. Solution: the root ledger tick owns the decision and ends the session itself
(`omarchy-kids-exit --finish --kid` exists); the kid-side daemon becomes a display adapter that
warns. Wins: enforcement in one root module; a kid cannot kill what root runs; scenario 40 tests
the real seam.

### 3. One config schema, one profile read (strong)

Files: `bin/omarchy-kids-conf`, `share/bands/bands.toml`, `lib/wizard-advanced.sh`,
`lib/wizard-apply.sh`, `lib/panel-kid.sh`.

Problem: conf is the nominal seam but its schema is restated in the wizard, the panel and the
runtime; a new key is an eight-file change and one panel screen spawns the conf tool twelve
times. Solution: one schema file owns every key (type, default, band precedence, label, group,
editor); conf gains `profile <kid>` returning the effective settings once as JSON; wizard and
panel render from the schema. Wins: new key = one file; interface shrinks to get/set/profile;
screens draw in one spawn; validation in one place.

### 4. One kid shell instead of six Quickshell processes (strong)

Files: `share/launcher`, `share/exit-modal`, `share/ask`, `share/time`, `share/wifi`,
`share/plugins`, `bin/omarchy-kids-{time,ask,exit,super-tap,launcher-ctl}`.

Problem: every modal is its own Quickshell process with its own theme load, and the launcher polls
a control file every 150 ms; the felt cost is one to two seconds of nothing after Super ×3.
Solution: one long-running Quickshell shell per kid session hosts every surface as a layer;
commands ask it over Quickshell's IPC instead of spawning it. The trust boundary is unchanged:
root decides, the shell shows. Wins: modals appear at once; one theme load; a new surface is one
QML file and one verb; polling gone; five copies of shell boilerplate deleted.

### 5. Locks as data (worth exploring)

Files: `lib/posture.sh`, `lib/assert-locks.sh`, `lib/check-locks.sh`, `bin/omarchy-kids-assert`,
`bin/omarchy-kids-remove`.

Problem: `check-locks.sh` fails the deletion test (it re-lists what `assert-locks.sh` knows); a
new lock touches six files. Solution: a lock is declared once with its check, fix and undo;
assert, check and remove loop over the table. Wins: new lock = one entry; one shallow module
deleted; fix and undo cannot drift.

### 6. A screen is one spec (worth exploring)

Files: `lib/tui.sh`, `lib/wizard-screens.sh`, `lib/panel-*.sh`.

Problem: the TUI's interface is nearly as wide as its implementation: nine positional arguments
per screen, two by name reference, and every flow re-learns the redraw rules. Solution: one screen
spec by name (title, body, choices, default, footer, validator); the module keeps redraw, gum,
validation, keys and error modes inside. Wins: interface shrinks to one call; wizard and panel
read as data; redraw rules in one place.

### 7. Keep: the languages and the daemons

`bin/omarchy-kids-authd`, `bin/omarchy-kids-wifid`, `share/sddm-theme`, `share/hyprland/*.lua`,
bash + gum everywhere. No friction found; one adapter each, so no seam to justify; maintainers
read bash and Lua; the speed problems are in candidate 4.

## Appendix: the friction walk (Codex, gpt-5.6-luna, read-only, main @ 5fb7b71)

# FRICTION audit

Read-only audit after AGENTS.md, SPEC.md, docs/style.md, and docs/reviews/*.md. “Depth” below means behavior per unit of interface; “locality” means how much change and verification stay in one place.

## (a) Concept bouncing

- `bin/omarchy-kids-conf:29-42,95-224`, `lib/wizard-advanced.sh:9-55,343-384`, `lib/wizard-apply.sh:41-55`, `lib/panel-kid.sh:273-352`; one setting is represented by key arrays, validators, precedence, wizard maps, Apply overrides, and panel dispatch. Cost: understanding one config concept requires learning several small seams, reducing depth and locality.

- `bin/omarchy-kids-session:98-238`, `bin/omarchy-kids-session-start:67-253`, `share/hyprland/L1.lua:150-170`, `share/launcher/shell.qml:167-183`; session startup is split between preflight, tile generation, Hyprland level selection, and QML launch behavior. Cost: failures can sit in ordering or handoff rather than in the module that appears to own login.

- `bin/omarchy-kids-provision:169-226`, `lib/provision-add.sh`, `lib/provision-remove.sh`, `bin/omarchy-kids-remove:222-496`; account creation and account removal distribute lifecycle behavior across dispatchers, add/remove libraries, posture writers, and duplicated presence checks. Cost: the lifecycle has weak locality and contributors must reconstruct ordering from several implementations.

- `bin/omarchy-kids-ask:331-462,466-563`, `lib/ask.py`, `share/ask/shell.qml:78-151`, `bin/omarchy-kids-authd`; a request travels through kid-side QML, an outbox, collection, authentication, action application, and queue decision state. Cost: the interface includes timing, ownership, privilege, and eventual consistency that no single module exposes completely.

## (b) Shallow modules

- `lib/check-locks.sh:9-66`; this module mostly enumerates `*_ok` calls already supplied by `lib/assert-locks.sh` and translates them through `lock_check`. Cost: deleting it would move the list into `bin/omarchy-kids-check` without concentrating new behavior, so the seam adds indirection with little depth.

- `lib/wizard-advanced.sh:11-55,343-384`; key-to-variable, key-to-group, key-to-label, and key-to-editor mappings repeat the same taxonomy in separate case statements. Cost: the interface is nearly the mapping implementation, so adding or renaming a setting has poor locality.

- `bin/omarchy-kids-remove:23-29,501-519`; the command exposes `REAL_DRY_RUN` and `DRY_RUN`, always performs a preview pass, then conditionally asks for confirmation and performs a second pass. Cost: the deletion test does not remove complexity, but the public interface is shallow because callers must understand internal execution phases and two dry-run states.

## (c) Pure functions versus call choreography

- `share/launcher/gridnav.js:34-65`, `test/shell.d/launcher-grid-test.sh:134-169`, `bin/omarchy-kids-session-start:77-131`, `share/launcher/shell.qml:167-183`; navigation math is isolated and tested while desktop-file heuristics, generated command strings, QML process startup, and installed-state behavior remain outside that test seam. Cost: the pure module has good depth, but the bugs most likely to affect launching live in the untested choreography around it.

- `lib/time.py:34-50`, `test/shell.d/time-test.sh:134-185`, `bin/omarchy-kids-time:97-190`; logical-day and threshold decisions are directly exercised while overlay spawning, pidfile lifetime, grant dismissal, and the daemon sleep loop are separate. Cost: the time engine can pass while the kid-facing state machine still fails to show, dismiss, or finish a surface correctly.

## (d) Leaking seams

- `bin/omarchy-kids-session-start:173-211`, `share/launcher/shell.qml:167-183`; bash writes an `exec` string into launcher JSON and QML executes it with `["sh", "-c", tile.exec]`. Cost: the bash-to-QML seam carries shell syntax, environment setup, and process policy instead of a narrow launch contract.

- `bin/omarchy-kids-session:168-205`; the kid session check uses `$HOME`, downgrades missing `/tmp` noexec to a warning, and checks only `getty@tty2.service` while the assert path checks tty2 through tty6. Cost: session identity, enforcement severity, and lock coverage diverge across the root-side and kid-side seams.

- `bin/omarchy-kids-session-start:223-235`, `share/menu/omarchy-kids-trimmed.jsonc:1-28`; Level 2 writes an allowlist but starts `/usr/bin/omarchy-launch-shell`, while the menu file declares an explicitly unverified schema and has no runtime reader here. Cost: configuration claims a menu mode whose enforcement seam is partly inert and partly delegated to an unverified external format.

- `bin/omarchy-kids-ask:492-523,531-563`; the list, approve, and decline paths are described as root-side but have no visible `is_root` gate, unlike `cmd_apply_grant:441-449`. Cost: the privilege boundary is implicit in filesystem permissions and caller convention rather than expressed at the command seam.

- `lib/assert-locks.sh:69-88`; the group lock checks required membership but does not reject extra supplementary groups. Cost: the root-owned lock’s invariant is weaker than the account policy implied by the interface, and the seam leaks unmodeled account state.

## (e) Untested or hard-to-test paths

- `test/shell.d/exit-test.sh:2-12`, `test/shell.d/ask-test.sh:1-12`; both suites explicitly leave their QML surfaces untested because Quickshell is unavailable. Cost: authentication, focus, modal closure, and action handoff are tested only through shell stubs or source inspection.

- `test/shell.d/portal-test.sh:78-157`, `test/shell.d/qml-theme-static-test.sh:57-110`; the SDDM and general QML checks balance text, grep for symbols, and reject literals without running a QML engine. Cost: syntax and intended wiring can pass while rendering, focus, imports, and runtime bindings fail.

- `test/live/all:15-40`, `test/shell.d/live-lib-test.sh:2-7`; the live scenarios are excluded from `test/all`, leaving only pure report and portal-index helpers in the ordinary suite. Cost: boot, portal, lights-out, ask, and removal behavior remain manual acceptance evidence rather than repeatable local verification.

- `test/shell.d/authd-test.sh:327-334`, `test/shell.d/wifi-test.sh:235-250`; critical password-daemon and SO_PEERCRED sections skip when host libraries or Linux socket features are absent. Cost: the Mac development run can report a green shell suite without exercising the security-sensitive live paths.

## (f) Runtime speed and smoothness

- `lib/tui.sh:192-224,311-350`, `bin/omarchy-kids-wizard:367-395`; each screen redraw clears the terminal, measures it, renders a card, and invokes gum, while the wizard drives fifteen screen states through a shell loop. Cost: backtracking and validation errors pay repeated terminal and process startup overhead.

- `bin/omarchy-kids-session-start:80-98,149-176`; each session scans application directories and desktop files, invokes the Python pack helper per allowlisted app, runs `command -v`, reads icons, and invokes jq repeatedly. Cost: login latency grows with both installed desktop entries and pack size.

- `share/launcher/shell.qml:130-145`; the launcher reloads its control file every 150 milliseconds and parses it on every timer tick. Cost: an idle launcher performs continual file polling instead of sleeping until an actual activation event.

- `bin/omarchy-kids-time:97-116,146-190`, `lib/theme.sh:55-68`; time overlays start separate Quickshell processes and the daemon sleeps between polls, while each command process independently probes `omarchy-theme-color` despite only caching within that process. Cost: cold starts and repeated polling are paid across time, panel, wizard, and modal flows.

- `test/live/lib.sh:97-117`, `test/live/50-ask-grant.sh:41-58`; the live harness waits a fixed 35 seconds for boot, then polls SSH and grant state in five-second intervals. Cost: feedback is slow and failures can take minutes before the harness distinguishes a dead surface from a delayed VM.

## (g) Files to touch for common additions

- One new app entry in an existing band pack is a five-file change: `share/packs/<band>.toml`, `docs/apps.md:119-147`, `test/shell.d/apps-test.sh:146-160`, `test/shell.d/conf-test.sh:120-122`, and `test/shell.d/session-start-test.sh:148-168`. Cost: data, documentation, fallback resolution, allowlist order, and launcher behavior all pin the same pack contents independently.

- One new panel screen is three files minimum: `lib/panel-kid.sh:421-496` or another panel library, `test/shell.d/panel-test.sh`, and `docs/panel.md`; a new panel group also touches `bin/omarchy-kids-panel:220-227`. Cost: the screen’s row, dispatch, verification, and documentation are not co-located.

- One new lock is typically six files: `lib/posture.sh`, `lib/assert-locks.sh:1-104`, `bin/omarchy-kids-assert:135-192`, `lib/check-locks.sh:9-66`, `test/shell.d/assert-test.sh`, and `test/shell.d/check-test.sh`, with the lock table in `docs/assert.md:49-71`. Cost: assertion, repair, reporting, tests, and rationale must stay synchronized across separate seams.

- One tile-launched QML surface is five files: `share/<surface>/shell.qml`, `PKGBUILD:82-86`, `bin/omarchy-kids-session-start:193-211`, the relevant shell test such as `test/shell.d/session-start-test.sh`, and its feature documentation. Cost: even though the static theme test auto-discovers QML, packaging, launch construction, runtime behavior, and evidence are separate edits.

- One config key with wizard, panel, and runtime behavior is roughly eight files: `bin/omarchy-kids-conf:29-42,95-165`, `share/bands/bands.toml`, `lib/wizard-advanced.sh:9-55,343-384`, `lib/wizard-apply.sh:41-55`, `lib/panel-kid.sh`, the consuming command, its test, and `docs/conf.md:44-67`. Cost: the key’s signature, default, validation, UI, persistence, consumer semantics, and proof are distributed rather than deep behind one interface.

## Five modules that most deserve deepening

1. `bin/omarchy-kids-session-start`, because it crosses config, Python, desktop files, JSON, QML, and Hyprland in one login path.

2. `bin/omarchy-kids-conf`, because it is the nominal configuration boundary while its schema is repeated in wizard, panel, data, and runtime callers.

3. `lib/tui.sh`, because every interactive flow depends on a large positional interface with redraw, gum, validation, keyboard, and error-mode behavior.

4. `lib/posture.sh`, because it owns many root-side seams whose correctness is later reinterpreted by assert, check, remove, SDDM, PAM, and filesystem code.

5. `bin/omarchy-kids-time`, because its pure calculations are well isolated but its daemon, overlay, pidfile, grant, and sleep choreography carries the user-visible failure modes.