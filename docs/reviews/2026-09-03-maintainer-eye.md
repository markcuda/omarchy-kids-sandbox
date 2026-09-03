# Review 3 — omarchy-kids-sandbox @ f2b9035, the maintainer's eye

Third pass, after #56's style follow-ups. Rounds one and two (`docs/reviews/2026-09-03-antagonistic*.md`)
hunted for what a kid can do; this one reads the repo the way the Omarchy maintainers would when
a contributor asks them to bless it: taste, shape, conventions. Calibrated against `docs/style.md`'s
observations of omacom/omarchy v4.0.2 (tiny scripts, `#!/bin/bash`, gum for prompts, one-line
whys, 2-space indent, no function soup) and `AGENTS.md`'s Conventions.

Read: every `bin/omarchy-kids-*`, `lib/kids.sh`, `tui.sh`, `theme.sh`, `time.sh`, `conf.sh`,
`sock.sh`, `units.sh`, the wizard and panel libs, `share/qml/KidsTheme.qml`, the exit modal and
Time's Up QML, `PKGBUILD`, `.SRCINFO`, the install scriptlet, every unit, the hook, both desktop
entries, `README.md`, `docs/install.md`, `docs/parent-card.md`, `CHANGELOG.md`. The tests' own
host coupling (61 checks failing on Arch) is being fixed on another branch and is not repeated here.

Severity here is taste, not risk: **high** = a parent or kid meets it; **medium** = a maintainer
would send it back; **low** = a nit they'd fix in the merge commit.

**Applied on branch `review3`** (five commits, `test/all` green, `shellcheck -S warning -x` clean):
1.2, 3.3, 4.1, 2.4, and the 1.13/5.1/4.7 trio. Everything else is a finding only.

**Resolution, end of the same day.** Every finding above is applied on `main` (branches
`review3`, `lows`, `panel-facts`, `fmt2`, and direct commits), each verified by the suite on the
Mac and on the VM, the visible ones by screenshot. One deliberate exception: 2.3's two `eval`s
stay, with a one-line why, because the dev Mac's `/bin/bash` is 3.2 and the suite runs there too.

---

## 1. `bin/omarchy-kids-*`

### 1.1 Two indent styles (medium)

47 files use 4 spaces, 7 use 2 (`blocked`, `exit`, `launcher-ctl`, `parent-auth`, `session`,
`session-start`, `super-tap`). Omarchy is 2-space everywhere (`docs/style.md` §9, §10, and every
`bin/omarchy-*` cited in §1–§3). A maintainer notices this before reading a line of logic.
**Fix:** one mechanical commit after the in-flight branches land — `shfmt -i 2 -ci -bn -w
bin/omarchy-kids-* lib/*.sh` — and name `shfmt` next to `shellcheck` in `AGENTS.md`'s "How to
work". Not applied here: it would collide with every open branch.

### 1.2 Time's Up's "Ask a grown-up" showed the wrong screen (high) — applied

`share/time/timesup.qml:78` ran `omarchy-kids-time ask-grownup`, which ran `omarchy-kids-blocked
time 15` (`bin/omarchy-kids-time:94-101`): the kid pressed "Ask a grown-up for more time" and got
"Something isn't set up right yet, so this desktop can't start safely. Check that failed: time" for
fifteen seconds. `docs/time.md:145` documented it as a placeholder from before `omarchy-kids-ask`
existed; `docs/parent-card.md:27` already promised the real queue. **Fix:** the button runs
`omarchy-kids-ask time 15`; the subcommand, its env var, its allowlist line, its tests and its doc
section are gone. The modal opening *over* the Time's Up overlay (two keyboard-exclusive layer
surfaces) has not been watched live — `docs/time.md` says so.

### 1.3 `apply_time` looks up its sibling on `PATH` (medium)

