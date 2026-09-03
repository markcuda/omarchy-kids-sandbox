# Review — omarchy-kids-sandbox @ 63d7c84

Read against Omarchy v4.0.2 (`bin/omarchy-theme-set`, `bin/omarchy-system-logout`,
`bin/omarchy-menu`, `default/hypr/helpers.lua`) as the house style. Calibration point:
`omarchy-theme-set` is 346 lines with a 9-line worst-case comment block and no duplicated
helpers; `omarchy-system-logout` is 13 lines. This repo is 13,239 lines of bash/shell with
3,467 comment lines — **26% of every shell file is comment**, and seven files carry headers
of 60–100 lines before the first statement.

`test/all` is green (29 files) and `shellcheck -x` on `bin/` + `lib/` is clean. The problems
below are not lint.

---

## 1. The ten changes with the highest payoff

### 1. The parent password is not a gate — a kid can grant themselves anything

`bin/omarchy-kids-ask:212-235`, `bin/omarchy-kids-ask:354-360`, `share/ask/shell.qml:117-142`

`cmd_submit` writes a record with `--state approved` into `$XDG_RUNTIME_DIR/omarchy-kids/ask-outbox/`
— a directory owned and writable by the kid. `cmd_collect`, running as root from
`omarchy-kids-ask-collect.timer` every minute, globs those directories and at line 358 does
`if [[ "$state" == "approved" ]]; then apply_record`. The only thing that ever checks a parent
password is `share/ask/shell.qml`, a QML process running as the kid, which on `exitCode === 0`
calls `submitApproved()`.

There is no authentication anywhere in the chain that reaches root. A kid with a terminal
(bands 9-12 and 13+ have one, R-BAND) runs `omarchy-kids-ask submit time 600 --state approved
--by keyboard` and root grants ten hours within sixty seconds. They do not even need that
command — a hand-written JSON file in their own outbox does it.

