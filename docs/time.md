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

Requires root, through `lib/kids.sh`'s `is_root`. There is no environment escape: nothing a kid
can set may decide whether a root check happens (`AGENTS.md` rule 9). A test that has to be root
stubs `id` (`test/shell.d/tree.sh`'s `kids_id_stub`, `$KIDS_TEST_UID=0`).

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
It refuses to run as anyone but root, through `lib/kids.sh`'s `is_root` — nothing in
this issue calls it from a kid session; it exists for a parent (or a future panel/bar widget,
R-BAR-2) to run directly.

`daemon` polls every 30 s (`OMARCHY_KIDS_TIME_POLL_INTERVAL`) while *this session*
(`$XDG_SESSION_ID`) is `Active=yes`/`LockedHint=no` and not paused:

- remaining minutes crossing 10/5/1 **downward** (`lib/time.sh`'s `time_toast_thresholds` —
  R-TIME-3, issue #40; SPEC.md's three thresholds, not the two a draft of this ticket floated —
  the spec wins, per `AGENTS.md`) → `share/time/toast.qml`. A threshold fires only when the
  remaining minutes last seen was above it and the current reading is at or below it (`previous >
  threshold ≥ current`); a grant that raises remaining minutes back above a threshold un-fires it,
  so it fires again the next time it's actually crossed, instead of the stale re-fire issue #40
  reported live (a grant to 16 minutes re-triggered the already-shown "10 minutes left" toast).
  Every check — fired or not — is logged with its previous/current values (`toast-check:` lines in
  the session log) so a live run can be audited the same way this was found.
- remaining ≤ 0, or the clock has reached lights-out → `share/time/timesup.qml` (R-TIME-4),
  unless one is already up (`pgrep`, same pattern `omarchy-kids-exit` uses for its own modal).
- if a grant (or a fresh day, or lights-out being pushed — see "Not built yet") clears the
  deficit while Time's Up is showing, the daemon kills it (`pkill -f "quickshell -p ..."`) and
  resets the warning thresholds so they can fire again if things get low a second time.

## Warnings and Time's Up (R-TIME-3, R-TIME-4)

`share/time/toast.qml`: small, anchored top-right below the Level 1/2 launcher's own top-right
clock (`share/launcher/shell.qml`) — a 96px top margin instead of the clock's 24px, clearing its
roughly 40px height (issue #40; UNVERIFIED, see the QML's own header) — auto-dismiss (6 s, down
from 8 s), **no keyboard grab** — deliberately not layer-shell-exclusive, so a kid mid-task never
loses focus to it.

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
- `share/time/toast.qml`'s 96px top margin actually clearing `share/launcher/shell.qml`'s clock,
  and the 6 s auto-dismiss (issue #40) — arithmetic from both files' own anchors/font sizes, never
  checked against a real rendered frame of either.
- The 1-minute toast and Time's Up firing by budget alone, not just lights-out (issue #40's other
  open question from the "Verified live" note below) — `test/shell.d/time-test.sh`'s daemon
  `--oneshot` checks prove the decision and the `toast-check:` log line's shape; a kid actually
  seeing either on a real session is still unconfirmed.

## Verified live (2026-09-02, QEMU test VM)

The kid-side daemon starts with the session (`omarchy-kids-session-start` line in the session
log). The lights-out rule fired the full-screen Time's Up overlay at login for a 6-8 kid at
22:29 (band lights-out 19:30): owl avatar, "Time's up, kid-ada!", a "Finishing in N s" countdown,
"Ask a grown-up for more time" and "Finish". With no answer it ran Finish after 60 s and the
portal came back. Two packaging slips found live and fixed: the timer unit did not name its
ledger service, and the units lock enabled the timers without starting them. The budget path
(ledger tick, warnings at 10/5/1, Time's Up at 0) is the next live check.

Budget path, same night: with the timer running the ledger counted real minutes ("2 min used"
after two ticks), the 5-minute toast fired at login with 3 minutes left, and a grant from the
Ask modal moved the boundary. Two small things to tidy (issue #40): the toast overlapped the
launcher's clock, and a later "10 minutes left" toast fired again after the grant raised the
remaining time. Later the same night the budget itself ran out live: the ledger counted 9
minutes down one per tick, "Time's up, kid-ada!" appeared at 0 with the fox avatar and the
countdown, and the 60 s auto-Finish returned a fresh greeter. Whether the 1-minute toast showed
was unconfirmed.

**Issue #40's fix, not yet re-verified live:** the toast now anchors below the launcher's clock
instead of under it (a 96px top margin, up from 24px — `share/time/toast.qml`'s header) and
auto-dismisses in 6 s instead of 8; the threshold logic moved into a pure function,
`lib/time.sh`'s `time_toast_thresholds` (table-tested in `test/shell.d/time-test.sh`), that fires
10/5/1 only on `previous > threshold ≥ current` and un-fires a threshold the moment a grant raises
`current` back above it, so the stale-refire-after-a-grant bug above can't recur; and every check
— fired or not — is logged as `toast-check: ... previous=N current=M fired={...} firing={...}` so
a live run can show, from the log alone, exactly what the daemon saw at the 1-minute mark and at
budget-exhausted-Time's-Up, closing both of this "Verified live" note's open questions. None of
the three (the clock clearance, the re-fire fix, or the 1-minute/budget-exhausted confirmation)
has run against a real session yet — see "What's unverified" above.

## Source header (moved from `bin/omarchy-kids-time`, issue #49)

Kept for reference; the file itself now carries a 3-line pointer instead.

```text
omarchy-kids-time: the kid-side half of the screen-time engine
(SPEC.md R-TIME-1..5, R-ASK-1, Appendix F). Started detached from the
kid's own session by bin/omarchy-kids-session-start; also the CLI a
parent (or a future panel/bar widget, R-BAR-2) uses to check or grant
time.

Trust boundary: this whole command runs as the kid. It NEVER decides
how many minutes a kid has used -- it only reads
/var/lib/omarchy-kids/<kid>/usage/, which only
bin/omarchy-kids-time-ledger (root, via systemd/omarchy-kids-time.timer)
ever writes. A kid can kill this process (the warnings and the Time's
Up screen stop appearing) but cannot make it lie about the ledger,
because it has no write path into it -- see lib/time.sh's header for
the full argument. The one command below that DOES write
(`grant`) refuses to run as anyone but root, same as
omarchy-kids-time-ledger.

  daemon           Runs until the session ends: every 30s (poll
                    interval below), while this session is Active and
                    unlocked (`loginctl show-session $XDG_SESSION_ID`),
                    shows a small toast the first time remaining
                    minutes crosses 10/5/1 downward (SPEC.md R-TIME-3;
                    lib/time.sh's time_toast_thresholds is the pure
                    decision, issue #40 -- a grant that raises
                    remaining minutes back above a threshold lets it
                    fire again next time it's crossed), and a
                    full-screen "Time's Up" overlay at 0 remaining or
                    at lights-out (R-TIME-4). Meant to be started
                    once, detached, from bin/omarchy-kids-session-start
                    -- not run twice in one session.
  status [<kid>]    Minutes used, minutes left, and the next boundary
                    (budget running out, or lights-out) for <kid>
                    (default: this account). Read-only; any account
                    can run this for any kid (the ledger files are
                    world-readable, same as a kid's own .conf).
  grant <kid> <n>   Adds <n> minutes to <kid>'s budget for today only
                    (R-TIME-4: "'More time' extends today's budget
                    only"). Root only.
  ask-grownup       Runs `omarchy-kids-ask-grownup time <n>` if that
                    command exists, else logs that a grant was asked
                    for and does nothing else. This is a placeholder
                    for the real "Ask a parent" flow (SPEC.md R-ASK-1,
                    a separate ticket): today it can only ask, never
                    itself grant -- share/time/timesup.qml's "Ask a
                    grown-up" button runs this, and I-6 ("honest UI")
                    is why that button's own label says "ask", not
                    "get", more time.

Every path is overridable for tests, same convention as
bin/omarchy-kids-session-start and lib/time.sh:
  OMARCHY_KIDS_ETC      kid overrides root (default /etc/omarchy-kids)
  OMARCHY_KIDS_SHARE    bands.toml, time/ (default /usr/share/omarchy-kids)
  OMARCHY_KIDS_ROOT     scratch prefix for /var/lib/omarchy-kids
  OMARCHY_KIDS_RUN      runtime state root (default $XDG_RUNTIME_DIR/omarchy-kids)
  OMARCHY_KIDS_ACCOUNT  kid account (default: this process's own user)
  OMARCHY_KIDS_NOW      "YYYY-MM-DD HH:MM:SS" clock override (tests)
  OMARCHY_KIDS_TIME_POLL_INTERVAL  daemon's sleep, seconds (default 30)
  OMARCHY_KIDS_TIME_DAEMON_ONESHOT=1  run one daemon iteration and
                        return instead of looping forever (test hook)
  OMARCHY_KIDS_ASK_GROWNUP_MINUTES  minutes `ask-grownup` names
                        (default 15)
```

## Source header (moved from `bin/omarchy-kids-time-ledger`, issue #49)

Kept for reference; the file itself now carries a 3-line pointer instead.

```text
omarchy-kids-time-ledger: the ONLY thing that ever writes a kid's
screen-time usage (SPEC.md R-TIME-1..2, Appendix F). Root, run from
systemd/omarchy-kids-time.timer (every minute) via
omarchy-kids-time-ledger.service.

Trust boundary (see lib/time.sh's header for the long version): the
per-session daemon (bin/omarchy-kids-time) runs as the kid and can
only read what's under here -- if this script only ran as the kid,
the "ledger" would just be a kid-writable file with extra steps. It
runs as root instead, and the only thing that decides what counts is
what `loginctl` reports about a session it doesn't own, plus a
root-owned paused flag (lib/time.sh's time_paused_file) -- never
anything a kid process could write into.

  tick    Lists every session with `loginctl list-sessions`, and for
          each one belonging to a known kid account (one with a
          profile under $OMARCHY_KIDS_ETC/kids/) whose session is
          Active=yes, LockedHint=no, and not paused (R-TIME-2: "Paused
          or locked time does not count"), adds one minute to that
          kid's ledger for today's logical day (Appendix F: the day
          rolls at 04:00). A kid with more than one such session only
          gets one minute added, not one per session. Also refreshes
          /run/omarchy-kids/status.json (R-BAR-3) for every known kid,
          whether or not they're live right now -- best-effort; a
          failure to write it never fails the tick itself, since the
          ledger write is the part that actually matters. Finally,
          for every known kid, folds any new lines from their own
          kid-writable runtime launches log into their root-owned
          launches.log (lib/data.sh's data_fold_launches, R-DATA-1's
          "app launches" -- see that file's header for the trust
          boundary this mirrors from screen time one level up).
          Same best-effort rule: a fold failure never fails the tick.

Every path is overridable for tests, same convention as
bin/omarchy-kids-apps and lib/time.sh:
  OMARCHY_KIDS_ROOT    scratch prefix for /var/lib/omarchy-kids and
                       /run/omarchy-kids
  OMARCHY_KIDS_ETC     kid overrides root (default /etc/omarchy-kids)
  OMARCHY_KIDS_NOW     "YYYY-MM-DD HH:MM:SS" clock override (tests)
  OMARCHY_KIDS_RUN_USER_BASE  lib/data.sh's launch-log fold source
                       (default /run/user; see that file's header)
```

## Source header (moved from `lib/time.sh`, issue #49)

Kept for reference; the file itself now carries a 3-line pointer instead.

```text
lib/time.sh — shared helpers for the screen-time engine (SPEC.md
R-TIME-1..5, Appendix F): bin/omarchy-kids-time-ledger (root, writes)
and bin/omarchy-kids-time (the kid, reads).

Trust boundary. `bin/omarchy-kids-time` runs as the kid, in the kid's
own session -- so it can never be the thing that decides how many
minutes a kid has used today; a kid could just kill it, or a copy of
it, and print whatever it wanted. The authoritative ledger is written
only by bin/omarchy-kids-time-ledger, run as root by
systemd/omarchy-kids-time.timer, never invoked from a kid session.
Every function in this file that *writes* under $TIME_ROOT
(time_ledger_add, time_grant_add) is only ever called by that root
helper (or by `omarchy-kids-time grant`, which itself refuses to run
as anyone but root -- see that command). Everything
bin/omarchy-kids-time itself calls here is read-only: it can show a
kid a stale or wrong number if it's buggy, but it cannot make the
ledger say something that isn't true, because it has no code path
that writes to it (I-3: locks live outside every home, root-owned;
R-TIME-1 puts that root ownership on /var/lib/omarchy-kids/<kid>/
itself, not just on the profile).

Clock. Every "now" here is OMARCHY_KIDS_NOW when set -- a local
wall-clock string, "YYYY-MM-DD HH:MM:SS" -- or the real clock
otherwise (`date '+%Y-%m-%d %H:%M:%S'`). This system has no notion of
timezone anywhere (budget/lights-out are plain HH:MM, same as
bands.toml), so nothing here ever converts a zone, only reads local
fields. Tests set OMARCHY_KIDS_NOW so the whole suite is independent
of the host's own clock and of GNU-vs-BSD `date` differences (see
lib/time.py's header for why day-rollover math is Python, not bash).

Not meant to be executed directly; source it from a command:
  source "$LIB/time.sh"

Every path below is overridable the same way bin/omarchy-kids-apps
and bin/omarchy-kids-assert already are:
  OMARCHY_KIDS_ROOT  scratch prefix for /var/lib/omarchy-kids
```

## The overlays are tracked by pidfile (issue #58)

`show_toast`, `show_timesup` and `dismiss_timesup` used `pgrep -f "quickshell -p <path>"` and
`pkill -f` on the same string. A kid with a terminal (bands 9-12 and 13+ ship one) could start any
process whose argv contained that string — `exec -a "quickshell -p …/timesup.qml" sleep 99999` —
and lights-out would think it was already on screen and never draw it (review §2.6).

They now use `lib/kids.sh`'s `modal_already_open` / `modal_write_pid` / `modal_close`, the pidfile
pair `omarchy-kids-exit` and `omarchy-kids-ask` already used: `$OMARCHY_KIDS_RUN/toast.pid` and
`timesup.pid`, written by the daemon with the overlay's own pid, checked against
`/proc/<pid>/comm`, and killed by pid rather than by argv match.

Note what this does *not* fix: the overlay still runs in the kid's own session, so a kid who kills
it (or never lets the daemon start) sees no Time's Up screen. Nothing root-side ends a session at
lights-out yet — `README.md` says so under "What works today", and it stays advisory for bands
with a terminal until the ledger does the terminating.

## The trust boundary (issue #58)

This command resolves `lib/` and every sibling `omarchy-kids-*` from its own resolved location
(`readlink -f "$0"`), else the installed prefix — never from the environment. `$OMARCHY_KIDS_LIB`,
the `*_BIN` / `*_PY` overrides, the socket paths and the `*_REQUIRE_ROOT` escapes are gone:
`AGENTS.md` rule 9 states the rule and `test/shell.d/trust-boundary-test.sh` enforces it, with the
allowlist of the data settings that stay. A test that needs a stub places it beside a copy of the
command in a scratch tree (`test/shell.d/tree.sh`), or substitutes a build-time constant, the way
`PKGBUILD` substitutes `KIDS_PY` at package time.
