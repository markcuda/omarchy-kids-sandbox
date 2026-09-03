# The exit modal: Super+Shift+K, the triple-tap, and Pause/Finish (SPEC.md R-EXIT-1..6, I-5, I-6)

Every Kids Mode Hyprland level (`share/hyprland/L1.lua`, `L2.lua`, `L3.lua`) binds
**Super+Shift+K** to `omarchy-kids-exit`, and R-EXIT-1 additionally asks for **Super pressed
three times within 1.5 seconds**. Both gestures are meant to open the same thing: a modal asking
for the parent's password, then either **Pause** or **Finish** the kid's session. This issue
builds the modal itself (`share/exit-modal/shell.qml`), the command it and the Hyprland binds
actually run (`bin/omarchy-kids-exit`, replacing its earlier stub), and the triple-tap counter
(`bin/omarchy-kids-super-tap`).

**Nothing here has run against a real Hyprland or Quickshell** — see "What's unverified" below
before trusting any of it in front of a kid.

## The pieces

| File | What it is |
| --- | --- |
| `share/exit-modal/shell.qml` | The modal itself: avatar, name, password field, Pause/Finish buttons |
| `bin/omarchy-kids-exit` | `--open` shows the modal; `--finish` and `--pause` are what the modal runs after the parent's password verifies |
| `bin/omarchy-kids-super-tap` | Counts Super-key releases; three within the window calls `omarchy-kids-exit` |
| `bin/omarchy-kids-parent-auth` / `omarchy-kids-authd` | The verifier the modal calls (R-SEC-2; already built, `docs/authd.md`) — this issue is a *caller* of it, not a reimplementation |

## The modal (R-EXIT-1)

A centered card: the kid's avatar and name, a password field (focused the instant the modal
appears, masked), and two buttons:

- **Pause `<name>`** — "`<Possessive>` apps stay open. You switch to your desktop."
- **Finish for `<name>`** — "Closes `<possessive>` apps. You switch to your desktop."

Pause is preselected (highlighted) per R-EXIT-1, but rendered **disabled**, its subline replaced
with "Coming soon", unless `OMARCHY_KIDS_PAUSE_AVAILABLE=1` is set in its environment — which
`bin/omarchy-kids-exit` never sets today (see "Why Pause is disabled" below). This is I-6, not an
oversight: the button exists so the layout and the parent's mental model ("there will be two
choices here eventually") are right, but nothing about it claims to work until it actually does.

Keyboard (I-5, keyboard-complete):

- **Tab** / **Shift+Tab** toggles which button is highlighted (Pause is still selectable, just
  not activatable, while it's disabled — pressing Enter on it explains why instead of doing
  nothing silently).
