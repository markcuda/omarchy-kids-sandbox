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

```
omarchy-kids-exit            # same as --open
omarchy-kids-exit --open     # show the modal (a no-op if one looks already up)
omarchy-kids-exit --finish   # end the kid's session (R-EXIT-3) -- run by the modal, not a kid
omarchy-kids-exit --pause    # not implemented; prints why and exits 2
```

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

Meant to run once per **Super key release** (a Hyprland `bindr`, not `bind` — see "The triple-tap
bind: not wired in" below for why it isn't actually bound anywhere yet). Each run appends "now"
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

## The triple-tap bind: not wired in

The level configs (`share/hyprland/L1.lua`, `L2.lua`, `L3.lua`) already bind Super+Shift+K to
`omarchy-kids-exit` (`o.bind("SUPER + SHIFT + K", ...)`). Wiring the triple-tap the same way
would need one more line — a **release**-triggered bind (Hyprland's native config has `bindr` as
a distinct keyword from `bind`) calling `omarchy-kids-super-tap` on every bare Super release —
but none of the Omarchy Lua DSL reference material this repo has ever had access to
(`bindings-tiling.lua`, `bindings-utilities.lua`, and everything else under
`scratchpad/hypr-ref/` used to write `share/hyprland/*.lua` in the first place) shows a
release-bind form to confirm against: no `o.bindr`/`hl.bindr` function, and no fourth-argument
option on `o.bind` itself (like the `{ locked = true }` seen on the lid-switch binds in
`bindings-utilities.lua`) that looks like it would turn a normal bind into a release bind either.
Guessing at a function name that doesn't exist would either error out the whole config (a config
that fails to load is worse than one gesture missing — that's a Level 1/2/3 kid staring at a
black screen) or, worse, silently bind the wrong thing. So this is left **out** rather than
guessed at.

**To add it once a real Omarchy box confirms the call**, in each of `L1.lua`/`L2.lua`/`L3.lua`,
next to the existing Super+Shift+K bind:

```lua
-- Whichever of these two turns out to be real:
o.bindr("SUPER", "Kids Mode: triple-tap parent", "omarchy-kids-super-tap")
-- or, if o.bind's own signature is what actually grows this instead:
o.bind("SUPER", "Kids Mode: triple-tap parent", "omarchy-kids-super-tap", { release = true })
```

Check with `hyprctl binds` or `omarchy-menu-keybindings` on a real Omarchy 4.0.2 box whether
either shape actually registers a *release*-triggered bind (as opposed to a press-triggered one
that happens to also fire on `SUPER` alone, which would misfire on every other Super+<key>
combo's initial press) before adding it. Failing that, Hyprland's own native config syntax for
this is `bindr = SUPER, catchall, exec, /usr/bin/omarchy-kids-super-tap` — if this Lua DSL turns
out to have no wrapper for it at all, that raw line would need to land in the *compiled* config
Hyprland actually reads, which is a bigger change (this repo's `.lua` files are Hyprland's Lua
config *format*, not something with a documented "drop in one raw native-syntax line" escape
hatch in the reference material available while writing this) and is out of scope for a
one-line fix — flag it as its own follow-up if that's the answer.

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
- **The triple-tap bind**, per the section above — not wired into any `.lua` file at all yet.
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
   ```

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
7. The triple-tap gesture cannot be tested until "The triple-tap bind: not wired in" above is
   resolved; until then, `omarchy-kids-super-tap` can only be exercised directly:
   `omarchy-kids-super-tap; omarchy-kids-super-tap; omarchy-kids-super-tap` run three times within
   1.5 seconds by hand (or scripted) should open the modal the same way Super+Shift+K does.
