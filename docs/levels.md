# Levels: the root-owned Hyprland configs and the Level 1 launcher (R-DESK, Appendix E)

What each level binds, how the Level 1/2 big-tile launcher gets its tiles, and how to check any
of this on the test laptop's VM — this issue's code has never run against a real Hyprland or
Quickshell, so treat everything under "Verify in the VM" as open until it has.

## The files

| File | What it is |
| --- | --- |
| `share/hyprland/L1.lua`, `L2.lua`, `L3.lua` | Root-owned Hyprland configs, one per level (R-DESK-1, R-DESK-3) |
| `share/hyprland/band-3-5.lua`, `band-6-8.lua` | Cursor/gap/scale overlays, loaded by whichever level file is active when `OMARCHY_KIDS_BAND` matches |
| `share/launcher/shell.qml` | The Level 1/2 big-tile launcher (Quickshell/QtQuick), R-DESK-5 |
| `bin/omarchy-kids-session-start` | Runs once per session from each level file's `exec-once`; writes the launcher's tile JSON and starts the right thing for the level |
| `bin/omarchy-kids-launcher-ctl` | What the Hyprland binds call to show/activate the launcher, so the Lua files don't need Quickshell IPC details |
| `bin/omarchy-kids-exit` | Stub for Super+Shift+K (R-EXIT-1); not built yet |
| `share/menu/omarchy-kids-trimmed.jsonc` | Best-effort omarchy-menu extension for R-DESK-4 (Install/Update/Setup hidden at Levels 1-2) |

Deployment (R-DESK-1): the package installs these under `/usr/share/omarchy-kids/hyprland/` and
`/usr/share/omarchy-kids/launcher/`; provisioning copies or links them to
`/etc/omarchy-kids/hyprland/`. `omarchy-kids-session` (a stub as of this issue — a different
issue) reads the kid's profile and execs:

```text
Hyprland --config /etc/omarchy-kids/hyprland/L<level>.lua
```

**Cross-issue dependency, not yet wired:** the level file's band overlay (`OMARCHY_KIDS_BAND`)
has to be an environment variable already set when Hyprland starts parsing its config — i.e.
before `omarchy-kids-session` execs Hyprland — since the level files check it at config-parse
time, not later. `bin/omarchy-kids-session-start` (this issue) separately re-reads the account's
level/band itself via `omarchy-kids-conf` if `OMARCHY_KIDS_LEVEL`/`OMARCHY_KIDS_BAND` aren't
already in its environment, so the *launcher JSON and level-2/3 shell startup* work either way —
but the *band overlay* in L1.lua/L2.lua/L3.lua only fires if `omarchy-kids-session` exports
`OMARCHY_KIDS_BAND` before the `Hyprland --config ...` exec. That's `omarchy-kids-session`'s job
to do when it's built.

## What each level binds (Appendix E)

**Level 1.** `Super+Home` show the launcher · `Super+Return` open the highlighted tile ·
`Super+Q` close the focused window · `Super+Shift+K` the exit overlay (`omarchy-kids-exit`
stub) · the five standard volume/brightness media keys. Nothing else — no defaults, no
`require("default.hypr.bindings.*")`. Every window is forced fullscreen
(`o.window(".*", { fullscreen = true })`). `test/shell.d/levels-test.sh` greps for exactly this
set; nothing more, nothing less.

**Level 2.** Everything Level 1 binds, plus `Super+arrows` to focus a window,
`Super+Shift+arrows` to swap it, `Super+K` for Omarchy's own keybindings cheat sheet
(`omarchy-menu-keybindings`), and `Super+Space` aliased onto the same launcher as
`Super+Home`. The "50/50 dwindle split" Appendix E asks for isn't extra config here — it's
`default.hypr.looknfeel`'s own `general.layout = "dwindle"` / `dwindle.preserve_split = true`,
which Level 2 requires (see below) and which already gives that behavior for two tiled windows.

**Level 3.** `require("default.hypr.omarchy")` — the same defaults a grown-up's Hyprland session
gets — then `hl.unbind("SUPER + RETURN")` (the terminal bind, assumed from convention; see
**Open questions** below) and `o.bind("SUPER + SHIFT + K", ...)` for the exit overlay.
`omarchy-sudo-passwordless` is **not** removed by this file; see Open questions.