- **Enter** submits: verifies the typed password, then runs whichever action is highlighted.
- **Esc** closes the modal with no side effects.
- Three wrong passwords in a row disable the password field for 30 seconds (a client-side pacing
  layer on top of `omarchy-kids-authd`'s own, stricter lockout — `docs/authd.md`'s "the modal is
  a second line of defense, not the first"). A wrong password also shakes the card and clears the
  field.

Verification never happens in the modal itself: it runs `omarchy-kids-parent-auth` (a `Process`
with the typed password piped to its stdin, one line, then EOF) and reads its exit code — 0 is
"a parent typed their password", 1 is anything else, exactly the same contract
`/etc/pam.d/omarchy-lock-password`'s `pam_exec` line uses (R-SEC-2, `docs/authd.md`). The
password is never logged: not to a file, not to the console, not left in a QML property any
longer than the one verification call needs it for.

## `bin/omarchy-kids-exit`

```text
omarchy-kids-exit            # same as --open
omarchy-kids-exit --open     # show the modal (a no-op if one looks already up)
omarchy-kids-exit --finish   # end the kid's session (R-EXIT-3) -- run by the modal, not a kid
omarchy-kids-exit --pause    # not implemented; prints why and exits 2
```text

`--open` execs `quickshell -p $OMARCHY_KIDS_SHARE/exit-modal/shell.qml`, first exporting
`OMARCHY_KIDS_ACCOUNT`/`OMARCHY_KIDS_NAME`/`OMARCHY_KIDS_AVATAR` read from `omarchy-kids-conf`
(name and avatar id; the avatar id is turned into
`$OMARCHY_KIDS_SHARE/avatars/<id>.svg`, the same path shape
`lib/posture.sh`'s AccountsService writer uses). "Already up" is checked with
`pgrep -f "quickshell -p <path>"` — a best-effort process-table check, since `--open` `exec`s
into Quickshell and so can never itself stay alive to track "still running" the way a
non-exec'd command could.

`--finish` (R-EXIT-3) is `hyprctl dispatch exit` (best-effort — only if `hyprctl` is on `PATH`,
and its failure doesn't stop anything else) then
`loginctl terminate-session "$XDG_SESSION_ID"`, so SDDM returns to the greeter the same way a
normal logout would.

## `bin/omarchy-kids-super-tap`

Meant to run once per **Super key release** — bound via `o.bind("SUPER + SUPER_L", ..., { release
= true })` in all three level configs ("The triple-tap bind" above). Each run appends "now"
(milliseconds) to `$XDG_RUNTIME_DIR/omarchy-kids/super-taps`, drops entries older than 1.5s
(`OMARCHY_KIDS_SUPER_TAP_WINDOW_MS`), and — once three remain — clears the file and runs
`omarchy-kids-exit`, so the *next* three taps start counting fresh rather than firing on every
release once three have ever landed close together. `OMARCHY_KIDS_SUPER_TAP_NOW_MS` overrides
"now" for tests, so `test/shell.d/exit-test.sh` never needs to sleep for real time to pass.

## Why Pause is disabled (R-EXIT-3, `docs/phase1/V1.md`, `docs/phase1/DECISIONS-NEEDED.md`)

R-EXIT-3 assumed Pause = lock the kid's session (hyprlock) and switch to the greeter via SDDM's
`Seat.SwitchToGreeter()`. Phase 1's V1 check found that call **fails outright** on Omarchy 4.0.2's
SDDM (Wayland-greeter mode): a second greeter cannot open while a session already holds the seat
(`HELPER_TTY_ERROR`, "Jumping to VT 1", display removed) — and on real hardware, the failed
attempt also revoked the parent's keyboard/trackpad until a manual `udevadm` re-trigger. **Do not
call `SwitchToGreeter` for Pause.** `docs/phase1/DECISIONS-NEEDED.md` leaves the real fix — most
likely a root helper that starts the parent's own session on a spare VT directly through PAM,
without SDDM — as its own future ticket with its own Phase 1 check. Until that exists,
`omarchy-kids-exit --pause` refuses (exit 2, a message pointing at `V1.md`), and the modal never
sets `OMARCHY_KIDS_PAUSE_AVAILABLE=1`, so the button stays visibly, honestly disabled (I-6) rather
than doing something broken or silently doing nothing.

## The triple-tap bind

Both gestures are wired into `share/hyprland/L1.lua`, `L2.lua`, and `L3.lua` now: `Super+Shift+K`
as a direct `omarchy-kids-exit` bind, and the triple-tap as a `release`-triggered bind next to it:

```lua
o.bind("SUPER + SHIFT + K", "Kids Mode: parent", "omarchy-kids-exit")
o.bind("SUPER + SUPER_L", "Kids Mode: exit (tap Super three times)", "omarchy-kids-super-tap", { release = true })
```text

The release-bind form is real, not a guess: `/usr/share/omarchy/default/hypr/bindings/voxtype.lua`
ships `o.bind("F9", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })`,
confirming `o.bind` takes a `{ release = true }` option, and Hyprland 0.56.2's Lua config engine
documents `release` alongside `ignore_mods`, `long_press`, `non_consuming`, `repeating`,
`separate`, and `transparent` as bind options. `SUPER_L` (the left-Super keysym) is what lets
`"SUPER + SUPER_L"` catch a bare Super tap at all, since Super is normally only the modifier half
of a combo. `bindr = SUPER, SUPER_L, exec, omarchy-kids-super-tap` is the Hyprland-native
(non-Lua) equivalent, for reference. `test/shell.d/levels-test.sh` greps for this bind in all
three level files; `bin/omarchy-kids-super-tap` itself is what does the counting/timing (its own
tests are in `test/shell.d/exit-test.sh`).

## What's unverified

Everything that touches a real Hyprland or Quickshell, since neither was available while writing
this (per the environment this was built in):

- **`share/exit-modal/shell.qml` end to end.** Its own header lists the specifics: whether
  `PanelWindow` + `WlrLayershell.layer: WlrLayer.Overlay` (from `Quickshell.Wayland`) is real API
  on the target Quickshell version, whether keyboard focus actually reaches the password field on
  a layer-shell surface with no explicit focus-grab property set, and — the one thing the whole
  verification flow depends on — whether `Quickshell.Io.Process`'s `stdinEnabled`/`write()`/EOF
  signaling exist with those names and actually deliver a clean EOF to
  `omarchy-kids-parent-auth`'s `cat -`. If `Quickshell.Wayland`/`PanelWindow` aren't available at
  all, the file's header has the exact fallback block (a plain fullscreen `Window`, matching
  `share/launcher/shell.qml`'s own choice) to swap in.
- **The triple-tap bind itself.** `Hyprland --verify-config` and the live modal in the VM are
  what actually confirm `{ release = true }` and `SUPER_L` behave as documented once run against
  a real Hyprland 0.56.2 — not run here.
- **`pgrep -f "quickshell -p <path>"` as "is the modal already open".** Untested against a real
  `quickshell -p ...` invocation's actual process listing.

## Testing in the VM

Once `share/exit-modal/`, the updated `bin/omarchy-kids-exit`, and `bin/omarchy-kids-super-tap`
are on the box (`docs/vm.md` has the SSH/VNC details):

1. SSH into the kid's session as the kid account (`ssh -p 2222 kid-ada@127.0.0.1` via the `vm`
   host, or whatever account is provisioned) — a plain SSH login has no Wayland/Hyprland
   environment of its own, so pull it from the live Hyprland process before running anything
   graphical:

   ```sh
   PID="$(pgrep -u "$(id -un)" -x Hyprland | head -1)"
   eval "$(tr '\0' '\n' < /proc/$PID/environ | grep -E '^(WAYLAND_DISPLAY|HYPRLAND_INSTANCE_SIGNATURE|XDG_RUNTIME_DIR)=' | sed 's/^/export /')"
   ```text

2. `omarchy-kids-exit --open` and confirm over VNC (`127.0.0.1:5905`, `scripts/vm-qmp.sh shot
   out.png` for a screenshot) that the modal actually appears **on top of** whatever the kid's
   desktop was already showing, centered, with the password field already focused (type
   immediately with no click needed).
3. Type the kid's own password, press Enter: should shake, clear, and show a hint — never
   succeed. Three wrong in a row: the field should visibly disable for 30 seconds.
4. Type the parent's real login password, with **Finish** highlighted (Tab once from the
   preselected Pause), press Enter: the kid's session should end and SDDM's greeter should
   reappear (R-EXIT-3).
5. Re-login as the kid, `omarchy-kids-exit --open` again, this time press Esc: confirm the modal
   closes with no other effect (still logged in, nothing changed).
6. Press Super+Shift+K from inside a running app (not the launcher) at each level and confirm the
   modal reaches the top — this is the scenario the layer-shell-vs-plain-Window choice in
   `share/exit-modal/shell.qml`'s header is actually about.
7. Tap bare Super three times within 1.5 seconds and confirm the modal opens the same way
   Super+Shift+K does. `Hyprland --verify-config` against each level file, and this live check,
   are what actually confirm `{ release = true }` + `SUPER_L` behave as documented — not run here.
   `omarchy-kids-super-tap` can also be exercised directly, without Hyprland at all:
   `omarchy-kids-super-tap; omarchy-kids-super-tap; omarchy-kids-super-tap` run three times within
   1.5 seconds should call `omarchy-kids-exit` the same way.

## Verified live (2026-09-02, QEMU test VM)

From the portal: Left to Cy's tile, Enter, kid password, the Level 1 launcher. Three taps of
Super within 1.5 s (the `{ release = true }` bind in every level config) opened the modal as a
Quickshell overlay: fox avatar, the kid's name, a focused password field, Pause greyed as
"coming soon", Finish. Parent password, Tab to Finish, Enter: the verifier said yes, Hyprland
exited cleanly, and SDDM started a new greeter with the Kids theme.

Four things had to change to get there, all found live and now in the code:

- The overlay needs `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive`; without it the
  keys went to the launcher underneath.
- `omarchy-kids-parent-auth` reads one line instead of waiting for EOF; the modal's Process
  kept stdin open and the helper hung.
- The chosen action runs through `Quickshell.execDetached`; a child `Process` started right
  before `Qt.quit()` died with the modal.
- `--finish` asks Hyprland to exit with `hyprctl dispatch 'hl.dsp.exit()'` (Hyprland 0.56 in
  Lua-config mode rejects `dispatch exit`) and waits for it. A hard
  `loginctl terminate-session` makes sddm-helper exit 1, SDDM logs "Process crashed" and starts
  no greeter at all: a black screen until `systemctl restart sddm`. It stays as the last resort
  only.

Not yet exercised live: the wrong-password shake and the 30 s lockout, Esc to close, Pause
(needs the decision in docs/phase1/DECISIONS-NEEDED.md), and the parent password on a kid's
tile at the portal (#15's PAM line is installed; a portal login with the parent password is
the next check).
