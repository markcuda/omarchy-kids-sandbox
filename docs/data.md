# Recorded data and transparency: `omarchy-kids-data` (SPEC.md R-DATA-1..5, I-2, I-6; issue #27)

Mutual transparency, local only: what this package records about how a kid uses the computer, one
command to read it (a parent, through the panel) and to explain it (the kid, through their own
screen), and one command to prune it once it's past its retention window.

## What's recorded, where, and for how long (R-DATA-1)

| What | Where | Kept | Read by |
| --- | --- | --- | --- |
| Active minutes per day | `/var/lib/omarchy-kids/<kid>/usage/<day>` — `lib/time.sh`'s own tree, R-TIME-1 | 1 year | `omarchy-kids-data summary`/`retention` (this issue only reads/prunes it — the ledger itself is docs/time.md's) |
| App launches (Level 1 tiles only) | `/var/lib/omarchy-kids/<kid>/launches.log` | 90 days | `omarchy-kids-data launches`/`summary`/`retention` |
| Ask-a-parent requests | `/var/lib/omarchy-kids/queue/*.json` (Appendix D, `lib/ask.py`) | 90 days | `omarchy-kids-data retention` prunes it; docs/panel.md/docs/ask.md read it |
| Browsing history | the kid's own `~/.config/chromium/Default/History` (Chromium's own SQLite db) | the browser's own retention — R-WEB-2 already sets `SavingBrowserHistoryDisabled: false` and `AllowDeletingBrowserHistory: false`, so this package never prunes it | `omarchy-kids-data sites`/`summary`, gated by `history_visible` (below) |

**Never recorded, anywhere in this package (R-DATA-2):** keystrokes, screenshots, file contents,
message contents. There is no code path here or anywhere else in this repo that reads any of those.

## `omarchy-kids-data`

```text
omarchy-kids-data launches <kid> [--since DAYS]
omarchy-kids-data sites <kid> [--since DAYS]
omarchy-kids-data summary <kid> [--week]
omarchy-kids-data mine
omarchy-kids-data retention [--apply]
```

- **`launches`** reads the root-owned `launches.log` (below), most recent first. World-readable, so
  this needs no privilege — same convention as every other read-only figure in this package
  (docs/time.md, docs/panel.md).
- **`sites`** copies the kid's Chromium `History` db (and its `-wal`/`-shm` sidecars, if present —
  Chromium keeps it open and WAL-locked while running, so this never reads the live file) to a temp
  file, reads *that* read-only, and prints one line per visit. Needs root, unless run as the kid
  themselves — see "Who can read what" below.
- **`summary`** prints today's (or, with `--week`, the last 7 days') minutes, launch count, top
  apps, and top sites — the same figures the panel's Data screen shows (docs/panel.md).
- **`mine`** is K5, "What my grown-ups can see" (Appendix A): run as the kid, it explains exactly
  R-DATA-1 for that kid, in plain words, plus their last day's summary. See "The kid's screen"
  below for how it's reached.
- **`retention`** prunes usage days older than 1 year, `launches.log` lines and queue records older
  than 90 days. Root only. `DRY_RUN` is the default shape everywhere else in this package
  (AGENTS.md rule 8) — `retention` alone (no `--apply`) prints what it would remove; `--apply` makes
  it real. **Never touches the Chromium History db** — that's the browser's own retention, not this
  package's to manage (I-2/I-6).

No timer unit installs `retention` on a schedule — that's a real gap (see "Not built here").

## Who can read what

