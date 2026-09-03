# The parent's bar widget: `bin/omarchy-kids-bar`, `share/bar/` (SPEC.md R-BAR, I-1; issue #37)

One dot per kid currently logged in, a badge with the count of open "ask a parent" requests, and
a click/Enter menu with quick actions -- installed only when the parent asks for it, never by the
wizard on its own (I-1: "Writes into the parent's own files happen only when the parent asks (bar
widget, ...)").

## The two pieces

| Piece | What it is |
| --- | --- |
| `share/bar/manifest.json`, `share/bar/KidsModule.qml` | The widget itself: an Omarchy shell plugin (see "Omarchy's real bar architecture" below) |
| `bin/omarchy-kids-bar` | `enable` / `disable` / `status` / `grant <kid> <minutes>` / `end <kid>` -- the only thing that ever touches the parent's own `~/.config/omarchy/shell.json` for this |

Nothing else in this package writes to either file. `bin/omarchy-kids-wizard`'s Done screen only
*mentions* `omarchy-kids-bar enable` in its Omy line -- see "Why this isn't a wizard yes/no
prompt" below.

Issue #37 also says the widget should be "removable from the panel". The panel (R-ASK-2's own
Requests screen included) is not built yet -- `bin/omarchy-kids` is a stub (see docs/wizard.md /
bin/omarchy-kids's own header) -- so for now `omarchy-kids-bar disable [--apply]` is that removal
path; whichever issue builds the real panel should wire a button to it there.

## Omarchy's real bar architecture (confirmed against omacom/omarchy, tag v4.0.2)

Unlike most of this repo's Quickshell files, this one targets Omarchy 4.0.2's real, documented
plugin system, read directly from the upstream source while writing it (not guessed from general
Quickshell knowledge):

- `manual/32-shell-plugins.md`, `shell/README.md` -- the plugin/manifest contract. The bar is one
  long-running Quickshell process (`omarchy-shell`) hosting first-party plugins under
  `$OMARCHY_PATH/shell/plugins/` and third-party ones dropped into
  `~/.config/omarchy/plugins/<id>/`, "discovered the same way" by the same process. A plugin is a
  directory with a `manifest.json` (`schemaVersion`, `id`, `kinds`, `entryPoints`) plus QML. A bar
  widget is turned on or off by adding or removing its id from `bar.layout.<left|center|right>` in
  `~/.config/omarchy/shell.json`; the real `omarchy plugin enable/disable` and `omarchy bar
  put/move` commands do that mutation on a live box.
- `shell/Ui/BarWidget.qml`, `shell/Ui/Panel.qml`, `shell/Ui/KeyboardPanel.qml`,
  `shell/Ui/PanelKeyCatcher.qml` -- the base types `KidsModule.qml` extends/uses. `Panel` (not the
  lighter `BarWidget`) is the root type, because this widget needs a click-to-open popup, same
  shape as two first-party examples this file's structure mirrors:
  `shell/plugins/panels/clock/BarWidget.qml` (icon + popup) and
  `shell/plugins/panels/power/Panel.qml` (icon + `KeyboardPanel` + `PanelKeyCatcher` + a `Column`
  of action rows -- the exact shape of this widget's menu).

**Why `bin/omarchy-kids-bar` edits `shell.json` with `jq` instead of shelling out to the real
`omarchy plugin`/`omarchy bar` commands:** those are the sanctioned way to do this on a live,
installed Omarchy box, but this issue's tests need to run against fixture trees with no
`omarchy-shell` or `omarchy` CLI present at all, and need an exact contract (back up once, add the
widget, disable restores byte-for-byte) that a plain `omarchy plugin disable` was never asked to
give you (it removes the layout entry; it was never asked to restore an original file). `enable`
still calls `omarchy-shell shell rescanPlugins` best-effort afterward, and `disable` calls
`omarchy-shell shell reloadConfig` best-effort, so a running shell picks the change up without a
logout -- both are no-ops (never fail the command) when no shell is running, which is every test
and most of local development.

**What is not confirmed:** whether a *third-party* plugin under `~/.config/omarchy/plugins/` can
`import qs.Ui` / `import qs.Commons` the same way a first-party one under `$OMARCHY_PATH/shell/
plugins/` does. The docs say both are discovered "the same way" by the same process, which implies
yes, but no third-party plugin source was available to confirm the import resolves outside
`$OMARCHY_PATH`. If it doesn't, on a live box the fix is almost certainly vendoring the small
pieces of `qs.Ui` this widget needs (`Panel`, `KeyboardPanel`, `PanelKeyCatcher`) into
`share/bar/` itself instead of importing the shell's copy -- confirm this first (see "What's
unverified" below).

## `bin/omarchy-kids-bar`

```text
omarchy-kids-bar enable [--apply]
omarchy-kids-bar disable [--apply]
omarchy-kids-bar status
omarchy-kids-bar grant <kid> <minutes>
```

`enable`:

1. Installs `share/bar/{manifest.json,KidsModule.qml}` into
   `~/.config/omarchy/plugins/omarchy-kids.bar/`.
2. If `~/.config/omarchy/shell.json` already exists, backs it up once to
   `shell.json.omarchy-kids.bak`, then adds `{"id": "omarchy-kids.bar"}` to `bar.layout.right`
   (everything else in the file -- other widgets, `plugins[]`, `idle`, ... -- is left untouched).
3. If it does **not** exist yet, seeds a new one from `$OMARCHY_PATH/config/omarchy/shell.json`
   (Omarchy's own shipped defaults -- reading that file is not an I-7 core edit; nothing under
   `$OMARCHY_PATH` is written) and remembers that it did (a
   `~/.config/omarchy/.omarchy-kids-bar-created-shell-json` marker), so `disable` can delete the
   file it created instead of leaving a stray `shell.json` a fresh install never had.
4. If **neither** exists, refuses (exit 1) rather than invent a bar config from nothing -- I-1:
   never risk silently discarding whatever else would have been on the parent's real bar.
5. Idempotent: enabling twice adds nothing a second time and never re-backs-up.

`disable` is the exact inverse: restores the backup and deletes it, or deletes the `shell.json` it
created, or (if for some reason neither applies) surgically drops just this widget's layout
entries. The installed plugin files under `~/.config/omarchy/plugins/` are left in place -- same
as `omarchy plugin disable` on a first-party widget (`shell/README.md`: "leaving its component
available to add again"). Idempotent: disabling an already-disabled bar is a no-op.

`grant <kid> <minutes>` is what the widget's own "give N more minutes" menu row runs (see
"Actions" below) -- it is not something a parent normally types by hand.

DRY_RUN=1 is the default for `enable`/`disable` (AGENTS.md rule 8); `--apply` (or `DRY_RUN=0`)
makes them real. `grant` always runs for real -- it's a parent clicking a button in their own
session, opening a terminal, nothing to preview.

## `share/bar/KidsModule.qml`

- Reads `/run/omarchy-kids/status.json` (R-BAR-3) via a `FileView` with `watchChanges: true`.
  Renders nothing when the file is missing, empty, or fails to parse (I-6: no control shown for
  data that isn't there).
- One dot per kid whose row has `"live": true`: the initial letter of the kid's slug (`kid-ada` →
  `A`), colored differently while `"paused": true`.
- A badge with the count of open requests, refreshed every 30s by running `omarchy-kids-ask list`
  in a `Process` and counting its output lines (that command prints a plain aligned table or the
  literal line `omarchy-kids-ask: no open requests` -- there is no `--json`/`--count` mode, so this
  counts lines rather than adding a new output mode to a command another issue owns).
- Click or Enter opens a menu: "give 15 more minutes" and "end session" rows for each live kid
  (also showing that kid's status and minutes left -- R-BAR-1's "Ada · paused · 32 min" line lives
  here), then "Open requests" and "Open Kids Mode".

### Actions (R-BAR-2: "give more time, end session, open Kids Mode")

| Menu row | Runs |
| --- | --- |
| `<K> · live/paused · N min — give 15 more` | `omarchy-kids-bar grant <kid> 15` |
| `<K> · live/paused · N min — end session` | `omarchy-kids-bar end <kid>` |
| `Open requests` | `omarchy-kids --requests` |
| `Open Kids Mode` | `omarchy-kids` |

`Open requests` is a fourth row this widget carries beyond R-BAR-2's exact three, grounded in
SPEC.md's own Ask flow description ("Kid action → modal → password on the spot, or queue → panel
or bar widget approve → action") rather than invented -- see "Why 'Open requests' isn't a deep
link" below.

**Why "give more time"/"end session" aren't direct calls to `omarchy-kids-time grant` /
`loginctl`:** granting time requires root (`omarchy-kids-time grant`'s own check), and this widget
runs in the parent's ordinary, unprivileged bar/shell process. `omarchy-kids-bar grant`/`end` open
a real terminal for a plain `sudo` prompt -- the parent's own login password (I-8), the same
mechanism `bin/omarchy-kids-wizard`'s own Apply step uses (plain `sudo`, not a `rootpw`), not a
polkit action, because none is defined for `omarchy-kids-time grant` or `loginctl terminate-user`
(R-FND-3's polkit rules cover NetworkManager/udisks/systemd-manage-units/pacman, not this). Both
prefer Omarchy's own `omarchy-launch-floating-terminal-with-presentation` helper (confirmed to
exist in `omacom/omarchy`'s `bin/` at v4.0.2) and fall back to `alacritty -e` if that isn't on
`PATH`.

**"End session" is a simplification of R-EXIT-3, not its exact sequence.** R-EXIT-3's Finish flow
(`share/exit-modal/shell.qml`, kid-initiated) does SIGTERM to a specific session scope, then
`loginctl terminate-session <id>`, then the greeter, because it already has that session's id in
hand. This widget only has `{kid, minutes_left, paused, live}` from status.json -- no session id
(R-BAR-3) -- so `omarchy-kids-bar end <kid>` runs `loginctl terminate-user <kid>` instead, ending
every session that account has. Real, root-capable `systemd-logind` functionality, not invented
for this, but the exact SIGTERM-then-terminate-session sequence was never itself confirmed against
a live `systemd-logind` here -- see "What's unverified" below.

**Why "Open requests" isn't a deep link into a Requests screen:** the panel (R-ASK-2: "the panel
lists requests") isn't built yet -- `bin/omarchy-kids` is still a stub. Rather than ship a button
that opens nothing (I-6), `omarchy-kids --requests` (added in this issue) prints
`omarchy-kids-ask list`'s own output right there, honestly labeled as the stub it is. Once the
real panel lands, that flag is the one to point at its Requests screen instead.

## `/run/omarchy-kids/status.json` permissions (R-BAR-3)

`bin/omarchy-kids-time-ledger`'s `write_status_json` already writes exactly what SPEC.md R-BAR-3
asks for: `chmod 0640` plus a best-effort `chgrp omarchy-parents` (never fails the tick if the
group doesn't exist or the chgrp fails for any other reason). `test/shell.d/bar-test.sh` asserts
this.

**A note on this issue's own instructions vs. the spec:** the task that produced this issue said to
make the file "world-readable... fix it to 0644 if it is not". SPEC.md R-BAR-3 says "group
`omarchy-parents` readable" (0640, not 0644) -- world-readable would let every kid account read
every other kid's live minutes-left and paused state, which nothing else in this spec does (R-DATA
carefully scopes what's visible to whom). Per AGENTS.md ("if a ticket and the spec disagree, the
spec wins and the ticket gets a comment"), this keeps the ledger's existing 0640/`omarchy-parents`
behavior unchanged rather than loosening it, and this paragraph is that comment.

## Why this isn't a wizard yes/no prompt

GitHub issue #37's own "Done when" list says the widget is "Enabled by the wizard's consent line
on the summary screen" (A13). SPEC.md's Appendix A row for A13 is just as exact as A14's, though:
a fixed bullet list ("Here's what happens next...") and exactly two Buttons ("Apply" / "Change
something") -- no third choice, same as A14 (Done). Either screen would mean adding a new
`tui_screen_confirm`/`tui_screen_choose` prompt that consumes its own answer in `TUI_MODE=file`,
which breaks every existing `answers_file(...)` sequence in `test/shell.d/wizard-test.sh` (each
currently ends `... apply parent`: the summary confirm, then Done's own choice, nothing in
between -- inserting a step anywhere in that chain shifts every answer after it).

Per AGENTS.md ("if a ticket and the spec disagree, the spec wins and the ticket gets a comment"),
neither A13 nor A14 gained a new prompt; Done's (A14) Omy line mentions `omarchy-kids-bar enable`
in its own text instead, once Apply has actually succeeded -- Done is the natural "one more thing,
now that you're set up" moment, and I-1's "only on consent" holds either way, since nothing runs
until the parent runs that command themselves. This paragraph, plus the status.json one above, are
this issue's two spec-vs-ticket comments.

## Env (every path overridable, per AGENTS.md rule 8)

| Var | Default | What |
| --- | --- | --- |
| `OMARCHY_KIDS_HOME` | `$HOME` | the parent's home |
| `OMARCHY_KIDS_SHARE` | `/usr/share/omarchy-kids` | `share/bar/manifest.json`, `KidsModule.qml` |
| `OMARCHY_PATH` | `/usr/share/omarchy` | Omarchy's own install root (a real Omarchy session var, confirmed against `etc/profile.d/omarchy.sh` / `default/bash/env-bootstrap` upstream -- not one of ours) |
| `OMARCHY_KIDS_DEFAULTS_SHELL_JSON` | `$OMARCHY_PATH/config/omarchy/shell.json` | seed for a shell.json `enable` has to create from scratch |
| `OMARCHY_KIDS_TIME_BIN` | resolved beside this script, else `/usr/bin/omarchy-kids-time` | what `grant` runs under `sudo` |
| `OMARCHY_KIDS_TERMINAL_BIN` | (probe `PATH`) | test hook: force `grant`'s terminal instead of probing for the floating-terminal helper / `alacritty` |
| `DRY_RUN` | `1` | gates `enable`/`disable` |

`share/bar/KidsModule.qml` reads its own env at runtime (`Quickshell.env(...)`, not a shell var):
`OMARCHY_KIDS_STATUS_JSON` (default `/run/omarchy-kids/status.json`), `OMARCHY_KIDS_ASK_BIN`
(default `omarchy-kids-ask`), `OMARCHY_KIDS_BAR_BIN` (default `omarchy-kids-bar`),
`OMARCHY_KIDS_BIN` (default `omarchy-kids`).

## What's unverified -- check in the VM

No Quickshell install, headless or otherwise, was available while writing `KidsModule.qml` --
see its own header for the full list. In order of what to check first:

1. **Does the widget appear on the bar at all** once `omarchy-kids-bar enable --apply` runs and
   `omarchy-shell shell rescanPlugins`/a re-login picks it up. This is the load-bearing unknown:
   if `import qs.Ui` doesn't resolve for a plugin under `~/.config/omarchy/plugins/` the way it
   does for one under `$OMARCHY_PATH/shell/plugins/`, this file needs its own copy of `Panel` /
   `KeyboardPanel` / `PanelKeyCatcher` (see "What is not confirmed" above).
2. With a kid logged in (and paused, via `omarchy-kids-time` or the panel once it exists): does
   the dot appear, with the right initial, and does its color/label change when paused?
3. Click the widget, then Enter/arrows/Escape with no mouse (I-5): does the menu open, navigate,
   and close the way `PanelKeyCatcher` promises?
4. "Give 15 more minutes" on a live kid: does a terminal open, prompt for the parent's own login
   password via plain `sudo`, and does `omarchy-kids-time status <kid>` reflect the grant
   afterward?
5. "End session" on a live kid: does the same terminal/sudo flow run, and does the kid's session
   actually end (portal shown again) the way `loginctl terminate-user` promises -- and is ending
   *every* session for that account (rather than just the one the parent meant) ever actually a
   problem in practice (a kid is not expected to have two sessions at once, but this was never
   checked against a real multi-session login)?
6. "Open requests" / "Open Kids Mode": do they print/launch what `bin/omarchy-kids` now does for
   `--requests` / no args?
7. `omarchy-kids-bar disable --apply` on a bar that has other, unrelated customizations (a real
   parent's real `shell.json`, not a fixture): confirm nothing else moves.

## Test coverage

`test/shell.d/bar-test.sh`: `enable`/`disable`'s exact `shell.json` edits against fixtures (no
existing file + no defaults → refuses; no existing file + defaults present → seeds and marks
"created"; a pre-existing, already-customized file → backs up once, adds the widget alongside
what's there, idempotent, `disable` restores the exact original bytes and removes the backup),
`grant`/`end`'s terminal-helper selection and argument validation, and `status.json`'s mode
(R-BAR-3).
`KidsModule.qml`'s own JSON parsing is QML/JS inline in the plugin (not a separate bash/python
script), so there is no bash unit test for it here -- item 4 above is the VM check that covers it.
