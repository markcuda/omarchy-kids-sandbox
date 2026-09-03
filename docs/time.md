# The screen-time engine (SPEC.md R-TIME-1..5, R-ASK-1, Appendix F)

Budget and lights-out per kid, accounted while their session is active and unlocked, with
warnings on the way down and a full-screen stop at the end. This is issue #23.

**Nothing here has run against a real Hyprland, Quickshell, or `loginctl`/systemd-logind** — see
"What's unverified" below before trusting any of it in front of a kid.

## The trust boundary — read this first

A kid's own session cannot be the thing that decides how many minutes they've used. Everything
that *runs as the kid* in this feature only ever **reads**:

| Piece | Runs as | Can write? |
| --- | --- | --- |
| `bin/omarchy-kids-time-ledger tick` | root, via `systemd/omarchy-kids-time.timer` (every minute) | yes — the only writer of `usage/<day>` |
| `bin/omarchy-kids-time grant` | must be root (checked; refuses otherwise) | yes — the only writer of `usage/<day>.grant` |
| `bin/omarchy-kids-time daemon` / `status` | the kid | no — read-only |

`/var/lib/omarchy-kids/<kid>/usage/` is root-owned, created `0755`; every file in it is written
`0644` (world-readable, so `status` and the daemon can read it as the kid, same as a kid's own
profile file under `/etc/omarchy-kids/kids/`) but only ever *written* by the root helper above. A
kid can kill their own `omarchy-kids-time daemon` — the warnings and the Time's Up screen just
stop appearing — but there is no code path in anything that runs as the kid that writes a minute,
a grant, or a lower "used" number into this tree. That's I-3 applied one level down from locks
generally: the ledger itself lives outside every home, root-owned, same as everything else this
package enforces.

## Pieces

| File | What it is |
| --- | --- |
| `lib/time.sh` | Shared bash helpers: the clock, day-boundary/weekend, budget/lights-out resolution, ledger/grant reads and (root-only) writes |
| `lib/time.py` | The one place this needs real calendar math — day rollover and weekday, portable across the dev machine's BSD `date` and the target's GNU `date` (same reasoning as `lib/conf.py`) |
| `bin/omarchy-kids-time-ledger` | Root: `tick` adds a minute to every active/unlocked/non-paused kid's ledger, and refreshes `/run/omarchy-kids/status.json` (R-BAR-3) |
| `systemd/omarchy-kids-time.timer` + `omarchy-kids-time-ledger.service` | Runs `tick` once a minute |
| `bin/omarchy-kids-time` | The kid-side daemon, plus `status`/`grant`/`ask-grownup` |
| `share/time/toast.qml` | The small "N minutes left" warning (R-TIME-3) |
| `share/time/timesup.qml` | The full-screen "Time's up" overlay (R-TIME-4) |

## Budget, lights-out, and the day (R-TIME-2, Appendix F)

Nothing new in `omarchy-kids-conf`: this reads Appendix B's existing `budget_min` /
`budget_min_weekend` and `lights_out` / `lights_out_weekend` keys (`docs/conf.md`), resolved the
usual way (a kid's override, else their band's default from `bands.toml`). There is no per-day-
of-week override beyond the weekday/weekend split — that split *is* R-TIME-2's "weekend variants".

