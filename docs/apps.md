# Apps: `omarchy-kids-apps`, the launcher allowlist, and the background install unit (SPEC.md R-APPS-2..6, Appendix C; I-1, I-6)

`bin/omarchy-kids-apps` is the one command that knows: what a band's starter pack contains and
whether it's installed, how to install the missing pieces without blocking the parent, a kid's
effective launcher allowlist (pack plus their own additions, minus their own hidden apps), and the
parent's opt-in switch for keeping kids' apps out of their own launcher.

## Commands

```text
omarchy-kids-apps list <band|kid>
omarchy-kids-apps install <band> [--now] [--apply]
omarchy-kids-apps install-queued
omarchy-kids-apps allowlist <kid>
omarchy-kids-apps hide <kid> <app>
omarchy-kids-apps show <kid> <app>
omarchy-kids-apps hide-from-mine [--apply]
omarchy-kids-apps show-in-mine [--apply]
```text

### `list <band|kid>`

Prints every app in a band's pack (`share/packs/<band>.toml`) with an `installed`/`missing` state
from `pacman -Q`. Given a kid account instead of a band, resolves that kid's band first
(`omarchy-kids-conf get <kid> band`) and lists the same thing — `list` is always about a *pack*,
never a kid's own allowlist (that's `allowlist`, below). An `aur:`-prefixed `pkg` is checked with
the prefix stripped (`pacman -Q` doesn't know about it), same as `install`.

### `install <band> [--now]`

Finds the band's pack packages that `pacman -Q` says aren't installed yet, and either:

- **Default** — enqueues them (deduplicated, one per line) to
  `/var/lib/omarchy-kids/apps-queue`, then `systemctl start --no-block
  omarchy-kids-apps-install.service` (R-APPS-3: "the parent keeps going"). The unit's own
  `install-queued` is what actually runs pacman, in the background, whenever systemd gets to it.
- **`--now`** — runs `pacman -S --needed --noconfirm` for the missing packages directly, in the
  foreground, right away.

Either way, an `aur:`-prefixed package is named on stderr and skipped, not queued and not
installed: building AUR packages is R-APPS-1's own job (`omarchy-pkg-*`), not yet built. Nothing
here ever removes a package or reboots.

`DRY_RUN=1` by default (AGENTS.md rule 8): both modes only print what they would do. `--apply`, or
`DRY_RUN=0`, makes either one real.

### `install-queued`

The queue's own worker: reads `/var/lib/omarchy-kids/apps-queue`, installs whatever in it isn't
already installed (`pacman -S --needed --noconfirm`), then empties the file. Meant to be run by
`systemd/omarchy-kids-apps-install.service`, never by a parent directly — see "Judgment calls"
below for why this one command always runs for real, unlike the rest of this file.

Idempotent: an empty queue, or a queue where everything is already installed, is a no-op. If
`pacman` fails, the queue file is left untouched (not emptied) so the next run — another
`install`, or a manual `install-queued` — tries again; this is the "retry from the panel" R-APPS-3
mentions, not a timer (no timer is built by this issue).

`bin/omarchy-kids-session-start` also reads this same queue file (issue #42, docs/levels.md's "The
launcher's tile list") — never writes it — to tell a launcher tile whose app is merely missing
apart from one whose package is already on its way in: `"installing..."` vs. `"not installed yet"`.

### `allowlist <kid>`

Prints the kid's *effective* launcher allowlist, comma-separated, same format as the raw
`allowlist` profile key: the band's pack (or the kid's `allowlist` override, if they have one),
plus every id in their `apps.extra`, minus every id in their `apps.hidden` (docs/conf.md's two
extension keys). Order: pack/override ids first in their own order, then any `apps.extra` ids not
already present, in their own order; anything in `apps.hidden` is dropped from either list.

This is what `bin/omarchy-kids-session-start` calls (instead of reading `allowlist` directly) to
build the Level 1 tile list and, at Levels 2/3, `$RUN/allowlist.json` (below) — so a `hide`/`show`
takes effect the next time that kid's session (re)starts.

### `hide <kid> <app>` / `show <kid> <app>`

Add/remove one launcher id from the kid's `apps.hidden`, through `omarchy-kids-conf set`
(docs/conf.md: nothing else is supposed to touch a kid's `.conf` file directly). Both are
idempotent — hiding an already-hidden app, or showing an app that was never hidden, changes
nothing. `<app>` doesn't have to be a pack id: hiding an `apps.extra` id works the same way.

### `hide-from-mine` / `show-in-mine`

**Opt-in only (I-1: the parent's account is never restricted or altered except when they ask).**
Nothing else in this repo calls these two.

`hide-from-mine` collects the effective allowlist (see `allowlist` above) of every provisioned
kid, finds each id's `.desktop` file (same best-effort substring search
`bin/omarchy-kids-session-start` uses for tiles), and writes an override copy of it into
`$HOME/.local/share/applications/<name>.desktop` with `NoDisplay=true` set and a
`X-OmarchyKidsHideFromMine=true` marker line added — so those apps stop appearing in the *current
user's own* launcher/menu, without touching the system-wide `.desktop` file, the kid's own account,
or anything under `omarchy`/`omarchy-settings` (I-7). An id with no matching `.desktop` file found
is skipped with a note, never silently claimed as hidden (I-6).

`show-in-mine` removes exactly the override files carrying that marker — never a file the parent
created themselves some other way, even one that also happens to set `NoDisplay=true`.

Both are `DRY_RUN=1` by default; `--apply` or `DRY_RUN=0` makes them real.

## `$RUN/allowlist.json` (R-DESK-4, issue #24)

At Levels 2 and 3, `bin/omarchy-kids-session-start` writes the kid's effective allowlist (the same
value `omarchy-kids-apps allowlist <kid>` prints) to
`$XDG_RUNTIME_DIR/omarchy-kids/allowlist.json`, alongside the Level 1/2 tile file
(`launcher-<uid>.json`, docs unwritten — see that script's own header comment). Shape:

```json
{ "account": "kid-ada", "band": "6-8", "allowlist": ["gcompris", "tuxpaint", "..."] }
```text

This exists for a future trimmed-menu extension at Levels 2/3 to read (Omarchy's own shell runs
there, not the Level 1 big-tile launcher, so there is no tile grid to read the list from instead).
**Nothing reads this file yet** — `share/menu/omarchy-kids-trimmed.jsonc` is a different mechanism
(it hides the Install/Update/Setup rows, R-DESK-4's other half) and, like that file's own header
comment says about `omarchy-menu`'s real extension schema, this repo has no confirmed way to feed
an app allowlist into Omarchy's own app grid/menu yet. Written unconditionally regardless (I-6:
this is inert data, not a claimed-but-unenforced control) so that wiring, whenever it lands, has
something correct to read from day one.

## Env (every path overridable — nothing here ever runs as root in dev, per AGENTS.md rule 8)

| Var | Default | Affects |
| --- | --- | --- |
| `OMARCHY_KIDS_ETC` | `/etc/omarchy-kids` | kid profiles (via `omarchy-kids-conf`) |
| `OMARCHY_KIDS_SHARE` | `/usr/share/omarchy-kids` | `packs/<band>.toml` |
| `OMARCHY_KIDS_ROOT` | (empty — the real paths) | scratch prefix for `/var/lib/omarchy-kids` (the install queue) — same convention `bin/omarchy-kids-assert` and `lib/posture.sh` use for system paths this package doesn't own |
| `OMARCHY_KIDS_HOME` | `$HOME` | `hide-from-mine`/`show-in-mine`'s target home — always the account running the command, never a kid's |
| `OMARCHY_KIDS_APPLICATIONS_DIRS` | `/usr/share/applications:/usr/local/share/applications` | `hide-from-mine`'s `.desktop` search |
| `OMARCHY_KIDS_CONF_BIN` | resolved beside this script, else `/usr/bin/omarchy-kids-conf` | every key read/write |
| `DRY_RUN` | `1` | `install` and `hide-from-mine`/`show-in-mine`; see "Judgment calls" |

`test/shell.d/apps-test.sh` runs entirely against a scratch `OMARCHY_KIDS_ETC`/`OMARCHY_KIDS_SHARE`/
`OMARCHY_KIDS_ROOT`/`OMARCHY_KIDS_HOME`, with stub `pacman` and `systemctl` on a stub `PATH` — see
that file's header comment for exactly how.

## Judgment calls made in this implementation

- **`install-queued` always runs for real, no `DRY_RUN` gate**, unlike every other write in this
  file. Same reasoning `docs/assert.md` gives for `omarchy-kids-assert`: it exists precisely so its
  one caller (`systemd/omarchy-kids-apps-install.service`, started with no other flags) never needs
  `--apply` to do its job. `install` (the command a parent actually runs) still defaults to
  `DRY_RUN=1` — the preview happens there, before anything is queued.
- **`hide`/`show` have no `DRY_RUN` gate**, unlike `install`. Same reasoning
  `bin/omarchy-kids-session-start`'s own `docs/session.md` gives for `--install-configs`, and the
  same one `omarchy-kids-conf set`/`reset` already live by: these are small, reversible,
  already-idempotent edits to one profile key, the same risk class as any other `omarchy-kids-conf
  set` — adding a dry-run flag here would be inconsistent with the tool they're a thin wrapper
  around, which has never had one.
- **`NoDisplay=true`, not `Hidden=true`.** SPEC.md's R-APPS-5 text says `Hidden=true`; this uses
  `NoDisplay=true` instead. In the freedesktop Desktop Entry / menu specs these mean different
  things: `Hidden=true` says "this id no longer exists, ignore it even for file-type/URL-scheme
  association", while `NoDisplay=true` says "don't list this in a menu, everything else about it is
  still valid" — which is what "keep it out of my launcher" actually means here (the app still
  needs to work if the parent runs it some other way, and still needs to resolve correctly for a
  kid's own, separate account). `NoDisplay=true` is also what desktop environments' own
  "remove from menu" features conventionally write. Worth a one-line comment on the issue per
  AGENTS.md's "if a ticket/spec disagree, the spec wins and the ticket gets a comment" rule, since
  this is the spec's own wording, not a ticket's.
- **`hide-from-mine` always covers every provisioned kid, no kid filter.** The issue's own wording
  ("writes those overrides for the current user") doesn't ask for one, and a filtered `show-in-mine`
  would need to re-resolve an allowlist that may have changed since the matching `hide-from-mine`
  ran, right when a parent is trying to clean up — matching everything the marker identifies is
  simpler and can't miss a stale override.
- **`list`/`allowlist` never touch `apps.extra`/`apps.hidden` for a band-only `list`.** `list
  <band>` is deliberately about the pack alone; a kid's own hides/extras only show up through
  `allowlist <kid>` or `list <kid>` (which resolves to the same band-level pack view — a kid's
  `apps.hidden` doesn't change what `list` reports as installed/missing, only what
  `allowlist`/the launcher shows).
- **AUR packages are named on `install`'s stderr, not silently dropped.** A parent running `--now`
  or watching the journal from the queue should be able to tell "this pack has N apps I can't
  install yet" from "everything installed cleanly" (I-6).

## Verify in the VM

This has never run against a real `pacman`, `systemd`, or `.local/share/applications` menu —
everything below is open until it has:

1. `omarchy-kids-apps list 6-8` on a fresh box: confirm every pack app shows `missing`.
2. `omarchy-kids-apps install 6-8` (default, no `--apply`): confirm it only prints the plan and
   queues nothing. Then `--apply`: confirm `/var/lib/omarchy-kids/apps-queue` has the missing
   package names and `systemctl status omarchy-kids-apps-install.service` shows it ran (or is
   running) `install-queued`; `journalctl -u omarchy-kids-apps-install.service` shows the pacman
   output.
3. `omarchy-kids-apps list 6-8` again: confirm the newly-installed apps now show `installed`.
4. Provision a kid, `omarchy-kids-apps hide kid-ada supertux`, then start (or restart) that kid's
   session and confirm the Level 1 launcher no longer has a SuperTux tile; `show` and confirm it
   reappears.
5. `omarchy-kids-apps hide-from-mine --apply` as the parent: confirm the parent's own app
   grid/menu no longer lists the kids' apps, and that a kid can still open them from their own
   session. `show-in-mine --apply`: confirm they're back in the parent's menu, unchanged from
   before.