- **Minutes and launches**: unprivileged, for anyone who can read `/var/lib/omarchy-kids/` — same
  as `omarchy-kids-time status` and everything the panel already reads without a password
  (docs/panel.md's "Root and the one sudo prompt").
- **Sites**: a kid's Chromium profile lives under *their own home*, which the parent account can't
  otherwise reach. `sites` (and the sites half of `summary`) needs root, unless the caller *is* the
  kid whose data it is — a kid reading their own history needs no elevation. The panel calls this
  through `sudo` (`read_priv`, docs/panel.md) the one time it's actually needed; `mine` never needs
  root at all, since a kid is always reading their own.
- **`history_visible=no`** (Appendix B) short-circuits all of the above before anything is ever
  touched: `sites`, `summary`, and `mine` all check it first and say so in plain words — R-DATA-4,
  "off means the panel shows none and the kid's screen says so" — never a silent empty list, and
  never a privilege check that would otherwise ask for a password it wouldn't use.

## App launches: the kid-writable half (issue #27's own note on where a launch is logged)

A kid's own processes can never write into `/var/lib/omarchy-kids/` (I-3) — so, same shape as the
screen-time ledger (docs/time.md's "trust boundary"), recording a launch is two pieces:

1. **`bin/omarchy-kids-launcher-ctl log <id>`** — new in this issue. `share/launcher/shell.qml`'s
   `launchCurrent()` calls this, fire-and-forget, every time a Level 1 tile is opened. It appends
   one `"<local-timestamp> <id>"` line to *this account's own* `$XDG_RUNTIME_DIR/omarchy-kids/
   launches.log` — writable by the kid, because it's theirs; never the root-owned log a parent or
   the kid's own `mine` screen actually reads.
2. **`bin/omarchy-kids-time-ledger tick`** — already runs once a minute as root (docs/time.md).
   This issue adds one step to it: `lib/data.sh`'s `data_fold_launches`, which appends whatever's
   new in each known kid's own runtime log onto their root-owned `launches.log`, then remembers how
   far it got (`launches.offset`, `"<inode> <byte-offset>"`) so the same line is never folded twice.
   A fresh login gets a fresh runtime tmpfs at the same path — a new inode, and often a smaller
   file; either one on its own means "this is a new file", so the fold starts over from the
   beginning rather than treating it as corruption or silently skipping already-there-looking bytes.
   `systemd/omarchy-kids-time-ledger.service` deliberately does not set `ProtectHome=yes` for the
   same reason `omarchy-kids-ask-collect.service` doesn't (docs/ask.md): it hides `/run/user/*`
   from the unit, which is exactly where a kid's own runtime log lives.

**Only Level 1 tile launches are recorded.** Levels 2/3 run Omarchy's own app grid (R-DESK-4's
trimmed menu, `docs/apps.md`), which this package doesn't own — there's no launch hook to add one
to without editing a core Omarchy file (I-7). A real gap, not an oversight — see "Not built here".

Every append is one short `printf`, well under `PIPE_BUF`; `data_fold_launches` folds whatever
bytes exist each tick rather than trying to be exact against a line torn mid-write at that instant
— the same order of slop docs/time.md's own ledger already accepts for its resolution note.

## The kid's screen (K5, "What my grown-ups can see")

`omarchy-kids-data mine`, run as the kid, prints what this file's "What's recorded" table says, in
plain first-person words, plus "Since: <the earliest day on file>" and the kid's own last day's
summary. It's wired into the Level 1 launcher's tile grid as **"What grown-ups see"**, but only for
bands **9-12 and 13+** — the two bands the starter-pack table already gives a terminal to
(R-BAND's own Terminal column), i.e. old enough to read the screen unsupervised. This is gated on
**band**, not level: a 9-12/13+ kid moved to Level 1 by a `level` override still gets the tile in
that grid. 3-5/6-8 kids aren't denied the data — I-6 is about not showing a control that doesn't
work, not about withholding the data itself — a grown-up can run `omarchy-kids-data mine` with them
directly; this issue just doesn't add a tile a pre-reader or early reader couldn't use alone.

The tile's `exec` launches whatever terminal emulator it finds first on `PATH` (a best-effort guess
— **UNVERIFIED**, see "Not built here"), running `omarchy-kids-data mine` and waiting for Enter. If
no terminal is found, the tile is left out entirely (logged, not shown broken) — the same "don't
show a control that isn't enforced" pattern `bin/omarchy-kids-session-start`'s own R-WEB-4 chromium-
tile omission already uses.

## The panel's Data screen (P2, docs/panel.md)

Read-only: today's and this week's minutes/launches/top-apps/top-sites, via `omarchy-kids-data
summary`. Reading a kid's sites needs root — the panel's own `read_priv` (a dedicated `sudo`, once
per run, separate from every *write* screen's `run_priv`/`DRY_RUN` dance, since a read has nothing
useful for `--dry-run` to preview) — except when `history_visible=no`, which needs no password at
all, since `omarchy-kids-data` already refuses to touch Chromium in that case.

## Judgment calls

- **No terminal-emulator convention exists anywhere in this repo yet.** `bin/omarchy-kids-session-
  start`'s `kids-data` tile guesses from a short list (`kitty`, `alacritty`, `foot`, `wezterm`,
  `xterm`) and omits the tile if none is found, rather than inventing one or leaving a broken tile
  (I-6). Whichever terminal Omarchy actually ships is the one to hard-code here once known.
- **Retention numbers are the issue's own v1.1 update comment, not the "30 days" fallback the
  original brief offered as a default.** SPEC.md's R-DATA-1 does state numbers (1 year / 90 days /
  browser's own) as of spec v1.1 — AGENTS.md's "spec wins" rule applies directly, no ticket comment
  needed.
- **`summary`'s "today"/"this week" launch-and-site windows are pinned to the exact same 04:00
  logical-day boundary "minutes used" is already measured against** (Appendix F), not a rolling
  24h/7d window — so every figure on one screen agrees about what "today" means, even though the
  underlying `--since N days` filter (used by `launches`/`sites` directly) is a plain rolling window.
- **`sites`/`summary`'s top-sites grouping is by host (`urlsplit(url).netloc`), not full URL.** A
  parent or a kid asking "what sites" almost always means "which sites", not "which exact pages" —
  `launches`'s own per-visit `sites` output still shows the full page title per row for anyone who
  wants that detail.
- **Chromium's `urls` table is read directly, no join against `visits`.** `last_visit_time` and
  `visit_count` already live on `urls` itself (this issue's own "Chromium facts") — a `visits` join
  would give per-visit rows instead of per-URL summaries, which nothing here needs.

## Not built here

- **No timer runs `retention` automatically.** A parent (or a future daily systemd timer, mirroring
  `systemd/omarchy-kids-time.timer`) has to run `omarchy-kids-data retention --apply` themselves for
  now.
- **Level 2/3 app launches aren't recorded at all** — only Level 1 tiles are (see above). A future
  issue would need either a real Omarchy launch hook or a menu-extension-side log call, neither of
  which exists yet.
- **The Level 1 `kids-data` tile's terminal choice is unverified** — no Quickshell/terminal
  integration in this repo has run against a real session yet (same caveat every other
  `share/launcher/shell.qml` feature carries — see that file's own header).
- **No export command.** A parent who wants a copy of a kid's recorded data today reads it through
  the panel or runs `omarchy-kids-data summary`/`launches`/`sites` themselves and copies the output;
  there's no `--json`/`--csv` flag.
- **No `PRIVACY.md`.** R-DATA-5 ("`PRIVACY.md` states all of this in plain words") isn't delivered
  by this issue — there's no `PRIVACY.md` anywhere in this checkout, and `AGENTS.md`'s own file-
  layout table doesn't list one either, so it isn't clear whether it belongs in this repo or the
  hub (`PATH-SANDBOX.md`'s home, per `AGENTS.md`'s "Hub and decisions" line). This doc (`docs/
  data.md`) carries R-DATA-5's content in the meantime — what's recorded, where, who can read it,
  retention, and export/delete, all below — until that's settled.

## How a parent exports or deletes

**Export:** everything `omarchy-kids-data` reads is plain text on stdout — `omarchy-kids-data
summary <kid> --week > week.txt`, or `sudo omarchy-kids-data sites <kid> > sites.txt`, is the whole
export story today (see "Not built here" above for why there's no dedicated flag).

**Delete:**

- **A kid's browsing history**: `sudo omarchy-kids-provision remove <kid> --apply` (R-FND-6,
  docs/provision.md) moves that kid's whole home — Chromium profile included — under
  `~parent/Kids Mode/<name>/`. It does not delete it — moves, same as every other removal in this
  package (R-TRUST-4's "keeps every kid's files").
- **A kid's usage/launches under `/var/lib/omarchy-kids/<kid>/` is not touched by `provision
  remove` at all** — that command only moves the home directory (verified by reading its own
  `cmd_remove`). A real gap: today, removing a kid leaves their `usage/`, `launches.log`, and
  `launches.offset` behind under `/var/lib/omarchy-kids/<kid>/` with no account left to own them.
  Until a future issue folds this into `provision remove` (or a `retention --forget <kid>`), a
  parent who wants it gone runs `sudo rm -rf /var/lib/omarchy-kids/<kid>/` themselves.
- **Just what's past retention**: `sudo omarchy-kids-data retention --apply` (above).
- **Just browsing history**: R-WEB-2 sets `AllowDeletingBrowserHistory: false` on purpose (a kid
  can't quietly clear their own trail) — a parent clears it themselves from inside Chromium on the
  kid's account (`chrome://history` → Clear browsing data), the same as clearing anyone's Chromium
  history; nothing in this package manages that db's contents directly (I-2/I-6, same reasoning as
  "never pruned by `retention`" above).

## File locations (overridable for tests, same convention as `docs/time.md`/`docs/panel.md`)

| What | Default path | Env override |
| --- | --- | --- |
| Kid overrides directory (`history_visible`, Appendix B) | `/etc/omarchy-kids/kids/` | `OMARCHY_KIDS_ETC` |
| Usage, launches, launches.offset, the ask queue | `/var/lib/omarchy-kids/` | `OMARCHY_KIDS_ROOT` (scratch prefix) |
| A kid's runtime launches log (`launcher-ctl log`'s target) | `$XDG_RUNTIME_DIR/omarchy-kids/launches.log` | `OMARCHY_KIDS_LAUNCHES_LOG`, or `XDG_RUNTIME_DIR` |
| A kid's runtime log, as seen by root folding it | `/run/user/<uid>/omarchy-kids/launches.log` | `OMARCHY_KIDS_RUN_USER_BASE` (default `/run/user`) + `OMARCHY_KIDS_ROOT` |
| A kid's home (for `sites`) | `/home/<kid>` | `OMARCHY_KIDS_HOMES_BASE` (default `/home`) |
| `lib/data.py` | `lib/` beside `bin/`, else `/usr/lib/omarchy-kids` | `OMARCHY_KIDS_DATA_PY` / `OMARCHY_KIDS_LIB` |
| `omarchy-kids-data` (called by the panel and the Level 1 tile) | resolved beside the caller, else `PATH` | `OMARCHY_KIDS_DATA_BIN` |

`test/shell.d/data-test.sh` covers `launches`/`sites`/`summary`/`mine`/`retention`, the
`history_visible` gate, the root-vs-self check on `sites`, `launcher-ctl log`, and the ledger's
launch-log fold (including the dedup-by-offset and fresh-login-reset cases) — a fixture launches
log, a small fixture Chromium `History` db built by python3 (this issue's own "Chromium facts"),
and a temp root throughout; no real Unix accounts, per AGENTS.md rule 8.
