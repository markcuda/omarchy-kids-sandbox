# Everything after the first kid: `bin/omarchy-kids-panel` (SPEC.md R-WIZ-7, R-WIZ-8, R-ASK-2, R-TIME-4/5, R-FND-6; issue #21)

Once at least one kid is provisioned, `omarchy-kids` opens this instead of the wizard
(`bin/omarchy-kids-wizard` stays reachable as `omarchy-kids wizard`, and as this panel's own "Add
a kid" row — R-WIZ-7). Every screen is rendered by `lib/tui.sh` (issue #18) — this file never calls
`gum` directly, and drives entirely through `OMARCHY_KIDS_TUI_ANSWERS` in tests, same as the wizard
and its own test suite.

## Running it

```text
omarchy-kids-panel [--dry-run] [--apply] [--help]
```

`DRY_RUN=1` is the default everywhere a screen would write something (AGENTS.md rule 8): every
command a write would run is printed instead of run. Pass `--apply` (or set `DRY_RUN=0`) for a real
run.

## Screens (Appendix A's P1-P3; P4/P5 are not built here — see "Not built here" below)

| Screen | What's on it |
| --- | --- |
| **P1 Home** | One row per kid — name, band, minutes used/left today, `paused` if a kid's time isn't counting right now, and their open-request count (`kid_home_line`) — then **Add a kid**, **Requests (N)**, **Remove Kids Mode**, **Quit**. |
| **P2 Kid** | **Screen time** (today's status, "give more minutes" via `omarchy-kids-time grant`, and editing the daily budget / lights-out, both validated), **Web** (the band's mode; a walled-garden kid also gets an allow-list editor), **Apps** (hide/show the band's pack), **Desktop level**, **Password**, **Remove this kid**, **Back**. |
| **P3 Requests** | Every open "Ask a parent" request, each shown as `<kid> — <what> (<age>)`; Enter opens the reason line and **Approve**/**Decline**. |

Every screen is keyboard-complete (I-5): Esc or a **Back**/**Quit** row goes back or leaves; Ctrl+C
leaves the whole panel immediately, same contract as `lib/tui.sh` everywhere else (`docs/tui.md`).

### Home (P1)

`kid_home_line` reads `omarchy-kids-time status <kid>` for the used/left numbers and the `paused:`
line, and the ask queue (see below) for that kid's open-request count — nothing here re-derives
either; both are read the same way P2 and P3 read them, so the numbers always agree. **Add a kid**
`exec`s the wizard directly (R-WIZ-7: "the same per-kid screens"); when it finishes, a parent
re-opens `omarchy-kids` to get back to the panel, same as the wizard's own Done screen already
sends a parent back through the app entry point today.

### One kid (P2)

- **Screen time** shows `omarchy-kids-time status <kid>` verbatim, then three actions:
  "Give more minutes today" (`omarchy-kids-time grant <kid> <n>`, R-TIME-4: extends *today's*
  budget only), and editing `budget_min` / `lights_out` (`omarchy-kids-conf set`), each validated
  the same way the wizard validates them (1-1440 minutes; `HH:MM`, 24-hour).
- **Web** shows the band's mode (`omarchy-kids-conf get <kid> web`). A `none`/`filtered` kid gets an
  info screen only — R-WEB-3 says those modes take no allow list, and I-6 means this panel doesn't
  offer to edit one that wouldn't do anything. A `garden` kid gets the kid's own
  `/etc/omarchy-kids/kids/<kid>/allow.txt` (the same file `omarchy-kids-ask`'s `apply_site` writes
  to for an approved "ask for a site" request, docs/ask.md) as an add/remove list, editor-free (no
  `$EDITOR` — every line add/remove is its own screen); either edit re-runs
  `omarchy-kids-web install <band> --allow <file> --apply` so the change actually takes effect.
- **Apps** lists the band's starter pack (`omarchy-kids-apps list <kid>`) against the kid's
  effective allowlist (`omarchy-kids-apps allowlist <kid>`); Enter on an app toggles it via
  `omarchy-kids-apps hide`/`show`.
- **Data** (R-DATA-1..5, issue #27): read-only. Prints `omarchy-kids-data summary <kid>` (today) and
  `summary <kid> --week` (last 7 days) — minutes, launches, top apps, and top sites, in that order.
  Minutes and launches are unprivileged reads, same as the rest of this panel; sites need root (a
  kid's Chromium profile lives in a home this panel's own account can't otherwise reach), so this
  screen is the one place in P2 that calls `read_priv` instead of `run_priv` — a real `sudo` read,
  once, the moment it's needed, never previewed by `--dry-run` (there's nothing to preview: a read
  changes nothing). If `history_visible=no` for this kid, `omarchy-kids-data` already says so in
  plain words without touching Chromium at all (R-DATA-4), so this screen skips `read_priv` and
  asks for no password it wouldn't use. See docs/data.md for what's recorded, where, and for how
  long.
- **Desktop level** is the same 1/2/3 choice as the wizard's own A11, writing `level` only when it
  changed from the current value (same "only overrides" reasoning as R-BAND-2, applied one screen
  at a time instead of a whole Apply).
- **Password**: `omarchy-kids-provision` has no `passwd` subcommand yet — only `add`/`remove`/`list`
  (docs/provision.md) — so this screen checks for one (future-proofing) and, finding none, names
  the exact command a parent runs themselves (`sudo passwd <kid>`) rather than claiming a control
  that doesn't exist (I-6).
- **Remove this kid** asks a parent to type the kid's name back, exactly, before running
  `omarchy-kids-provision remove <kid> --apply` (R-FND-6). A mismatch runs nothing at all — not
  even a dry-run print — and says so.

### Requests (P3)

R-ASK-3 calls the queue format "stable and documented for a future home-network approver"; this
panel is the first such approver, so it reads `lib/ask.py`'s own `list-open`/`show` directly
(tab-separated, exact fields) instead of parsing `omarchy-kids-ask list`'s human-formatted columns,
which pad for a terminal, not a parser. Approve/decline themselves still go through
`omarchy-kids-ask approve|decline <id> --apply` — this panel never writes a queue record itself,
same "one thing writes the format" rule `docs/conf.md` applies to a kid's profile.

## Root and the one sudo prompt

Same shape as the wizard's own "Root and the one sudo prompt" (`docs/wizard.md`), but per-screen
instead of per-Apply: this panel runs as the parent and is never itself elevated. Every file it
*reads* — a kid's profile, the time ledger, the ask queue, a band's pack — is root-owned but
world-readable (docs/conf.md, docs/time.md, docs/ask.md), so Home and every P2/P3 screen render
with no privilege at all. The first time a screen would actually write something, `warm_sudo`
prints why on screen and spends one `sudo -v`; every write after that in the same run reuses sudo's
cached credential. `run_priv` is the one place a real change is either printed (`--dry-run`, the
default) or run for real under `sudo` — so `--dry-run` always shows the exact command a write would
run, panel-wide, not just for Apply.

## Not built here

- **P4 Machine** and **P5 Confirm remove** (Remove Kids Mode itself, R-TRUST-4): nothing in this
  checkout implements "Remove Kids Mode" yet — not the wizard, not this panel, not a standalone
  command. Home's own "Remove Kids Mode" row says so plainly (I-6) instead of pretending to offer
  it; removing kids one at a time from their own P2 screen is what this issue actually delivers.
- **Weekend budget/lights-out variants** (`budget_min_weekend`, `lights_out_weekend`): editable
  through `omarchy-kids-conf set` directly today; the Screen Time screen only edits the weekday
  pair, matching the issue brief ("edit budget and lights-out").

## File locations (overridable for tests, same convention as `docs/conf.md`/`docs/time.md`/`docs/ask.md`)

| What | Default path | Env override |
| --- | --- | --- |
| Kid overrides directory, allow-list files | `/etc/omarchy-kids/kids/` | `OMARCHY_KIDS_ETC` |
| `bands.toml`, `packs/` | `/usr/share/omarchy-kids/` | `OMARCHY_KIDS_SHARE` |
| The ask queue | `/var/lib/omarchy-kids/queue/` | `OMARCHY_KIDS_ROOT` (scratch prefix) |
| `lib/ask.py` (read directly for Requests, see above) | `lib/` beside `bin/`, else `/usr/lib/omarchy-kids` | `OMARCHY_KIDS_LIB` |
| Each helper binary (`omarchy-kids-conf`/`-time`/`-ask`/`-apps`/`-web`/`-provision`/`-wizard`/`-data`) | resolved beside this script, else `PATH` | `OMARCHY_KIDS_<NAME>_BIN` |

`test/shell.d/panel-test.sh` drives every screen above through `OMARCHY_KIDS_TUI_ANSWERS`, checking
both the exact `[dry-run] sudo ...` line a write prints and, in a real (`--apply`) run against a
pass-through `sudo` fake and a thin argv-logging "spy" in front of each real helper binary, that the
write actually happened (a budget really changed on disk, an app is really hidden, a request is
really marked approved) — and that a mistyped remove confirmation runs nothing at all.

## Verified live (2026-09-02, QEMU test VM)

Over `ssh -tt` with an answers file: `omarchy-kids` opened the panel (two kids exist), the Home
rows showed live minutes ("Cy · 6-8 · 17m used / 0m left today"), Cy → Screen time → "Give
more minutes today" → 10 printed the exact command in dry-run and, with `--apply`, ran
`sudo omarchy-kids-time grant kid-cy 10` after one warmed prompt; the status line updated to
"9 min left today (budget 1 + 25 granted)". Kid rows answer to their number (or the full
line), not the account name. Requests, Web, Apps, Password and Remove rows share the same
code path and are not yet exercised live.