**Do:** root must decide, not observe. `collect` may only ever promote a record to `open`.
Approval has to be an action taken by a root-side path that itself verified the password
(`authd` returning a single-use token bound to the record's hash, consumed by `collect`), or by
the panel. Delete `--state approved` from `submit` entirely.

**Why a maintainer cares:** this is the product. Screen time, app installs and site allowances
are the whole feature set, and all three are self-service.

### 2. The verifier a kid runs is a verifier a kid controls

`bin/omarchy-kids-parent-auth:11`, `share/ask/shell.qml:108`, `share/exit-modal/shell.qml:151`,
`share/wifi/shell.qml:148`, `lib/posture.sh:221`

Every parent-password prompt inside a kid's session invokes `omarchy-kids-parent-auth` **by bare
name** (`command: ["omarchy-kids-parent-auth"]`), resolved through the kid's own `PATH`. The
helper then reads its socket path from `${OMARCHY_KIDS_AUTH_SOCK:-...}` — the kid's own
environment. Two independent one-line bypasses: drop an executable of that name earlier on
`PATH` that `exit 0`s, or point the env var at a socket that answers `ok`.

This is not confined to QML. `lib/posture.sh:221` installs
`auth [success=done default=ignore] pam_exec.so quiet expose_authtok /usr/bin/omarchy-kids-parent-auth`
into `omarchy-lock-password`. hyprlock runs as the kid, so pam_exec inherits the kid's
environment: `OMARCHY_KIDS_AUTH_SOCK` pointed at a listener that says `ok` makes the lock screen
accept any password, and `success=done` ends the stack before pam_unix is consulted.

**Do:** absolute paths at every call site; make `parent-auth` ignore `OMARCHY_KIDS_AUTH_SOCK`
unless `geteuid()==0`. Longer term, an exit code from a process the kid owns cannot be an
authorization result — see #1.

### 3. `limine-editor` is asserted only on machines that have the boot hook

`bin/omarchy-kids-assert:680-683`

```text
if [[ -f "$HOOK_FILE" ]]; then
    assert_one "boot-hook" boot_hook_ok boot_hook_fix
assert_one "limine-editor" limine_editor_ok limine_editor_fix
fi
```text

The second `assert_one` is indented as though it were outside the `if`; it is inside it. The
comment at line 515 states the stakes: *"the menu editor and 'Blank Entry' let anyone append
`init=/bin/bash`"*. On any box where `/usr/lib/initcpio/hooks/omarchy-kids-unlock` is absent —
a machine that never ran `mkinitcpio -P`, an install where the hook was removed, anything
non-Limine-plus-hook — `editor_enabled: no` is never enforced and a kid edits the boot entry to
a root shell. `test/shell.d/assert-test.sh:349` `touch`es the hook file before the limine tests,
so the suite can never see this.

**Do:** dedent line 682. Add a test that runs `assert` with no hook file and expects
`limine-editor` to still be reported.

### 4. Dry-run — the default — prints the kid's password and the parent's LUKS passphrase

`bin/omarchy-kids-provision:92-100`, `bin/omarchy-kids-provision:466`

`run()` previews with `printf ' %q' "$@"`. Line 466 is
`run add_luks_slot "$account" "$device" "$kid_password" "$parent_password"`. With `DRY_RUN=1`
— the documented default for the command — both secrets are shell-quoted onto stdout, into SSH
scrollback and into whatever the wizard's caller is logging. AGENTS.md:58: *"passwords only ever
on stdin, never argv, never logged."*

**Do:** `add_luks_slot` takes its two secrets on fds, not argv, and prints its own one-line
preview. No secret ever reaches `run`.

### 5. The shipped app entry point runs the whole product in preview mode

`desktop/omarchy-kids.desktop:5`, `bin/omarchy-kids:93`, `bin/omarchy-kids-panel:104`,
`bin/omarchy-kids-wizard:97`

`Exec=omarchy-kids` → `exec "$PANEL_BIN" "${args[@]}"` with no `--apply`; both the panel and
the wizard default `DRY_RUN=1`. A parent opens Kids Mode from the drawer, walks the wizard,
presses **Apply**, watches `[dry-run] sudo ...` scroll past, and has no kid account. There is no
argument the drawer can pass to fix it.

AGENTS.md rule 8 is a rule for *developer machines*. It has been applied to the user-facing
product, where it makes the two interactive commands no-ops by default.

**Do:** the panel and the wizard are interactive; a human confirming a screen *is* the
confirmation. Default them to real, keep `--dry-run` for review, and leave `DRY_RUN=1` where it
belongs: `provision`, `assert`, `web`, `apps`, `remove`.

### 6. `boot-login` still uses the `kid-` username heuristic that was already found broken

`bin/omarchy-kids-boot-login:37-42`

```text
session_for() { case "$1" in kid-*) echo "omarchy-kids.desktop" ;; *) echo "omarchy.desktop" ;; esac; }
```text

`lib/posture.sh:482-486` documents this exact heuristic failing live: *"a VM whose owner was
named `kid-vm` … the owner's own tile was misclassified as a kid"*. The portal was fixed to read
the profile registry; the autologin path was not. An owner account whose name starts with `kid-`
unlocks with their own passphrase and is autologged into a **kid session** on a root-owned
kiosk config.

**Do:** `[[ -f "$ETC/kids/$1.conf" ]]` decides, the same source of truth
`omarchy-kids-assert`, `-ask` and `-time-ledger` all already use.

### 7. Seven copies of `run()`, four of `group_for_band`, three socket clients

See §3 for the full table.

`lib/` already exists and is already sourced by `provision`, `assert`, `remove` and
`session-start`. Every duplication carries a paragraph explaining that `omarchy-kids-provision`
"is a script with its own `main "$@"`, not a library" — which is an argument for moving the four
lines into `lib/`, not for copying them. They have already drifted: `provision:122` rejects
`13plus` and calls `die`; `assert:144` accepts it and returns 1.

**Do:** `lib/kids.sh` with `run`, `group_for_band`, `home_dir_for`, `parent_home_dir`,
`read_kv`/`conf_get`, `detect_luks_device`, `file_mode`, `authd_request`, and the
`BIN="${OVERRIDE:-$DIR/bin/x}"` resolver. Delete the apology comments with the copies.

### 8. A 26% comment ratio, and headers that contradict the code below them

`share/exit-modal/shell.qml:1-52`, `bin/omarchy-kids-exit:1-45`, `bin/omarchy-kids-bar:2-102`

`share/exit-modal/shell.qml` opens with `====== UNTESTED ======` and *"this has never run
against a real Quickshell or Hyprland"*; line 65, inside the same file, says *"Verified live
2026-09-02"*, and line 161 answers the question line 157 says is unanswered. `bin/omarchy-kids-exit:5`
says the same file *"has never run against a real Hyprland/Quickshell session"* while
`README.md:37` lists the exit modal under **What works today**. A reader cannot tell which
sentence is current.

**Do:** headers say what the file is, in two lines. Status belongs in `docs/` and the issue
tracker, where it can be updated in one place. See §4 for the ten worst blocks.

### 9. `a && b || c` on the one path that ends a session

`bin/omarchy-kids-exit:238`

`--finish) [[ -n "$kid" ]] && cmd_finish_kid "$kid" || cmd_finish ;;` — if `cmd_finish_kid` ever
returns non-zero instead of exec'ing (a `loginctl` that isn't installed, a future early return),
the shell falls through to `cmd_finish`, which under `--finish --kid` is running **as root** and
terminates root's own session. Use an `if`.

