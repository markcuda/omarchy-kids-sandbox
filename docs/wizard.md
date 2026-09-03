# The parent wizard's Easy path: `bin/omarchy-kids-wizard` (SPEC.md R-WIZ-1..9, Appendix A; issue #19)

Five minutes, no terminal knowledge, sensible defaults: a parent types their kid's name, picks a
face and an age band, walks five one-choice screens with the band's default already picked, sets
a password, sees a plain-words summary of what's about to happen, and applies it. Every screen is
rendered by `lib/tui.sh` (issue #18, `docs/tui.md`) — this file never calls `gum` directly, and it
drives entirely through `OMARCHY_KIDS_TUI_ANSWERS` in tests, same as that library's own demo and
test suite.

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

## The screens, in Appendix A order

| Step | Appendix A | Screen | What happens |
| --- | --- | --- | --- |
| 1 | A1 | Welcome | Omy's line and three bullets; **Begin** is the only choice. |
| 2 | A2 | Parent password | Right after Welcome. Verified against `omarchy-kids-authd`, the same protocol `bin/omarchy-kids-parent-auth` speaks (`docs/authd.md`), when that verifier is reachable; kept in memory (never written anywhere) and reused for the one sudo prompt at Apply. |
| 3 | A3 | Name | Letters, spaces, and hyphens, 1-24 characters; previews the `kid-<slug>` account name via `omarchy-kids-conf slug`. |
| 4 | A4 | Face | One of the twelve `share/avatars/*.svg` animals (Q18), as a keyboard list — `lib/tui.sh` has no separate grid widget, and a list is exactly as keyboard-complete. |
| 5 | A5 | Age band | 3-5 / 6-8 / 9-12 / 13+, each with its `bands.toml` blurb as the reason line. **Prefetch starts here** (see below) and never blocks. |
| 6 | A6 | Simple or Advanced | Simple is the only real path here; choosing Advanced explains it's coming next (issue #20) and re-shows this screen. |
| 7 | A7 | Web | Two options, band-appropriate, band default preselected: 3-5 sees no-browser vs. a short allowed list; 6-8/9-12 see the walled garden vs. filtered open web; 13+ sees filtered open web vs. the walled garden. |
| 8 | A8 | Screen time | The band's minutes-a-day and lights-out, or "I'll set my own" (two follow-up fields, each validated). |
| 9 | A9 | Apps | "The `<band>` starter pack" (every app), or "Let me pick" — a yes/no per app, one at a time (there's no multi-select checklist widget in `lib/tui.sh` yet; that's Advanced's, A13a, issue #20). |
| 10 | A10 | Wi-Fi | "Ask me first" (`parent`) vs. "On their own, safely" (`helper`), band default preselected. |
| 11 | A11 | Desktop level | 1 / 2 / 3, each with a one-liner, band default preselected. |
| 12 | A12 | Kid's password | Twice, masked. Band 3-5 gets an extra "set a password or not" choice first (R-BAND's `password_optional`); every other band always sets one. Explains what it unlocks. |
| 13 | A13 | Summary | A plain-words table — account, face, age band, desktop level, web mode, screen time, bedtime, Wi-Fi, starter apps, password — then **Apply** or **Change something**. |
| 14 | A13b/A13c | Apply | A step-by-step progress dashboard (`tui_progress`, R-WIZ-5): the account (plus any A7-A11 choice that overrides the band default), the web policy, the starter pack, and the safety check (A13c). |
| 15 | A14 | Done | Omy's line; **Return to my desktop** or **Open `<Name>`'s desktop** (R-WIZ-6). |

Every screen up through the Summary is keyboard-complete: Esc goes back one screen (re-asking
whatever was there), Ctrl+C asks to confirm leaving and, if confirmed, exits `130` having run
nothing. Once Apply actually starts running commands, the run is committed — same as the
installer's own dashboard never lets you cancel mid-write. The apps checklist (A9's "Let me pick")
is the one place Esc and "No" are genuinely the same outcome per app — `tui_screen_confirm`'s own
contract — since there's no meaningful "go back" mid-checklist; either way just leaves that one app
out and moves to the next.