## What Level 1/2 do and don't require from Omarchy's defaults (I-3)

Level 1 must not depend on anything in the kid's home. Reading Omarchy's own
`default.hypr.looknfeel` and `default.hypr.input` end to end (the two files this repo had a copy
of to check against), neither one reaches into a home directory or requires anything else — they
only call `hl.config`/`hl.curve`/`hl.animation` (looknfeel) or read `/etc/vconsole.conf`, a
system file (input). Both are required directly by L1.lua and L2.lua.

`default.hypr.envs`, by contrast, requires `default.hypr.paths` and sets `XCOMPOSEFILE` to
`paths.home .. "/.XCompose"` — a path inside the logged-in account's home. That's not
enforcement, but I-3 is written broadly enough ("nothing in `~` enforces anything") that this
repo treats "nothing in `~` should matter at all" as the safer reading. L1.lua and L2.lua set the
handful of Wayland/toolkit envs a session actually needs directly instead (copied from
`default.hypr.envs`'s own list, minus the home-dependent lines).

`default.hypr.windows` and `hypr.monitors` are not required either: `windows.lua` requires
`default.hypr.apps` (not available to inspect while writing this, and not relevant to a
fullscreen-only kiosk), and `hypr.monitors` is the *user's own* `~/.config/hypr/monitors.lua` —
exactly the home file I-3 rules out. Levels 1 and 2 set no explicit monitor configuration; they
rely on Hyprland's own auto-detection.

## The launcher's tile list

`bin/omarchy-kids-session-start` resolves the kid's `allowlist` (`omarchy-kids-conf get <kid>
allowlist`) against `share/packs/<band>.toml`, tries to find each app's real `.desktop` file
(case-insensitive substring match on the pack `id` or `pkg` against every `.desktop` basename
under `/usr/share/applications`) to get a `gtk-launch`-able id and an `Icon=` value, and falls
back to running the pack `id` as a bare command if no `.desktop` file matches. It writes:

```json
{
  "account": "kid-ada",
  "band": "6-8",
  "level": "1",
  "tiles": [
    { "id": "tuxpaint", "label": "Tux Paint", "icon": "tuxpaint", "exec": "gtk-launch tuxpaint" }
  ]
}
```

to `/run/omarchy-kids/launcher-<uid>.json` (root-owned, tmpfs — never under the kid's home). If
the kid's `web` key isn't `none` **and** `/etc/chromium/policies/managed/omarchy-kids-<band>.json`
is readable, a `chromium` tile is appended (R-WEB-4: refuse the browser tile if the policy isn't
there). The policy file itself is a different issue's deliverable and doesn't exist in this repo
yet, so today this is always false — the correct fail-closed behavior, not a bug.

`share/launcher/shell.qml` polls that file, plus a small control file
(`/run/omarchy-kids/launcher-control`) that `bin/omarchy-kids-launcher-ctl` writes to on
`Super+Return`, and renders the tiles as a grid (140px cells, comfortably over the 96px floor)
with keyboard-only navigation (arrows move the highlight, Return/Enter launches, Escape is
swallowed and does nothing).

## Open questions / what could not be verified without Hyprland or Quickshell

This repo had two of Omarchy's real `default.hypr.bindings.*` files to check syntax against
(`bindings-tiling.lua`, `bindings-utilities.lua`) and a handful of other `default.hypr.*` files,
but no live Hyprland, no Quickshell, and no `default.hypr.bindings.applications` (where terminal
launching and, per Appendix E, "omarchy-sudo-passwordless" are presumably bound). Everything
below needs a real Omarchy 4.0.2 box or the VM to close out:

1. **The exact Level 3 terminal-launching bind(s).** L3.lua unbinds `SUPER + RETURN` on the
   near-universal Hyprland/tiling-WM convention that Super+Return opens a terminal — not
   confirmed against Omarchy's actual bindings. Run `omarchy-menu-keybindings` or `hyprctl binds`
   on a real box and correct the list in `share/hyprland/L3.lua` (there may be more than one
   terminal-launching bind, e.g. a second terminal or a file manager, also gated by
   `menu=trimmed`).
2. **`omarchy-sudo-passwordless`.** Deliberately not touched. It may not be a keybind at all —
   `default.hypr.autostart` (the file this repo calls `hypr-autostart.lua`) calls
   `omarchy-provision-first-run` on every `hyprland.start`, which sounds like a more likely place
   for a first-run passwordless-sudo convenience to live than a key someone presses. If that's
   right, Level 3 requiring `default.hypr.omarchy` re-runs that provisioning for the kid too,
   which the Appendix G bypass matrix ("Kid runs sudo → No grant") says must never happen. This
   needs confirming on a real box, and probably belongs to whatever issue owns
   `omarchy-provision-first-run` or Level 3 session hardening, not this one.
3. **`fullscreen = true` as a windowrule.** Modeled on the one confirmed boolean windowrule flag
   in the reference material (`{ no_focus = true }` in `default.hypr.windows`). Could be
   `{ fullscreen = "1" }` or something dispatcher-shaped instead; check with `hyprctl clients` on
   a Level 1/2 session.
4. **`hl.unbind`'s signature.** Assumed to take the same key-combo string `o.bind`'s first
   argument does. `bindings-utilities.lua`'s comment on its selection-layer binds describes
   unbinding by key as risky only because it can strip a *user's own* rebinding from their
   personal `~/.config/hypr` files — L3.lua has no such layer (R-DESK-6), so that risk doesn't
   apply here, but the call signature itself is still unverified.
5. **Everything in `share/launcher/shell.qml`.** No Quickshell was available to run this against
   at all. `Window` vs. `PanelWindow`/`WlrLayershell`, `FileView`'s API, and `Process`'s API are
   all best-effort guesses from general knowledge of the project — see the file's own header for
   the specifics and the reasoning for picking a plain top-level `Window` (fullscreened by the
   same windowrule as every other app, reachable by `hyprctl dispatch focuswindow`) over a
   layer-shell overlay.
6. **`omarchy-kids-trimmed.jsonc`'s schema.** No omarchy-menu extension documentation or source
   was available. The "hide": [...] shape in `share/menu/omarchy-kids-trimmed.jsonc` is a guess.
   Independent of whether it's supported, R-DESK-4 still holds at the keybinding level: Level 1
   runs no bar/shell at all, and Level 2 never binds anything to `"omarchy-menu toggle"`
   (`Super+Space` is rebound to the kids' own launcher instead), so there's no keyboard path to
   the untrimmed menu at either level regardless of whether the extension's hiding works.
7. **Volume/brightness keys** use `wpctl`/`brightnessctl` directly rather than an
   Omarchy-specific wrapper, since none was in the reference material. If Omarchy ships its own
   (e.g. for on-screen-display feedback), swap them in.

## Verify in the VM

With the package installed (or `share/hyprland/`, `share/launcher/`, and the `bin/omarchy-kids-*`
scripts copied to their spec-required paths and made root-owned):

1. From a spare tty (or the omarchy-kids session entry, once `omarchy-kids-session` is built):
   `Hyprland --config /etc/omarchy-kids/hyprland/L1.lua`.
2. Confirm the launcher appears fullscreen with tiles from `/run/omarchy-kids/launcher-<uid>.json`,
   that arrows move the highlight, Return launches, Escape does nothing.
3. `Super+Home` and `Super+Space` (Level 2) bring the launcher back after opening an app;
   `Super+Enter` opens whatever tile is highlighted without needing the launcher already focused.
4. `Super+Q` closes the focused app; `Super+Shift+K` prints `omarchy-kids-exit`'s stub message
   (until R-EXIT-1 is built).
5. Repeat for `L2.lua` (focus/swap/cheat sheet) and `L3.lua` (real Omarchy desktop minus the
   terminal bind — try `Super+Return` and confirm nothing launches).
6. Set `OMARCHY_KIDS_BAND=3-5` (or `6-8`) before the `Hyprland --config` run and confirm the
   cursor is visibly larger and GTK/Qt apps render bigger.

Everything above is run from `bash test/shell.d/levels-test.sh` first where it can be
(grep-based binding checks, `luac -p` if available, `bin/omarchy-kids-session-start`'s JSON
output against a scratch profile) — the VM is only for what a test file on a laptop with no
Hyprland or Quickshell cannot check.