Related, same file, `:102-105`: `modal_already_open` matches `pgrep -f "quickshell -p $MODAL_QML"`.
A kid runs any process whose argv contains that string and the exit modal can never be opened
again — Super×3 and Super+Shift+K both silently return 0. Track the modal with a pidfile under
the root-owned `/run/omarchy-kids`, not a substring of `/proc/*/cmdline`.

### 10. LUKS slot detection breaks when the kid's password equals the parent's

`bin/omarchy-kids-provision:538-557`

`add_luks_slot` finds the new slot by running `cryptsetup open --test-passphrase` with the kid's
password and parsing *"Key slot N unlocked"*. `--test-passphrase` reports the **first** slot that
matches. If the kid types the parent's passphrase (a six-year-old copying what they watched), it
reports slot 0, and `luks-slots` gets a second `0=` line under the parent's. `boot-login`'s
`lookup_slot` returns on the first `0=` match — behaviour then depends on line order in a file
`posture_write_luks_slots` regenerates. Line 544's trailing `|| true` also swallows a failed
test outright.

**Do:** snapshot `cryptsetup luksDump`'s occupied slots before `luksAddKey` and diff after.
Reject a kid password that already unlocks the device.

---

## 2. Security findings

**S1 — Kid-authored "approved" records applied by root (critical).**
`bin/omarchy-kids-ask:229` / `:354-360`, `lib/ask.py:100-126`. *Scenario:* band 13+ kid opens
their terminal, `omarchy-kids-ask submit time 480 --state approved --by keyboard`, waits ≤60s
for `omarchy-kids-ask-collect.timer`. Root grants eight hours. Repeatable, silent, and it also
works for `app`, `plugin` and `site`.

**S2 — `apply_record` trusts the `kid` field, not the outbox owner (critical).**
`bin/omarchy-kids-ask:252-257`, `lib/ask.py:95` (`kid` is never validated). *Scenario:* kid A
writes `{"kid":"kid-b","kind":"time","minutes":600,"state":"approved"}` into their own outbox
and grants kid B the time — or writes `"kid":"<parent>"` and has root run
`omarchy-kids-conf set <parent> apps.extra …`, editing the parent's profile from a child account
(I-1: *"the parent's account is never restricted"*).

**S3 — Root path traversal via the same field (critical).**
`bin/omarchy-kids-ask:317-325`: `allow_file="$ETC/kids/$kid/allow.txt"`, then
`run append_allow_line "$allow_file" "$host"` which does `install -d -m 0755 "$(dirname …)"` and
appends. *Scenario:* a record with `"kid": "../../../../etc/sudoers.d"` and
`"what": "kid-ada ALL=(ALL) NOPASSWD: ALL"` makes root create `/etc/sudoers.d/allow.txt` with a
kid-chosen line in it. `install -d` creates whatever directory is missing on the way.

**S4 — PAM/PATH/env redirection of the password verifier (critical).**
`bin/omarchy-kids-parent-auth:11`, `lib/posture.sh:221`. *Scenario:* kid puts
`export OMARCHY_KIDS_AUTH_SOCK=$HOME/fake.sock` in `~/.bashrc` (or a shell script named
`omarchy-kids-parent-auth` in `~/.local/bin`), runs a two-line listener that writes `ok\n`, then
hits the lock screen or the ask modal. `[success=done]` at `posture.sh:221` ends the PAM stack
successfully before pam_unix ever sees the typed password.