Advanced (A13a's per-cell checklist) is issue #20: choosing Advanced on A6 explains that plainly
and re-shows A6, rather than exiting or half-building a table this issue doesn't implement.

## Root and the one sudo prompt

The wizard itself never needs root — reading `bands.toml`/`packs/`/`avatars/` and rendering
screens is all unprivileged. Apply is the one place a real system change happens, so it's the one
place `sudo` is used, and only once: right at the start of Apply, `sudo -S -p '' -v` spends the
password collected back at A2 to warm sudo's credential cache (or, in `--dry-run`, just prints
`sudo -v`). Every subsequent Apply command (`run_priv`/`run_priv_stdin`/`run_priv_as`, called from
one of the five `apply_step_*` functions) is then a plain `sudo <command>`, which shouldn't prompt
again inside that cached window. This needs the parent's account to actually be in
`sudoers`/`wheel` with the usual Arch/Omarchy defaults — verifying that assumption, and that the
single A2 password really does cover the whole Apply sequence with no surprise second prompt,
needs a real terminal (or the test laptop/VM): `test/shell.d/wizard-test.sh` exercises both
`--dry-run` (where `sudo` is never actually invoked) and `DRY_RUN=0` against a fake `sudo` that
really execs its argv, but neither one is a real `sudoers` file.

**A VM run once got past every command below with every dashboard row showing ✓, yet `kid-ben`
was never actually created.** Root cause: `DRY_RUN=0` in the wizard's own environment does not
cross `sudo` into the child process at all (a fresh `sudo` invocation starts a fresh environment
unless the target's `sudoers` config explicitly keeps a variable, which none here do), and every
downstream command — `omarchy-kids-provision`, `omarchy-kids-web install`, `omarchy-kids-apps
install` — defaults to `DRY_RUN=1` and only actually writes anything when it sees its own
`--apply` on argv. So every `run_priv`/`run_priv_stdin` call in this file passes `--apply`
literally, on the command line, to every one of those three commands (see `apply_step_account`,
`apply_step_web`, `apply_step_pkgs`) — never the environment, which is the one thing that reliably
survives a `sudo` boundary. `omarchy-kids-assert` doesn't need this (it defaults to *acting* for
real and only previews with its own `--dry-run`, the one command in `bin/` that inverts the usual
convention — see `docs/assert.md`), and `omarchy-kids-conf set` has no dry-run concept at all,
so neither of those two needed a fix here.

## Prefetch (R-WIZ-4): a known gap

Prefetch is supposed to start on the age screen through "a root helper" so it never needs its own
password prompt. No such helper exists in this repo yet (there's no polkit action or sudoers
NOPASSWD line for `pacman -Sw`), so a real (non-dry-run) run only starts the background
`pacman -Sw --noconfirm <band's repo packages>` when `sudo -n true` already succeeds — which, since
A2 (the parent password) comes before A5 (the age screen), is often true in practice, because A2's
own verification step doesn't itself warm sudo's cache, but a parent who has used `sudo` anywhere
else in the same terminal session recently may already have one. When there isn't a cached
credential, prefetch prints a one-line note and skips, falling back to Apply's own "install from
cache" step downloading fresh instead — no different in effect from R-APPS-8's "offline: complete
and defer" fallback, just a different reason. Fixing this for real (a root helper, or a sudoers
drop-in scoped to exactly `pacman -Sw` for the `omarchy-kids` group) is follow-on work, not part of
this issue. Ctrl+C before Apply kills the background prefetch job if one is running
(`stop_prefetch`, on an `EXIT` trap) — SPEC's own "abort it on Ctrl+C". Prefetch always downloads
the *whole* band pack via a raw `pacman -Sw` (not `omarchy-kids-apps`, which has no download-only
mode) regardless of what the A9 apps screen later picks — R-WIZ-4's own words, "changed selections
need no undo" — Apply's own install step (below) installs the whole pack too; only the allowlist
override A9 writes actually restricts what the kid sees in their launcher.

## Apply's five steps: exit codes, stopping on failure, and the technical log

Each of Apply's five dashboard rows is one function (`apply_step_getok`, `apply_step_account`,
`apply_step_web`, `apply_step_pkgs`, `apply_step_safety`), and `run_apply_step` is the one place
that runs one, decides ✓ or ✗, and does something about it:

- **✓/✗ is the step's own real exit code**, not "we got this far without the script itself
  crashing." `run_apply_step` captures it through `PIPESTATUS[0]`, which stays correct regardless
  of `pipefail`, even though the step's output is piped through `tee` on the way to the screen and
  the log (below) — a step that printed a happy-looking line but exited non-zero still shows ✗.
- **The dashboard stops at the first ✗** (real runs only — every `--dry-run` step "succeeds",
  there being nothing real to fail): the remaining rows print as `·` (never attempted, never
  claimed to be), the failing command's last ten lines print under the dashboard, and Done's
  headline names which step it was ("Setup stopped at ...") instead of claiming the desktop is
  ready.
