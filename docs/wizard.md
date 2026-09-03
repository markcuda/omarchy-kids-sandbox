# The parent wizard's Easy path: `bin/omarchy-kids-wizard` (SPEC.md R-WIZ-1..9; issue #19)

Five minutes, no terminal knowledge, sensible defaults: a parent types their kid's name, picks an
age band, sets a password, sees a plain-words summary of what's about to happen, and applies it.
Every screen is rendered by `lib/tui.sh` (issue #18, `docs/tui.md`) — this file never calls `gum`
directly, and it drives entirely through `OMARCHY_KIDS_TUI_ANSWERS` in tests, same as that
library's own demo and test suite.

## Running it

```text
omarchy-kids-wizard [--dry-run] [--help]
```

`omarchy-kids` (the app entry point) opens this automatically when no kid has been provisioned
yet; `omarchy-kids wizard` always opens it, to add another kid (R-WIZ-7). `DRY_RUN=1` is the
default everywhere Apply would write something (AGENTS.md rule 8): every command Apply would run
is printed instead of run. There's no separate `--apply` confirmation flag on this command —
the summary screen (A13) *is* the confirmation; set `DRY_RUN=0` (or pass `--apply`) for the wizard
you launch to make a real run.

## The screens, in order

| Step | Screen | What happens |
| --- | --- | --- |
| 1 | Welcome | Omy's line and three bullets; **Begin** is the only choice (SPEC A1). |
| 2 | Name | Letters, spaces, and hyphens, 1-24 characters; previews the `kid-<slug>` account name via `omarchy-kids-conf slug`. |
| 3 | Age band | 3-5 / 6-8 / 9-12 / 13+, each with its `bands.toml` blurb as the reason line. **Prefetch starts here** (see below) and never blocks. |
| 4 | Simple or Advanced | Simple is the only real path here; choosing Advanced explains it's coming next (issue #20) and re-shows this screen. |
| 5 | Kid's password | Twice, masked. Band 3-5 gets an extra "set a password or not" choice first (R-BAND's `password_optional`); every other band always sets one. Explains what it unlocks. |
| 6 | Summary | A plain-words table — account, age band, desktop level, web mode, screen time, bedtime, starter apps, password — from `bands.toml`/`packs/<band>.toml`, then **Apply** or **Change something**. |
| 7 | Apply | One parent-password prompt, then a step-by-step progress dashboard (`tui_progress`, R-WIZ-5): the account, the web policy, the starter pack, and a safety check. |
| 8 | Done | Omy's line; **Return to my desktop** or **Open `<Name>`'s desktop** (R-WIZ-6). |

Every screen up through the Summary is keyboard-complete: Esc goes back one screen (re-asking
whatever was there), Ctrl+C asks to confirm leaving and, if confirmed, exits `130` having run
nothing. Once Apply actually starts running commands (after the one parent-password prompt), the
run is committed — same as the installer's own dashboard never lets you cancel mid-write.

## What this issue does not build

SPEC.md's Appendix A describes a longer flow than this: a parent-password screen right after
Welcome (A2), a face/avatar picker (A4), and five separate one-choice screens for web, screen
time, apps, Wi-Fi, and desktop level (A7-A11), each shown before the summary. Issue #19's own
brief scopes this wizard down to what's above instead — the band's sensible defaults for all of
those, shown once on the summary screen, with the one parent-password prompt moved to right
before Apply (where root is actually needed) rather than the top of the flow. Consequences worth
being explicit about:

- **Avatar** always defaults to `fox` — the same default `bin/omarchy-kids-provision`'s own
  `cmd_add` already falls back to (see its own "Judgment calls": no avatar SVGs are shipped yet
  either). No `--avatar` flag is passed.
- **Web mode, screen time, bedtime, starter apps, and level** are always the band's default;
  there's no "let me pick" checklist screen here (that needs a multi-select widget `lib/tui.sh`
  doesn't have yet — `tui_screen_choose` is one-of-many, not a checklist). Advanced (A13a) is
  where per-cell picking belongs, and that's issue #20.
- **Advanced** is a dead end on purpose: choosing it explains it's coming next and re-shows the
  same screen, rather than exiting or half-building a table this issue doesn't implement.

## Root and the one sudo prompt

The wizard itself never needs root — reading `bands.toml`/`packs/` and rendering screens is all
unprivileged. Apply is the one place a real system change happens, so it's the one place
`sudo` is used, and only once: right after the parent-password screen, `sudo -S -p '' -v` spends
that same password to warm sudo's credential cache (or, in `--dry-run`, just prints `sudo -v`).
Every subsequent Apply command (`run_priv`/`run_priv_stdin`/`run_priv_as` below) is then a plain
`sudo <command>`, which shouldn't prompt again inside that cached window. This needs the parent's
account to actually be in `sudoers`/`wheel` with the usual Arch/Omarchy defaults — verifying that
assumption, and that the single warm-up prompt really does cover the whole Apply sequence with no
surprise second prompt, needs a real terminal (or the test laptop/VM): `test/shell.d/wizard-test.sh`
only exercises `--dry-run`, where `sudo` is never actually invoked.

## Prefetch (R-WIZ-4): a known gap