`bin/omarchy-kids-ask:234-244`: "omarchy-kids-time is being built in a parallel issue; call it by
name and degrade gracefully". It shipped weeks ago in the same package, and every other sibling is
resolved with `kids_bin`. **Fix:** `run "$(kids_bin time "$DIR")" grant "$kid" "$minutes"`, delete
the degrade branch and the comment. Coordinate with the unit-suite-on-Arch branch (its "missing
command" test is one of the 61).

### 1.4 A hand-rolled terminal fallback that can't run on Omarchy (medium)

`bin/omarchy-kids-bar:181-185` falls back to `alacritty -e` when
`omarchy-launch-floating-terminal-with-presentation` is missing; `bin/omarchy-kids-session-start:202`
walks `kitty alacritty foot wezterm xterm` for the data tile. A stock 4.0.2 box has the Omarchy
helper and `foot`; `alacritty` is not there. **Fix:** trust the helper the way the code already
trusts `/usr/bin/omarchy-launch-shell` (no fallback; the test stubs it), and give the data tile the
same helper instead of a list.

### 1.5 The `-h|--help|"")` puzzle (low)

`apps`, `ask`, `bar`, `conf`, `launcher-ctl`, `plugins`, `provision`, `web`, `wifi` all carry the
same one-line case arm: usage, then exit 2 if the command was empty, else exit 0. It's correct and
it reads like a riddle. `time`, `data`, `time-ledger` already do it plainly. **Fix:** a usage-and-
exit-2 guard on an empty `$#` above the `case`, and a plain `-h|--help` arm inside it.

### 1.6 `CONF` vs `CONF_BIN` (low)

`bin/omarchy-kids-provision:29`, `bin/omarchy-kids-web:12` call it `CONF`; twenty other files
call the same sibling `CONF_BIN`. **Fix:** `CONF_BIN`.

### 1.7 `PY="$KIDS_PY"` (low)

`panel:19`, `session-start:15`, `conf:25`, `apps:13`, `ask:12`, `wizard:36` alias the constant to
a second name. **Fix:** use `"$KIDS_PY"` and delete the alias.

### 1.8 The `TIME_CONF_BIN` handshake (low)

`time:15`, `time-ledger:15`, `data:15` each `source lib/time.sh` and then set `TIME_CONF_BIN`
— but `lib/time.sh:41-49` already resolves the sibling when the variable is empty. **Fix:** delete
the variable and the three assignments.

### 1.9 Constants left over from the env-override era (low)

`bin/omarchy-kids-check:20-21` (`RUNUSER_BIN=runuser`, `LOGINCTL_BIN=loginctl`),
`bin/omarchy-kids-plugins:15-17`. Everything else calls `runuser` by name. **Fix:** same here.

### 1.10 bash-3.2 apologies in a bash-5 product (low)

`session:198-201` ("the macOS box this was built and tested on"), `session-start:75`,
`conf:43-44`, `lib/theme.sh:24`, `lib/tui.sh:97-99,108-109`. `AGENTS.md` says bash 5; the package
runs on Arch; the suite now runs on the VM. **Fix:** keep the `case` statements (they read fine),
delete the apologies, and let `_tui_array_copy`/`_tui_gum_env_default` become `local -n` and
`${!name}` once `test/all` on macOS is no longer a goal.

### 1.11 A second `is_root` (low)

`bin/omarchy-kids-parent-auth:21` redefines the "one uid check" `lib/kids.sh:10` owns. It sources
only `sock.sh` on purpose (a PAM helper wants a small surface). **Fix:** say that in the one line,
or source `kids.sh`.

### 1.12 `omarchy-kids-time-ledger` writes `status.json` in a function called by `tick` only (low)

`bin/omarchy-kids-time-ledger:73-98` computes `active_kid_sessions` once per kid inside a loop
(`:86-88`), so a house with four kids runs `loginctl` four times more than needed every minute.
**Fix:** read `active_kid_sessions` once into a variable before the loop.

### 1.13 Help text pointing at comments that moved (low) — applied

`super-tap:21-25` ("see this file's header for why that bind isn't wired into
share/hyprland/*.lua yet" — it is wired, in all three levels), `session:48`, `web:55-56`,
`blocked:14`. #56 moved the headers to `docs/`; the `--help` texts still pointed at them.
**Fix:** they point at the docs, and `super-tap` says what the levels do.

---

## 2. `lib/*.sh`

### 2.1 Two account-home resolvers (medium)

`lib/kids.sh:57-67` (`parent_home_dir`: getent, else `home_dir_for`) and `lib/theme.sh:106-113`
(`theme_account_home`: getent, else `/home/<account>` under `HOME_ROOT`) are the same idea.
**Fix:** one `account_home ACCOUNT` in `kids.sh`; `parent_home_dir` calls it.

### 2.2 `lib/units.sh` is three arrays in their own file (low)

Twelve lines, 66% comment by #56's own count. **Fix:** fold into `lib/kids.sh` under a
"systemd units" heading, or leave — a maintainer would accept either, but would ask.

### 2.3 `lib/tui.sh:97-115`: two `eval`s for bash 3.2 (low)

See 1.10. On bash 5 they are `local -n` and `${!name}`; `eval` in a TUI library is the first
thing a reviewer greps for.

### 2.4 Five copies of `is_in` (low) — applied

`conf:90`, `apps:75`, `ask:92`, `plugins:58` (unused), `check:82` (`array_contains`) were the
same six lines. **Fix:** one `is_in` in `lib/kids.sh`; `is_valid_band` is a one-liner over it.

### 2.5 `is_known_kid` is the odd one out (low)

`lib/kids.sh:164`: the only helper with no comment, argument order `(ACCOUNT, DIR)` while
`kids_list`/`portal_conf_entries` take `DIR` first, and both callers (`ask:42`,
`time-ledger:26`) wrap it in `is_known_kid_here` to bind `$KIDS_DIR`. **Fix:** `is_known_kid DIR
ACCOUNT`, one comment line, drop the two wrappers.

### 2.6 Table output parsed by column offset (medium)

`lib/panel-kid.sh:163` (`cut -c18-41` over `omarchy-kids-apps list`'s human table) and `:216-217`
(`cut -c26-49`, `cut -c69-` over `plugins shelf`). The first 25-character label shifts every
column. **Fix:** `apps list --json` (or TSV, like `provision list`) and `shelf --json` (exists
already) — parse those.

### 2.7 A library that sets the caller's environment on `source` (low)

`lib/theme.sh:11-15` exports `OMARCHY_PATH` and `LANG` the moment it is sourced. It was a live fix
(#48: `omarchy-theme-color` under SSH). **Fix:** keep the defaults, but inside `theme_dir`/
`_theme_kids_tool_ready`, so sourcing a library never changes the parent's environment.

---

## 3. The wizard, the panel, the QML

### 3.1 The panel's status lines are cleared before the parent reads them (high)

Card mode clears the terminal on every screen (`lib/tui.sh:125-128,195-197`). Every panel
screen prints its facts with `echo` *before* the chooser: `lib/panel-kid.sh:428-431` (the kid's
band, minutes, open requests), `:16-17` (screen time status), `:82-89` (the allow list),
`:251-264` (the whole Data screen), `lib/panel-home.sh:12-15`. In a terminal, each of those is
wiped by `clear` before the card draws; the parent sees a menu and no facts. File mode (plain, no
clear) is what every panel test and the live run over SSH used, so this has not been seen. **Fix:**
give `tui_screen_choose` the optional `BODY_ARRAYNAME` `tui_screen_confirm` already has
(`tui_header` supports it), and pass the facts as body lines. Verify with a screenshot on the VM.

### 3.2 The wizard tells the parent the account name where they can't see it (medium)

`lib/wizard-screens.sh:52-58`: "That'll be kid-ada on this computer." is echoed after the name
screen and cleared by the face screen. The summary (`:300`) shows it anyway. **Fix:** delete the
echo (six lines).

### 3.3 A wrong parent password gave no feedback in card mode (high) — applied

`lib/wizard-screens.sh:34-41` echoed "That wasn't it. Try again." and looped straight into a
screen that clears; same for the kid-password mismatch (`:279-281`). **Fix:** `lib/tui.sh` takes a
caller's verdict via `TUI_PRESET_ERROR` and renders it exactly like a validator's message, on the
red card. Plain mode output is unchanged, so the three-wrong-tries test still counts three.

### 3.4 Omy's welcome is five sentences (low)

`lib/wizard-screens.sh:12`. The installer's voice is one or two (`docs/style.md` §5). **Fix:**
"Hi, I'm Omy. Each kid gets their own desktop. You stay in charge with your own password, and
everything can be undone."

### 3.5 Twenty lines of QML that do nothing (low)

`share/exit-modal/shell.qml:40-63`: a `FileView` over the launcher JSON plus `fallbackField`,
documented in place as "UNVERIFIED and likely a no-op in practice today" (the JSON carries no
`name`/`avatar`). `:16` still says "see the UNTESTED header above"; #56 rewrote that header.
`:115-119` keeps the "closeStdin() is a guess" note next to the line that says it's verified.
**Fix:** delete the fallback and the two stale comments; `displayName` is `kidName || kidAccount`.

### 3.6 `share/qml/KidsTheme.qml` is 60% comment (low)

170 lines, ~100 of them prose (`:11-16`, `:25-105`). #56 trimmed every QML *header* to three
lines and left this body alone. **Fix:** the derivation rationale to `docs/theming.md`, one line
per property.

### 3.7 The Time's Up avatar has no owl (low)

`docs/parent-card.md:25` promises "an owl (or their own avatar)"; `share/time/timesup.qml:134-141`
hides the `Image` when the avatar is missing. **Fix:** `source: root.kidAvatar || "…/avatars/owl.svg"`.

### 3.8 "Esc/q quit" (low, verify)

`lib/panel-home.sh:47`'s footer advertises `q`. `gum choose` aborts on Esc and Ctrl+C; if `q`
isn't bound in the shipped gum, the footer is a label claim. Verify on the VM; drop `q` if so.

### 3.9 Keyboard completeness — no finding

Every gum screen: Enter/Esc/Ctrl+C, number keys, a footer that says so. Every QML surface:
Tab/Backtab, arrows, Enter, Esc where dismissal is allowed and deliberately not on Time's Up.

---

## 4. Packaging

### 4.1 `.SRCINFO` drifted from `PKGBUILD`; units documented files that don't exist (medium) — applied

`.SRCINFO` lacked `hyprland` and `sddm` (`PKGBUILD:50`). `omarchy-kids-apps-install.service`,
`-ask-collect.service/.timer`, `-assert.service` pointed `Documentation=` at
`/usr/share/doc/omarchy-kids/*.md`, which the package never installs; `-boot-login*.service`
at `man:omarchy-kids-boot-login(1)`, which doesn't exist. An AUR reviewer runs `makepkg
--printsrcinfo | diff - .SRCINFO` first. **Fix:** regenerated by hand (no makepkg here); every
unit names its `docs/*.md` on GitHub like the other six already did.

### 4.2 Thirty-six lines of depends rationale inside the PKGBUILD (medium)

`PKGBUILD:22-57`. Reviewers read a PKGBUILD as code; the "UNVERIFIED whether sddm pulls in
qt6-svg" paragraph belongs in `docs/packaging.md`. **Fix:** one line per non-obvious depend
(`# qt6-svg: SDDM renders share/avatars/*.svg`), the rest to the doc.

### 4.3 `pkgdesc` says Kids Mode twice and Omarchy twice (low)

`PKGBUILD:18`. **Fix:** "Kids Mode for Omarchy: one real account per kid, the parent never
restricted".

### 4.4 `post_upgrade` talks (low)

`omarchy-kids.install:32` prints "Kids Mode is installed. Run: omarchy-kids" on every upgrade.
Arch scriptlets speak only when the admin must act. **Fix:** silent upgrade.

### 4.5 `User=root` spelled out (low)

`omarchy-kids-authd.service`, `-time-ledger.service`, `-wifid.service`. It's the default; a
reviewer reads it as "did they mean something else?". **Fix:** drop the three lines.

### 4.6 `ExecStartPre=/bin/sleep 20` (low)

`omarchy-kids-boot-login-cleanup.service`. A sleep as an ordering contract; the three-line comment
says why but not why 20. **Fix:** name the observation the number came from, or order the unit
`After=graphical.target` and let a `.timer` `OnActiveSec=` carry the delay.

### 4.7 The drawer entry named an icon that isn't shipped (medium) — applied

`desktop/omarchy-kids.desktop:6` `Icon=omarchy-kids`; nothing installs one, so the app drawer
showed the missing-icon placeholder. **Fix:** Omy's owl (`share/avatars/owl.svg`, already
packaged). A purpose-drawn icon later is a one-line change.

---

## 5. README, install, parent card, CHANGELOG, AGENTS

### 5.1 README's "What is here now" described the empty skeleton (medium) — applied

`README.md:77-90`: a three-row table (`omarchy-kids-check`, `verify-phase1.sh`, "a T2 MacBook
note") and a section about an old pull request, under a "What works today" list that is current.
**Fix:** one paragraph pointing at the 26 commands, `lib/`, `share/`, `test/all`, and `AGENTS.md`'s
Layout table.

### 5.2 "What will be here" still promises two things the code refuses (medium)

`README.md:73` "Exit modal … **Pause** (kid's apps stay open)" — Pause is rendered and refused
(`docs/phase1/DECISIONS-NEEDED.md`); `:74` "`time`, `dns`, `apps` also exposed as
`omarchy-parent-<feature>`" — nothing ships under that name. The heading says "will", but a parent
skims tables. **Fix:** mark both rows "planned" in the cell, or drop them until they exist.

### 5.3 Two dates (low)

`README.md:22` "as of the evening of 2026-09-02" above a "What works today" list that changed on
the 3rd. **Fix:** one date at the top of "Status", or none (the loop report carries dates).

### 5.4 CHANGELOG skips five merged issues (medium)

`CHANGELOG.md` has Added (#8–#39), Fixed, Security (#58), and now Changed (#56, this review) —
nothing for #49 (the refactor), #51 (round-one security), #53 (kid theme), #55 (launch fold), #57
(light themes). A maintainer reading the log sees `#39` then `#56`. **Fix:** one line each.

### 5.5 `AGENTS.md` rule 8 is a paragraph (low)

Eleven lines, three exceptions. **Fix:** rule 8 = "`DRY_RUN=1` by default, `--apply` to write";
rule 8a = "`assert` is real by default (the hook)"; rule 8b = "the two interactive commands are
real when a human is driving". Same content, three findable rules.

### 5.6 `docs/style.md` §4 still lists `tui-demo` among the commands (low)

It moved to `scripts/` in #56. **Fix:** drop it from the list (and `wifi`'s removed `portal`).

### 5.7 `docs/install.md`, `docs/parent-card.md` — no finding

Both say what isn't built in the same breath as what is. The card's Time's Up paragraph
(`:25-28`) became true with 1.2.

---

## What is already good (quote freely)

- **One file per command, thin `main`, `lib/<command>-<area>.sh` for the rest** — the same shape
  as `bin/omarchy` over many `bin/omarchy-<verb>-*` scripts. `check`, `assert`, `panel`, `wizard`,
  `provision` all read top to bottom in one sitting.
- **`--help` on all 26 commands**, each stating its exit codes and its `DRY_RUN` posture in plain
  words. `run` prints the shell-quoted command it would have run; `--apply` is the only way to write.
- **The theme plumbing is Omarchy's own**: `lib/theme.sh` asks `omarchy-theme-color`, `lib/tui.sh`
  hands gum the theme through `GUM_*` env only where the session hasn't already, `KidsTheme.qml`
  reads `colors.toml` with `shell/Commons/Color.qml`'s fallback chain. No hex per screen.
- **The trust boundary is a test** (`test/shell.d/trust-boundary-test.sh`), with an allowlist that
  says why each remaining setting is allowed. Reviewers can grep for the rule instead of trusting it.
- **Copy tone**: "First, your password.", "How old is Ada?", "That wasn't it.", "Left setup.
  Nothing changed." — terse, warm, second person, the installer's voice.
- **Every screen is keyboard-complete**, and each footer says how.
- **Docs per command with a "Verified live" section**, and an honest "What's unverified" beside it.
  `README.md`'s "What works today" is drawn from those, not from the spec.
- **Tests list their skips** instead of hiding them in a green count.