- **The technical log** (R-WIZ-5's tip line, `$SETUP_LOG`, default `/var/log/omarchy-kids/setup.log`)
  is now actually written on a real run, not just named: `apply_step_getok` creates its directory
  (`sudo install -d`, since a parent's own unprivileged wizard process can't create anything under
  `/var/log` itself), and every step's combined output is piped through `sudo tee -a "$SETUP_LOG"`
  on its way to the screen — a second, separate `sudo` call from the step's own (already-elevated)
  command, which the A2-warmed credential cache covers the same way it covers everything else. A
  `--dry-run` never touches this file at all; the tip line only mentions it after the real dashboard
  finishes.

## The safety check

Apply's last step (`apply_step_safety`) runs two things and shows both outputs directly:
`omarchy-kids-assert` (SPEC I-4, `docs/assert.md`) reasserts every lock and prints one
`ok`/`fixed`/`FAIL` line per check; `sudo -u <account> omarchy-kids-session --check`
(`docs/session.md`) runs the same R-DESK-2 preflight the kid's own real login would run, as the
kid's own account, and prints its own PASS/FAIL/WARN table. Running the second one *as* the new
account (rather than the parent) is what makes it check the right kid's facts —
`omarchy-kids-session --check` figures out which account it's checking via `id -un`. On a real run
(never in `--dry-run`, where there's nothing real to check), this step first checks that the
account genuinely exists (`id "$ACCOUNT"`); if it doesn't, it prints one line explaining that and
skips the `sudo -u` call entirely, rather than handing `sudo` a user that was never created and
getting back a confusing "no such user" error. In practice `apply_step_account` failing would
already have stopped the whole dashboard before this step ever runs — this is belt-and-suspenders
for exactly that kind of gap, not the primary defense.

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
per line, `@esc`/`@ctrlc` for the two keys a file can't press.

### Which token a choose screen (A1, A5-A11, A13, A14) accepts

Every one of this wizard's choice screens is `tui_screen_choose` (`docs/tui.md`), and it matches a
line against exactly four things for each option, in this order: the option's **value** (the short
id shown before `|` in this file's own `choices=(...)` arrays — e.g. Done's two options are
`parent|Return to my desktop|` and `kid|Open <Name>'s desktop|`), its **label** verbatim (e.g.
`Return to my desktop`, capital R, no trailing period), the **whole rendered line** verbatim
(`1) Return to my desktop`), or a bare **1-based number** (`1`). Nothing else matches — not a
lowercase or partial label, not the first word of one. Typing `return` for Done's first option
does **not** match anything (it's not the value, not the label, not the numbered line) and fails
the run with `tui: 'return' does not match any choice on 'Done'`; the value `parent` does. This
file's own examples always use each screen's **value**, since those are what's shortest and least
likely to collide with another screen's own value (Wi-Fi's A10 also happens to use `parent` as a
value, for "Ask me first" — a coincidence with Done's `parent`, not a bug: they're different
screens, so there's no ambiguity in an actual answers file, only when reading two screens' values
side by side out of context, as in the examples below).

A full happy-path run, band 6-8, with a password and every A7-A11 choice left at its band default:

```text
begin              # A1 Welcome
parentpw123        # A2 Parent password
Ada                # A3 Name
fox                # A4 Face
6-8                # A5 Age band
simple             # A6 Simple or Advanced
garden             # A7 Web (6-8's default)
default            # A8 Screen time ("the usual" — not "I'll set my own")
pack               # A9 Apps (the whole starter pack, not "let me pick")
parent             # A10 Wi-Fi (6-8's default)
1                  # A11 Desktop level (6-8's default)
secret1            # A12 Kid password
secret1            # A12 Kid password, again
apply              # A13 Summary: Apply (not "Change something")
parent             # A14 Done: "Return to my desktop"
```

Band 3-5 inserts one extra line right after A11 (`yes`/`no`, for A12's "set a password?"):

```text
begin
parentpw123
Zoe
fox
3-5
simple
none
default
pack
parent
1
no                 # no password for this band
apply
parent
```

Picking "I'll set my own" at A8 inserts two more lines (minutes, then lights-out); picking
"Let me pick" at A9 inserts one `yes`/`no` line per app in the band's starter pack, in pack order.
`test/shell.d/wizard-test.sh` builds every one of these programmatically under `--dry-run` and
checks the exact `[dry-run] sudo ...` lines Apply prints — provision's flags (`--apply` and the
face included), the `omarchy-kids-conf set` override lines for any A7/A10/A11 choice that differs
from the band default (and their absence when every choice matches the default — R-BAND-2), the
web install call (also with `--apply`), and the `omarchy-kids-apps install <band> --now --apply`
call (always the whole band pack, regardless of A9's pick — see "Apply's five steps" above) — plus
name validation, the A8/A9 branches, Esc-back, and that Ctrl+C right after Welcome prints no
command at all. A separate block of scenarios runs with `DRY_RUN=0` against a fake `sudo` that
actually execs its argv, to check the things `--dry-run` can't: a failing step showing ✗ and
stopping the dashboard before any later step runs, the failing command's tail on screen, the
technical log actually gaining that same content, and the safety check's account-existence guard.

## Every path is overridable, same convention as the rest of `bin/`

| Env var | Default | What |
| --- | --- | --- |
| `OMARCHY_KIDS_ETC` | `/etc/omarchy-kids` | kid profiles (only read, to preview slug collisions) |
| `OMARCHY_KIDS_SHARE` | `/usr/share/omarchy-kids` | `bands.toml`, `packs/<band>.toml`, `avatars/*.svg` |
| `OMARCHY_KIDS_LIB` | `lib/` beside `bin/`, else `/usr/lib/omarchy-kids` | `lib/conf.sh`, `lib/tui.sh`, `lib/conf.py` (the apps checklist's `pack-app` lookups) |
| `OMARCHY_KIDS_CONF_BIN` | sibling `bin/omarchy-kids-conf`, else `PATH` | reading bands/packs, writing A7/A10/A11 overrides |
| `OMARCHY_KIDS_CONF_PY` | `python3` | running `lib/conf.py` directly for the A9 checklist |
| `OMARCHY_KIDS_PROVISION_BIN` | sibling `bin/omarchy-kids-provision`, else `PATH` | Apply's account step |
| `OMARCHY_KIDS_WEB_BIN` | sibling `bin/omarchy-kids-web`, else `PATH` | Apply's web-policy step |
| `OMARCHY_KIDS_ASSERT_BIN` | sibling `bin/omarchy-kids-assert`, else `PATH` | the safety check |
| `OMARCHY_KIDS_SESSION_BIN` | sibling `bin/omarchy-kids-session`, else `PATH` | the safety check's `--check` |
| `OMARCHY_KIDS_APPS_BIN` | sibling `bin/omarchy-kids-apps`, else `PATH` | Apply's starter-pack install step (issue #24) |
| `OMARCHY_KIDS_AUTH_SOCK` | `/run/omarchy-kids/auth.sock` | A2's parent-password verification, if `omarchy-kids-authd` is running (`docs/authd.md`) |
| `OMARCHY_KIDS_SETUP_LOG` | `/var/log/omarchy-kids/setup.log` | Apply's technical log (see "Apply's five steps" above) — a real run writes it; `--dry-run` never does |
| `OMARCHY_KIDS_TUI_ANSWERS` | (unset — real terminal) | see `docs/tui.md` |
| `DRY_RUN` | `1` | `0` (or `--apply`) makes Apply real |

## Parent-password verification (A2)

A2 tries `verify_parent_password` first: the same one-line-in, `ok`/`no`-back protocol
`bin/omarchy-kids-parent-auth` speaks to `omarchy-kids-authd` (`docs/authd.md`), against
`OMARCHY_KIDS_AUTH_SOCK`. If that socket doesn't exist — a dev box, or a machine where the
socket-activated service hasn't started — this can't verify anything on its own and doesn't try to
fake it: the password is accepted, and `omarchy-kids-provision add --parent-password-stdin` (at
Apply) is the backstop check, but only when a LUKS slot is actually in play
(`docs/provision.md`). `--dry-run` skips this check entirely and always accepts, as intended — a
dry run shouldn't need a real `omarchy-kids-authd` on the box it's run from. On a real machine,
`omarchy-kids-authd` should always be running (its socket is enabled by the package), so the
direct check is the one a parent actually sees in practice.

## Verified live (2026-09-02, QEMU test VM)

Driven by an answers file over `ssh -tt` (sudo's ticket is per-tty): all fifteen screens
rendered, Apply provisioned Ben (account, LUKS slot 3, band 6-8, avatar owl, the portal
override file updated), and a cold boot with Ben's disk password went straight to Ben's
Level 1 launcher. Two things the first run taught: `DRY_RUN=0` does not cross `sudo`, so every
repo command gets its own `--apply` flag now, and the step marks follow real exit codes. The
last provisioning step, Omarchy's own `omarchy-provision-user`, fails on this VM (no offline
Node tarball) and is a warning with the migrations fallback since then.