Prefetch is supposed to start on the age screen through "a root helper" so it never needs its own
password prompt. No such helper exists in this repo yet (there's no polkit action or sudoers
NOPASSWD line for `pacman -Sw`), and popping an *unplanned* second password prompt this early
would break the "one parent-password prompt, right before Apply" brief. So a real (non-dry-run)
run only starts the background `pacman -Sw --noconfirm <band's repo packages>` when `sudo -n true`
already succeeds (an already-cached credential from some earlier `sudo` in the same terminal
session); otherwise it prints a one-line note and skips prefetching, falling back to Apply's own
"install from cache" step downloading fresh instead — no different in effect from R-APPS-8's
"offline: complete and defer" fallback, just a different reason. Fixing this for real (a root
helper, or a sudoers drop-in scoped to exactly `pacman -Sw` for the `omarchy-kids` group) is
follow-on work, not part of this issue. Ctrl+C before Apply kills the background prefetch job if
one is running (`stop_prefetch`, on an `EXIT` trap) — SPEC's own "abort it on Ctrl+C".

## The safety check

Apply's last step runs two things and shows both outputs directly: `omarchy-kids-assert`
(SPEC I-4, `docs/assert.md`) reasserts every lock and prints one `ok`/`fixed`/`FAIL` line per
check; `sudo -u <account> omarchy-kids-session --check` (`docs/session.md`) runs the same R-DESK-2
preflight the kid's own real login would run, as the kid's own account, and prints its own
PASS/FAIL/WARN table. Running the second one *as* the new account (rather than the parent) is
what makes it check the right kid's facts — `omarchy-kids-session --check` figures out which
account it's checking via `id -un`.

## Open `<Name>`'s desktop, on Done

R-WIZ-6 wants this to switch the parent's own session to a live preview of the kid's desktop.
No such switch exists on this box yet — `bin/omarchy-kids-exit --finish` ends a *kid's own*
session from inside it (`docs/exit.md`); there's nothing today that starts one as a preview from
the parent's side, and that file's own header notes `Seat.SwitchToGreeter()` outright fails on
Omarchy 4.0.2 while a session is live. So choosing "Open `<Name>`'s desktop" here just explains
that plainly and returns: `<Name>` logs in from the portal next time the screen locks or the
computer starts. Building a real preview switch is separate, later work.

## The answers-file layout

Every screen is driven by `lib/tui.sh`'s `OMARCHY_KIDS_TUI_ANSWERS` (`docs/tui.md`): one answer
per line, `@esc`/`@ctrlc` for the two keys a file can't press. A full happy-path run, band 6-8,
with a password:

```text
begin              # Welcome
Ada                # Name
6-8                # Age band
simple             # Simple or Advanced
secret1            # Kid password
secret1            # Kid password, again
apply              # Summary: Apply (not "Change something")
parentpw123        # The one parent-password prompt, right before Apply
parent             # Done: "Return to my desktop"
```

Band 3-5 inserts one extra line right after the band screen (`yes`/`no`, for "set a password?"):

```text
begin
Zoe
3-5
simple
no                 # no password for this band
apply
parentpw123
parent
```

`test/shell.d/wizard-test.sh` builds these programmatically and checks the exact `[dry-run] sudo
...` lines Apply prints for each — provision's flags, the web install call, the pacman install
line, and the two safety-check commands — plus name validation, Esc-back from the band screen to
the name screen, and that Ctrl+C before Apply prints no command at all.

## Every path is overridable, same convention as the rest of `bin/`

| Env var | Default | What |
| --- | --- | --- |
| `OMARCHY_KIDS_ETC` | `/etc/omarchy-kids` | kid profiles (only read, to preview slug collisions) |
| `OMARCHY_KIDS_SHARE` | `/usr/share/omarchy-kids` | `bands.toml`, `packs/<band>.toml` |
| `OMARCHY_KIDS_LIB` | `lib/` beside `bin/`, else `/usr/lib/omarchy-kids` | `lib/conf.sh`, `lib/tui.sh` |
| `OMARCHY_KIDS_CONF_BIN` | sibling `bin/omarchy-kids-conf`, else `PATH` | reading bands/packs |
| `OMARCHY_KIDS_PROVISION_BIN` | sibling `bin/omarchy-kids-provision`, else `PATH` | Apply's account step |
| `OMARCHY_KIDS_WEB_BIN` | sibling `bin/omarchy-kids-web`, else `PATH` | Apply's web-policy step |
| `OMARCHY_KIDS_ASSERT_BIN` | sibling `bin/omarchy-kids-assert`, else `PATH` | the safety check |
| `OMARCHY_KIDS_SESSION_BIN` | sibling `bin/omarchy-kids-session`, else `PATH` | the safety check's `--check` |
| `OMARCHY_KIDS_AUTH_SOCK` | `/run/omarchy-kids/auth.sock` | independent parent-password verification, if `omarchy-kids-authd` is running (`docs/authd.md`) |
| `OMARCHY_KIDS_SETUP_LOG` | `/var/log/omarchy-kids/setup.log` | named in Apply's tip line (R-WIZ-5); nothing here writes to it yet — a later issue's job |
| `OMARCHY_KIDS_TUI_ANSWERS` | (unset — real terminal) | see `docs/tui.md` |
| `DRY_RUN` | `1` | `0` (or `--apply`) makes Apply real |

## Parent-password verification

The one parent-password prompt, right before Apply, tries `verify_parent_password` first: the
same one-line-in, `ok`/`no`-back protocol `bin/omarchy-kids-parent-auth` speaks to
`omarchy-kids-authd` (`docs/authd.md`), against `OMARCHY_KIDS_AUTH_SOCK`. If that socket doesn't
exist — a dev box, or a machine where the socket-activated service hasn't started — this can't
verify anything on its own and doesn't try to fake it: the password is accepted here and it's
`omarchy-kids-provision add --parent-password-stdin` that actually checks it, but only when a
LUKS slot is in play (`docs/provision.md`). On a real machine, `omarchy-kids-authd` should always
be running (its socket is enabled by the package), so the direct check is the one a parent
actually sees in practice.