**S5 — `editor_enabled: no` unenforced without the boot hook (high).** `bin/omarchy-kids-assert:680-683`.
*Scenario:* the Limine editor is reachable, kid appends `init=/bin/bash` to the kernel command
line, gets a root shell on the unlocked filesystem. Also unreachable through
`limine_editor_fix`'s own writer: `assert:527` and `:600` do `cat "$tmp" > "$f"` on
`/boot/limine.conf` and `/etc/default/limine` — a non-atomic truncate-then-write on the
bootloader config, where every other writer in the repo uses temp-file-then-rename. Power loss
mid-`cat` leaves an unbootable machine.

**S6 — Both secrets printed by the default dry run (high).** `bin/omarchy-kids-provision:466`.
*Scenario:* the documented preview run
(`printf '%s\n%s\n' "$kidpw" "$parentpw" | omarchy-kids-provision add Ada --band 6-8
--password-stdin --parent-password-stdin`) prints `[dry-run] add_luks_slot kid-ada /dev/sda2
<kid password> <parent LUKS passphrase>` — over SSH, into `docs/loop-report.md`-style captures,
into any CI log.

**S7 — Anyone local can lock the parent out of the exit modal (medium).**
`bin/omarchy-kids-authd:115-135`, `systemd/omarchy-kids-authd.socket:7` (`SocketMode=0666`).
The rate limiter is global to the daemon, not per-peer, and `wrong_count` never decays.
*Scenario:* kid loops ten wrong guesses at the world-writable socket every four minutes. The
parent's correct password now returns `no` from `verify()` for as long as the kid keeps
looping — the parent cannot end the session from the modal. The daemon is also a single
`accept()` loop with a 5s per-client timeout (`:243-260`), so a kid holding connections open
serializes every other verification.

**S8 — Wi-Fi password echoed back to the caller (medium).** `bin/omarchy-kids-wifid:127`:
`raise Failed(f"nmcli {' '.join(args)}: {exc}")` — `args` includes `password <secret>` for the
JOIN path, and the `Failed` text is sent to the client at `:249`. A parent who types the network
password into the kid's picker gets it back over the socket and into whatever the client logs.