The day rolls at **04:00 local**: a session still running at 03:59 is still spending yesterday's
budget, and one still running at 04:01 has started spending a fresh day's (Appendix F). Weekend is
Saturday and Sunday of the *logical* day, not the wall-clock day, for the same reason. Both are
computed once per read by `lib/time.py logical-day`, never by shelling out to `date -d`/`date -v`
(those two flags don't agree between GNU and BSD `date`, and this repo is developed on the latter,
shipped on the former — see that file's header).

`OMARCHY_KIDS_NOW` (format `"YYYY-MM-DD HH:MM:SS"`, local wall clock, no timezone — this system
has no notion of one anywhere, same as `budget_min`/`lights_out` being plain numbers/`HH:MM`)
overrides "now" in **both** `omarchy-kids-time` and `omarchy-kids-time-ledger`; unset, both call
the real `date '+%Y-%m-%d %H:%M:%S'`. `test/shell.d/time-test.sh` sets it on every case so the
suite never depends on the host's own clock or its `date` binary's flavor.

## `bin/omarchy-kids-time-ledger tick` (root, once a minute)

1. Reads today's logical day and weekend flag.
2. Lists every session (`loginctl list-sessions --no-legend`), keeping the ones whose account has
   a profile under `$OMARCHY_KIDS_ETC/kids/` (i.e., is a kid).
3. For each such kid (deduplicated — two sessions for the same kid still only count once), checks
   `loginctl show-session <id> -p Active -p LockedHint`. `Active=yes` and `LockedHint=no` and no
   `paused` flag file (see below) → add one minute to `usage/<day>`.
4. Refreshes `/run/omarchy-kids/status.json` (R-BAR-3) for every known kid, live or not — a
   first cut for the future parent-bar widget (R-BAR), not consumed by anything in this issue.
   Best-effort: a failure here (missing `jq`, an unwritable `/run`) never fails the tick itself.

Requires root (`OMARCHY_KIDS_TIME_LEDGER_REQUIRE_ROOT=0` skips the check — a test hook, the same
convention `grant`'s `OMARCHY_KIDS_TIME_REQUIRE_ROOT` below uses).

**Resolution note:** SPEC.md R-TIME-1 says "30 s resolution". This ledger writes once a minute
(matching the timer's own period) — the 30 s figure is met by `omarchy-kids-time daemon`'s own
poll loop noticing a boundary within 30 s of it actually being crossed, not by the ledger itself
writing sub-minute totals. A minute's worth of slop at the very edge of a budget or lights-out is
the trade-off; nothing here tries to hide that.

## `bin/omarchy-kids-time` (the kid)

```text
omarchy-kids-time daemon           # started detached by omarchy-kids-session-start
omarchy-kids-time status [<kid>]   # minutes used, left, and the next boundary
omarchy-kids-time grant <kid> <n>  # root only: +n minutes to <kid>'s budget, today only
omarchy-kids-time ask-grownup      # see "Ask a grown-up" below
```text

`status` (default `<kid>`: this account) prints two lines:

```text
$ omarchy-kids-time status kid-ada
kid-ada: 23 min used, 37 min left today (budget 60)
next boundary: lights-out at 19:30
```text

`grant` adds to a *separate* `usage/<day>.grant` file, never subtracted from `usage/<day>` itself
— "used" always means "used", and "budget" for the day is `budget_min(_weekend) + grant`
(R-TIME-4: "'More time' extends today's budget only", i.e. just today's file, never tomorrow's).
It refuses to run as anyone but root (`OMARCHY_KIDS_TIME_REQUIRE_ROOT=0` for tests) — nothing in
this issue calls it from a kid session; it exists for a parent (or a future panel/bar widget,
R-BAR-2) to run directly.

`daemon` polls every 30 s (`OMARCHY_KIDS_TIME_POLL_INTERVAL`) while *this session*
(`$XDG_SESSION_ID`) is `Active=yes`/`LockedHint=no` and not paused:

- remaining ≤ 10/5/1 minutes (first crossing only, per threshold) → `share/time/toast.qml`
  (R-TIME-3; SPEC.md's three thresholds, not the two a draft of this ticket floated — the spec
  wins, per `AGENTS.md`).
- remaining ≤ 0, or the clock has reached lights-out → `share/time/timesup.qml` (R-TIME-4),
  unless one is already up (`pgrep`, same pattern `omarchy-kids-exit` uses for its own modal).
- if a grant (or a fresh day, or lights-out being pushed — see "Not built yet") clears the
  deficit while Time's Up is showing, the daemon kills it (`pkill -f "quickshell -p ..."`) and
  resets the warning thresholds so they can fire again if things get low a second time.

## Warnings and Time's Up (R-TIME-3, R-TIME-4)

`share/time/toast.qml`: small, top-right, auto-dismiss (8 s), **no keyboard grab** — deliberately
not layer-shell-exclusive, so a kid mid-task never loses focus to it.

`share/time/timesup.qml`: full-screen, keyboard-exclusive (same `PanelWindow` +
`WlrLayershell.layer: WlrLayer.Overlay` + `WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive`
pattern verified live for `share/exit-modal/shell.qml`), a visible 60 s countdown, and two
choices:

- **Ask a grown-up for more time** — runs `omarchy-kids-time ask-grownup`, detached. Does *not*
  close the overlay or grant anything by itself (see below).
- **Finish** — runs `omarchy-kids-exit --finish`, same as the exit modal's own Finish.

After 60 s with no answer, it runs Finish itself (R-TIME-4: "terminate after 60 s unless a parent
grants more").

### "Ask a grown-up" is a placeholder, not R-ASK-1

SPEC.md's real "Ask a parent" flow (R-ASK-1: one modal, parent password grants on the spot or the
request is queued) is its own ticket. `omarchy-kids-time ask-grownup` runs
`omarchy-kids-ask-grownup time 15` if that command is on `PATH`, else logs the request and does
nothing else — it can *ask*, it cannot *grant*. `share/time/timesup.qml`'s button is labeled "Ask
a grown-up for more time", not "Get more time", for exactly this reason (I-6: don't claim a
control does something it doesn't). `omarchy-kids-ask-grownup` itself is today's R-DESK-2
fail-closed placeholder (`docs/session.md`) reused here as a hook, not rebuilt — it will print an
"Ask a grown-up" screen naming "time 15" as the "check", which reads a little oddly until R-ASK-1
lands and gives it (or a real ask-modal) the real behavior.

## Pause-awareness (R-TIME-2)

`/var/lib/omarchy-kids/<kid>/paused`: if this file exists, `tick` does not count that kid's time,
full stop, regardless of what `loginctl` says about their session. Nothing in this issue creates
this file — `bin/omarchy-kids-exit --pause` is itself not implemented yet (see its own header and
`docs/phase1/V1.md`) — it exists so the ledger is ready the moment something does. Until then, "no
counting while paused or locked" (R-TIME-2) is already covered by the `Active`/`LockedHint` check
alone.

## Not built in this issue

- **The pre-reader full-screen countdown** (R-TIME-3's second half: "plus a full-screen countdown
  for pre-readers with icon and sound"). `share/time/toast.qml` is the same for every band today.
- **Pushing lights-out for tonight only** (R-TIME-4). `grant` only ever extends the *budget*.
- **The real R-ASK-1 "Ask a parent" modal** (a parent-password-gated on-the-spot grant, or a
  queued request) — see "Ask a grown-up is a placeholder" above.
- **`/run/omarchy-kids/status.json` has no reader yet** — it's written (R-BAR-3's shape) for the
  future parent-bar widget, R-BAR, which is a separate ticket.

Each of these is a real gap, not an oversight — I-6 says don't claim a control that isn't there,
so this list is exactly the set of R-TIME/R-ASK behaviors this issue's "Done when" doesn't cover.

## File locations (overridable for tests, same convention as `docs/conf.md`)

| What | Default path | Env override |
| --- | --- | --- |
| Kid overrides directory | `/etc/omarchy-kids/kids/` | `OMARCHY_KIDS_ETC` |
| `bands.toml` | `/usr/share/omarchy-kids/` | `OMARCHY_KIDS_SHARE` |
| Ledger/grant/paused files | `/var/lib/omarchy-kids/<kid>/` | `OMARCHY_KIDS_ROOT` (scratch prefix, same as `bin/omarchy-kids-apps`) |
| `status.json` | `/run/omarchy-kids/status.json` | `OMARCHY_KIDS_ROOT` (scratch prefix) |
| `omarchy-kids-time`'s runtime log | `$XDG_RUNTIME_DIR/omarchy-kids/session-<uid>.log` | `OMARCHY_KIDS_RUN` |

## What's unverified (check in the VM before this ships)

- Every Quickshell-specific name in `share/time/toast.qml` and `share/time/timesup.qml` — see
  their own headers; `timesup.qml` reuses exactly the `PanelWindow`/`WlrLayershell` pattern
  already verified live for the exit modal, so that part is lower-risk than `toast.qml`'s
  non-exclusive layer-shell window, which is new territory for this repo.
- `loginctl show-session <id> -p Active -p LockedHint`'s exact output shape on the real target
  (this repo has never run against a real `systemd-logind`) — `test/shell.d/time-test.sh` stubs
  it, so the *parsing* is tested, not the real command's actual output.
- Whether a background `&`'d `omarchy-kids-time daemon`, started from
  `omarchy-kids-session-start` before it `exec`s the launcher/shell, actually survives that `exec`
  and keeps running for the life of the session (expected — backgrounded jobs aren't children of
  the `exec`'d process — but never watched happen on a real Hyprland session).

## Verified live (2026-09-02, QEMU test VM)

The kid-side daemon starts with the session (`omarchy-kids-session-start` line in the session
log). The lights-out rule fired the full-screen Time's Up overlay at login for a 6-8 kid at
22:29 (band lights-out 19:30): owl avatar, "Time's up, Ben!", a "Finishing in N s" countdown,
"Ask a grown-up for more time" and "Finish". With no answer it ran Finish after 60 s and the
portal came back. Two packaging slips found live and fixed: the timer unit did not name its
ledger service, and the units lock enabled the timers without starting them. The budget path
(ledger tick, warnings at 10/5/1, Time's Up at 0) is the next live check.

Budget path, same night: with the timer running the ledger counted real minutes ("2 min used"
after two ticks), the 5-minute toast fired at login with 3 minutes left, and a grant from the
Ask modal moved the boundary. Two small things to tidy (issue #40): the toast overlaps the
launcher's clock, and a later "10 minutes left" toast fired after the grant raised the
remaining time, so the thresholds should only fire on the way down.