**S9 — Unquoted heredoc generating a polkit rule (medium).** `lib/posture.sh:52-67` uses
`cat <<RULES` (unquoted) and interpolates `return ["unix-user:$parent"];` at line 63.
AGENTS.md:58 requires *"quoted heredocs for anything root writes"*, and this is the
highest-value file on the box: a `parent=` value in `machine.conf` containing `"` or `]` yields
either a broken admin rule (polkit then falls back to asking for **root**'s password, not the
parent's) or injected JavaScript. `posture_portal_conf_text:533-546` has the same shape and its
own comment concedes nobody sanitizes names for `:` or `,`.

**S10 — Kid display name is never validated (medium).** `bin/omarchy-kids-provision:350`
accepts any `$display`, which then reaches `usermod -c "$display"` (`:416`), a tab-delimited
portal record (`:505`) and a `:`/`,`-delimited `kids=` field (`posture.sh:538`). A name
containing a tab, colon or comma corrupts `theme.conf.user` and can shift another kid's avatar
or account onto the wrong tile at the greeter.

**S11 — Fail-open self-checks (low, but they are the safety net).** `assert:221`
(`gecos_ok` returns *ok* when `getent` is missing), `:360` (`parent_unlock_ok` returns *ok* when
the PAM stack file is absent), `:413` (`parent_group_ok` returns *ok* when `parent=` is unset),
`:431`/`:491`/`:519`/`:561` (same pattern). AGENTS.md rule 4 is *"fail closed at kid login"*;
a check that cannot look reports green. At minimum these should report `warn`, and
`omarchy-kids-check` should exit non-zero on a machine it could not verify.

**S12 — Bare-name exec of privileged-ish commands from the kid's session (low).**
`bin/omarchy-kids-super-tap:24,88` (`EXIT_BIN` defaults to the bare name, `exec`'d),
`share/exit-modal/shell.qml:187-189` (`execDetached(["omarchy-kids-exit", …])`),
`session-start:388` (`omarchy-launch-shell`). All PATH-resolved inside a session whose PATH the
kid owns.

---

## 3. Duplicated helpers, and the single home each should have

| Helper | Copies | Single home |
| --- | --- | --- |
| `run()` (identical 8 lines, `%q` dry-run preview) | `provision:92`, `apps:145`, `ask:143`, `bar:149`, `plugins:146`, `wifi:119`, `web:138` — plus `panel:161` `run_priv` and `panel:182` `read_priv`, same job, different names | `lib/run.sh` — one `run`, one `run_priv` |
| `group_for_band` | `provision:122`, `assert:144`, `web:161`, used again in `check:669` | `lib/conf.sh` (already sourced by all four); the copies have already drifted on `13plus` and on `die` vs `return 1` |
| `home_dir_for` | `provision:140`, `assert:156`, `remove:126` | `lib/posture.sh` (owns every other `/home` path) |
| `parent_home_dir` | `provision:161`, `remove:301` | `lib/posture.sh` |
| key=value reader | `provision:146` `read_kv`, `lib/conf.sh:16` `conf_get`, `boot-login:49` `lookup_slot` — `provision`'s own comment names both others | `lib/conf.sh:conf_get`; `lookup_slot` becomes a caller |
| `detect_luks_device` | `provision:216`, `check:224` (`detect_luks_device_check`) | `lib/posture.sh` |
| GNU/BSD `stat` wrapper | `assert:161` `file_mode` (`%a`), `check:209` `stat_group` (`%G`) — same dance, two names | one `lib` `file_stat FMT FILE` |
| authd socket client (socat-else-inline-python3, ~20 lines) | `parent-auth:18-39`, `wizard:348-375`, `wifi:172-201` | `lib/sock.sh:kids_request SOCKET PAYLOAD`; the three copies already differ in `elif`/`else` and timeout handling |
| `BIN="${OVERRIDE:-$DIR/bin/x}"; [[ -x ]] \|\| BIN=x` | every command; six consecutive lines in `session-start:67-72`, four in `omarchy-kids:23-26` | `lib/paths.sh:kids_bin NAME` |
| `modal_already_open` (pgrep on the QML path) | `exit:102`, `ask:164` | one helper — and replace pgrep with a pidfile (see §1.9) |
| `portal_conf_entries` | `provision:240`, `assert:308` (the second silently drops the `EXCLUDE` argument) | `lib/posture.sh` |
| `list_kids` / `known_kids` | `provision:651` (inline), `assert:506`, `ask:239`, `time-ledger:84`, `omarchy-kids:57` | `lib/conf.sh:kids_list` |

Every one of these copies is accompanied by a comment justifying it. That is the tell: when the
codebase has to argue with itself twelve times, the argument is wrong.

---

## 4. Comment bloat — the ten worst blocks

Measured as runs of ≥10 consecutive comment lines. Omarchy's own worst case in the four files
read for calibration is 9 lines.

| # | Location | Lines | Replace with |
| --- | --- | --- | --- |
| 1 | `share/sddm-theme/Main.qml:1-144` | 144 | `// The login portal (R-LOGIN). Tiles come from theme.conf.user; see docs/portal.md.` |
| 2 | `bin/omarchy-kids-bar:2-102` | 101 | `# The parent's bar widget: per-kid minutes and requests from /run/omarchy-kids/status.json (R-BAR). See docs/bar.md.` |
| 3 | `bin/omarchy-kids-web:2-81` | 80 | `# Installs the band's Chromium policy and launches Chromium without Omarchy's extension flags (R-WEB). See docs/web.md.` |
| 4 | `bin/omarchy-kids-panel:2-80` | 79 | `# The parent panel: per-kid time, web, apps, level, password, remove (R-WIZ-7/8). See docs/panel.md.` |
| 5 | `bin/omarchy-kids-ask:2-79` | 78 | `# Ask a grown-up: the kid asks, root collects and applies (R-ASK). See docs/ask.md.` |
| 6 | `bin/omarchy-kids-session-start:2-62` | 61 | `# Per-session setup: writes the launcher tile JSON, then starts the launcher (L1) or Omarchy's shell (L2/3).` |
| 7 | `share/exit-modal/shell.qml:1-52` | 52 | `// Exit modal: parent password, then Finish (R-EXIT).` — and delete the UNTESTED banner, which lines 65 and 161 contradict |
| 8 | `lib/posture.sh:164-210` | 47 | `# The parent-unlock pam_exec line: after a leading pam_faillock preauth, else before the first auth line. Rationale in docs/authd.md.` |
| 9 | `lib/posture.sh:480-518` | 39 | `# theme.conf.user — SDDM's ThemeConfig loads it beside theme.conf; rebuilt in full on every add/remove.` |
| 10 | `bin/omarchy-kids-assert:691-710` | 20 (for a 3-line guard) | `# Sourced by omarchy-kids-check for the *_ok functions; only run main when executed directly.` |

Honourable mentions: `lib/posture.sh:380-413` (34 lines above a 14-line function),
`bin/omarchy-kids-remove:312-326` (15 lines above a 2-line `home_present`),
`bin/omarchy-kids-session-start:324-337` (14 lines for one tile),
`bin/omarchy-kids-provision:296-314` (19 lines above `install_kids_chromium_flags`).

Three recurring habits drive the count and should stop outright: (a) restating a function's
argument list and defaults immediately above a signature that shows them; (b) narrating the
history of rejected designs in the source — `posture.sh:488-495`, `assert:296-307` and
`exit:19-24` each re-litigate an approach that is no longer in the tree; (c) apologising for a
duplication instead of removing it (§3).

---

## 5. Naming and voice

**Flags.** `provision`/`apps`/`web`/`ask`/`plugins` use `--apply` (default preview);
`assert` uses `--dry-run` (default real); `panel`/`wizard` accept both. Three vocabularies for
one idea. Pick `--apply` for scripts, plain-real for the two interactive commands (§1.5).

**Commands.** `omarchy-kids-ask` is the request queue; `omarchy-kids-ask-grownup` is an unrelated
fail-closed splash screen. Prefix collision on two things that share nothing. Rename the second
`omarchy-kids-blocked`.

**Words for the same person.** `grown-up` (`ask/shell.qml:237,321`, `timesup.qml:200`),
`grownup` (the command name), `parent` (`L1.lua:105` `"Kids Mode: parent"`, shown to the kid in
Omarchy's own keybinding menu), `your grown-up` (`ask/shell.qml:152`). Pick one for kids
("grown-up") and one for docs/CLI ("parent"), and never show the CLI word to a kid.

**Function naming.** `*_ok`/`*_fix` (assert) vs `add_result … pass|fail|warn|skip` (check) vs
`report ok|fixed|would-fix|FAIL` (assert's own output) — three status vocabularies inside two
files that source each other. `check_*` in `check` vs `*_check` in the same file
(`account_sudoers_check` at `:236`, `pam_parent_unlock_check` at `:640`).

**Kid voice, mixed registers.** `share/exit-modal/shell.qml:214`:
*"Pause isn't available yet -- press Tab, then Enter, for Finish."* — keyboard mechanics in a
modal whose other strings are `"That wasn't it."`. Same file, `:389`: *"Closes Ada's apps. You
switch to your desktop."* — "you" is the parent, in a card headed with the kid's name and avatar.
Decide who each screen talks to.

**Typography.** `…` in `plugins/shell.qml:186` and `wifi/shell.qml:275`; `...` in
`session-start:258` (`"installing..."`). ASCII `--` used as an em-dash in kid-facing text
(`plugins/shell.qml:203` *"Nothing here yet -- check back later!"*, `exit-modal:214`).

**Adult voice.** `README.md:50-53` is two sentences interleaved and shipped that way:
*"the one-command build, and the"* / (blank) / *"The night the code landed is summarised…"* /
*"honest list of what isn't ready yet."* Also `README.md:63` advertises **Pause** in the feature
table while `exit:37-45` says it is not implemented and refuses — the honest-UI rule (I-6)
applied to the README.

---

## 6. Dead, unreachable, and half-built

- **`--pause` is unreachable and, when reached, does nothing.** `bin/omarchy-kids-exit:208-211`
  prints and exits 2. `share/exit-modal/shell.qml:120` gates the button on
  `OMARCHY_KIDS_PAUSE_AVAILABLE === "1"`, which `exit:45` states is never set — but it is read
  from the environment, so a kid can set it, enable the button, and get a no-op. Delete the
  branch and the button; the README row goes with them.
- **`share/tui/screens/` is empty.** AGENTS.md:39 promises *"Screens as data, one renderer
  (R-WIZ-9)"*; `lib/tui.sh` contains no TOML reader (`grep -n toml lib/tui.sh` → nothing) and
  `bin/omarchy-kids-wizard` hardcodes every screen. Either build the reader or delete the
  directory and the AGENTS.md row.
- **`polkit/` and `sudoers/` are empty `.gitkeep` directories** that AGENTS.md:46 describes as
  holding drop-in templates. The real templates are heredocs inside `lib/posture.sh`.
- **`bin/omarchy-kids-tui-demo`** is a demo with no non-test caller, and `PKGBUILD:66`
  (`install -m755 bin/omarchy-kids bin/omarchy-kids-*`) ships it to `/usr/bin` on every user's
  machine. The glob is the problem: it makes anything dropped in `bin/` a supported command.
- **`bin/omarchy-kids-provision:228`** — `# --- account naming (Appendix B.1) ---` is a section
  banner with no section under it.
- **`bin/omarchy-kids-wifid:254`** — `_ = account`, a no-op assignment kept to silence a linter
  for a variable the function does not use.
- **`bin/omarchy-kids-session-start`** calls `mkdir -p "$RUN"` twice (`:78` and `:233`).
- **`bin/omarchy-kids-assert:441-446`** — `hyprland_fix` prefers
  `omarchy-kids-session --install-configs`, and its own comment says the flag "doesn't yet
  exist — verified against this checkout". Speculative branch for an interface nobody has
  written.
- **`bin/omarchy-kids-provision:279-293`** — `mark_migrations_done` writes a
  `migrations.log` whose format the comment admits is *"a documented guess"* with a
  `TODO(#10)`. It either satisfies Omarchy's migration check or it does not; shipping a guess
  that writes into a real home is worse than not writing at all.
- **`bin/omarchy-kids-exit:37-45`, `share/*/shell.qml` UNTESTED banners,
  `share/menu/omarchy-kids-trimmed.jsonc:4` ("UNVERIFIED SCHEMA")** — nine files ship against
  interfaces nobody has checked. `share/menu/omarchy-kids-trimmed.jsonc` is data for a menu
  extension format that was guessed; nothing reads it.
- **`omarchy-kids.install`** creates groups and reloads systemd but never enables a unit, while
  `bin/omarchy-kids-assert:625` fixes "units not enabled" from
  `omarchy-kids-assert.service` — itself one of the units that is not enabled. On a fresh
  `pacman -S omarchy-kids` nothing runs until the wizard's Apply.
- **`PKGBUILD:43`** has no dependency on `omarchy`, `sddm` or `hyprland`, though the package
  requires `/usr/share/omarchy/*.lua` (`L1.lua:50`), `omarchy-launch-shell`
  (`session-start:388`) and an SDDM theme directory. It installs cleanly on a machine where
  every command fails.

### On the tests

29 files, all green, and the tests are thorough about argv shapes. Two structural problems:

- **Skips read as passes.** `test/shell.d/authd-test.sh:10-11` skips the entire suite when
  libcrypt is unloadable, exits 0, and `test/all:10` prints `ok test/shell.d/authd-test.sh`. On
  the macOS dev box named in AGENTS.md the run reports 29/29 while four things silently did not
  happen: the password verifier's whole test file, `wifi-test.sh` section B (the SO_PEERCRED
  authorization boundary — the only test of who is allowed to drive the Wi-Fi daemon), the
  `luac` syntax check of `share/hyprland/*.lua`, and the POSIX-sh check of
  `omarchy-kids.install`. `test/all` must count skips and print them in the summary; a suite
  where the security tests are the ones that skip is worse than no suite.
- **Implementation, not behaviour.** `test/shell.d/portal-test.sh` has sixteen `grep -q` calls
  against source text, including `grep -qF 'charAt(0).toUpperCase()' "$MAIN_QML"` (`:139`) and
  `grep -qF "new XMLHttpRequest"` asserting an *absence* (`:134`). These pin the current
  implementation and will fail on any refactor that preserves behaviour, while proving nothing
  about what the greeter renders. Same pattern in `ask-test.sh` (11) and `exit-test.sh` (4).
- **Nothing tests the security boundary.** No test asserts that a kid-written outbox record is
  *not* applied (§S1), that `parent-auth` ignores a hostile `OMARCHY_KIDS_AUTH_SOCK` (§S4), or
  that `limine-editor` is asserted without the boot hook (§S5). Each is a ten-line test.
