# Session entry: `omarchy-kids-session` and `omarchy-kids-ask-grownup` (R-DESK-1, R-DESK-2, R-WEB-4, R-FND-2a, I-3, I-4, I-9)

The kid session entry point. SDDM's `omarchy-kids` tile runs this through
`/usr/share/sddm/scripts/wayland-session` the same way Omarchy's own session runs
`uwsm start -g -1 -e -D Hyprland hyprland.desktop`; `desktop/omarchy-kids-session.desktop`
(`Exec=omarchy-kids-session`) is installed as `/usr/share/wayland-sessions/omarchy-kids.desktop`,
so this is the whole session command SDDM invokes for a kid tile.

## What it does

1. Figures out the account: `id -un`. (`OMARCHY_KIDS_ACCOUNT` overrides this for tests.)
2. Runs every R-DESK-2 check below, in order.
3. On the first check that fails closed: shows a full-screen "Ask a grown-up" naming the check
   (`omarchy-kids-ask-grownup "<check name>"`) and exits 1. **Fail closed** — a kid never lands
   on an unfenced desktop because a lock silently went missing (I-4, I-9).
4. Once every fail-closed check passes: exports `OMARCHY_KIDS_ACCOUNT`, `OMARCHY_KIDS_LEVEL`,
   `OMARCHY_KIDS_BAND`, `OMARCHY_KIDS_HYPRLAND_DIR` and `exec`s
   `Hyprland --config /etc/omarchy-kids/hyprland/L<level>.lua` (or whatever
   `OMARCHY_KIDS_HYPRLAND_BIN` names, for tests). The kid's own `~/.config/hypr` is never read
   (R-DESK-6): `--config` picks the root-owned file exclusively.

Every check's result — PASS, FAIL, or WARN — is logged, one line per check, to
`$OMARCHY_KIDS_RUN_DIR/session-<uid>.log` (default `$XDG_RUNTIME_DIR/omarchy-kids/session-<uid>.log`
— deliberately *not* `/run/omarchy-kids`, which is root-owned and this process never is root).

## The checks (R-DESK-2), in order

| # | Check | Name (shown to a grown-up / in `--check`) | Fails closed? |
| --- | --- | --- | --- |
| a | Profile present at `/etc/omarchy-kids/kids/<account>.conf`, and `level`/`band`/`web` resolve | `profile present` | Yes |
| b | `/etc/chromium/policies/managed/omarchy-kids-<band>.json` readable by this account, **unless** the profile's `web` is `none` (R-WEB-4) | `browser policy readable` | Yes |
| c | `/etc/polkit-1/rules.d/40-omarchy-kids.rules` and `41-omarchy-kids-deny.rules` both exist | `polkit rules present` | Yes |
| d | `findmnt -no OPTIONS "$HOME"` contains `noexec` | `home noexec` | Yes |
| e | `findmnt -no OPTIONS /tmp` contains `noexec` | `private /tmp noexec` | **No — WARN only, for now** |
| f | `systemctl is-enabled getty@tty2.service` prints `masked` | `consoles masked` | Yes |
| g | `/etc/omarchy-kids/hyprland/L<level>.lua` exists | `level config present` | Yes |

Check (e) is a warning, not a fail-closed check, because `pam_namespace` for `/tmp` (R-FND-2a) is
new and not yet verified everywhere it needs to run; locking every kid out over a fence that isn't
fully rolled out would be worse than warning. `omarchy-kids-session` still logs it every run
(`result=WARN`) so it shows up in `--check`'s table and the session log — once R-FND-2a is
verified end to end, flipping it to fail-closed is a one-line change (move `check_tmp_noexec`'s
logic to return 1 with `RESULT=FAIL` like the others).

A missing profile ((a)) is also how a non-kid account gets refused: if `id -un` isn't a
provisioned kid, there's no profile, check (a) fails, and the session refuses to start — the same
fail-closed path as every other check, not a special case.

## `omarchy-kids-session --check`

Runs every check above (not stopping at the first failure — it always produces the full table)
and prints a `CHECK / RESULT / DETAIL` table instead of starting anything. Exits 0 if nothing
FAILed (a WARN doesn't fail this), 1 if anything did. Built so `omarchy-kids-check` (the
green/red "is it safe?" tool, currently a stub of its own from an earlier issue) can shell out to
this instead of re-implementing R-DESK-2's checks a second time — that wiring is that command's
own issue, not this one's; this ticket only builds the flag.

## `omarchy-kids-session --install-configs`

Copies every `*.lua` under `$OMARCHY_KIDS_SHARE/hyprland/` (the package's
`/usr/share/omarchy-kids/hyprland/`) to `$OMARCHY_KIDS_ETC/hyprland/` (`/etc/omarchy-kids/hyprland/`)
with mode 0644. This is the root-owned copy that `L1.lua`/`L2.lua`/`L3.lua`'s band overlays
`dofile()` at Hyprland config-parse time (`docs/levels.md`) — it has to exist and stay current, or
check (g) above fails closed and every kid is locked out after an update that touched those Lua
files. Meant to be called by the package's `post_install`/`post_upgrade` hook
(`omarchy-kids.install`) and by `omarchy-kids-assert` (R-TRUST-5), so this copy can never go stale
after a pacman transaction — **neither of those exists yet** (`omarchy-kids-assert` is still a
stub from its own issue, and `omarchy-kids.install` doesn't call this flag). Wiring `--install-configs`
into them is that other work's job; this ticket only builds and tests the flag itself.

## Env (every path overridable — nothing here ever runs as root in dev, per AGENTS.md rule 8)

| Var | Default | Affects |
| --- | --- | --- |
| `OMARCHY_KIDS_ETC` | `/etc/omarchy-kids` | the kid's profile (`kids/<account>.conf`); `--install-configs`' destination (`hyprland/`); check (g)'s level config path |
| `OMARCHY_KIDS_SHARE` | `/usr/share/omarchy-kids` | `--install-configs`' source (`hyprland/*.lua`) |
| `OMARCHY_KIDS_ROOT` | (empty — the real paths) | scratch prefix for the two system paths this doesn't own: `/etc/chromium/policies/managed` (check b) and `/etc/polkit-1/rules.d` (check c). Same convention `bin/omarchy-kids-provision` and `lib/posture.sh` already use for `/etc/polkit-1` et al. — see "Judgment calls" below |
| `OMARCHY_KIDS_RUN_DIR` | `${XDG_RUNTIME_DIR:-/run/user/<uid>}/omarchy-kids` | where the per-session check log (`session-<uid>.log`) is written |
| `OMARCHY_KIDS_ASK_GROWNUP_BIN` | resolved beside this script, else `/usr/bin/omarchy-kids-ask-grownup` | what runs on the first fail-closed check |
| `OMARCHY_KIDS_ACCOUNT` | `id -un` | which account's profile/checks run (test hook) |
| `OMARCHY_KIDS_ASK_GROWNUP_SLEEP` | 15 | (on `omarchy-kids-ask-grownup`) seconds the message holds the screen before exiting — tests set this to 0 |

`test/shell.d/session-test.sh` runs entirely against scratch trees built from these, with stub
`findmnt`, `systemctl`, and `Hyprland` on a stub `PATH` that read/report from small control files
this test writes per scenario — see that file's header comment for exactly how.

## `omarchy-kids-ask-grownup`

`omarchy-kids-ask-grownup "<check name>"` — the message shown on the first fail-closed check.
**This is a placeholder, not the real modal**: at the point `omarchy-kids-session` calls it,
Hyprland hasn't started, so there's no compositor and nothing graphical to draw into. All it can
honestly do today is print a message and hold the screen for a while:

- If `gum` is on `PATH`, a big centered `gum style` box.
- Otherwise, plain text between two banner lines.
- Either way, to the real tty if one is attached (falling back to stdout, e.g. in a test run with
  no controlling terminal), then `sleep 15` (override: `OMARCHY_KIDS_ASK_GROWNUP_SLEEP`) and exit 1.

A real graphical modal — rendered by whatever runs the portal/greeter, or a tiny standalone
compositor client — is a separate ticket; this script is what that ticket should replace, not
build on top of.

## Judgment calls made in this implementation

- **`OMARCHY_KIDS_ROOT` for the Chromium policy and polkit paths.** Neither
  `/etc/chromium/policies/managed` nor `/etc/polkit-1/rules.d` is owned by this package (the
  first is Chromium's, the second polkit's), so they don't live under `OMARCHY_KIDS_ETC`. The
  issue text's env list names only `OMARCHY_KIDS_ETC`, `OMARCHY_KIDS_SHARE`, `OMARCHY_KIDS_RUN_DIR`,
  and `OMARCHY_KIDS_HYPRLAND_BIN` — reusing `bin/omarchy-kids-provision`'s and `lib/posture.sh`'s
  own `OMARCHY_KIDS_ROOT` convention for exactly this class of system path (rather than inventing
  a second, differently-named scratch var, or leaving these two checks untestable without real
  root) was the more consistent reading, and it's what `test/shell.d/session-test.sh` builds its
  scratch `/etc/chromium/...` and `/etc/polkit-1/...` under.
- **`OMARCHY_KIDS_RUN_DIR`'s default is `$XDG_RUNTIME_DIR/omarchy-kids`, not `/run/omarchy-kids`.**
  The rest of this repo's `/run/omarchy-kids` (session-start's launcher JSON, the boot slot file)
  is root-owned; `omarchy-kids-session` runs as the kid, who cannot write there. The per-user
  runtime dir is the one writable place a non-root session process reliably has.
- **`--install-configs` sets mode 0644 only, no `chown`** — the same call `docs/provision.md`
  makes for its own writers: a real run of this always happens as root already (package hooks,
  `omarchy-kids-assert`), at which point everything it creates is already root-owned by virtue of
  the process, and adding an explicit `chown` would only add a privileged call that fails outright
  in the scratch trees this had to be built and tested against on a non-root Mac (AGENTS.md rule 8).
- **No `DRY_RUN` gate on `--install-configs`**, unlike `omarchy-kids-provision`. It's a plain,
  idempotent file copy (no account creation, no LUKS, nothing destructive to reverse), the same
  risk class as `bin/omarchy-kids-boot-login`'s writes, which also has no `DRY_RUN` — both are
  made safe for dev/test by their path overrides (`OMARCHY_KIDS_ETC`/`OMARCHY_KIDS_SHARE` here),
  not by a dry-run flag.
- **No associative arrays.** The id → human check-name mapping is a `case` statement
  (`check_name()`), not a `declare -A` table, because this was built and tested on the same bash
  3.2 macOS box `bin/omarchy-kids-session-start`'s header comment calls out (`tr` instead of
  `${var,,}`) — bash 3.2 doesn't have associative arrays at all, and silently misparses
  `declare -A X=([foo]=...)` as an *indexed* array trying to evaluate `foo` as an arithmetic
  subscript, which fails with `foo: unbound variable` under `set -u`. Worth remembering for any
  future edit to this file: stick to indexed arrays, `case`, and plain variables.
- **`--check` always runs every check**, even after the first FAIL, instead of stopping early
  like a normal start does. The issue only says `--check` "prints a table"; running the full set
  makes that table an actual diagnostic (see every check's state at once), which is also what a
  tool like `omarchy-kids-check` needs from it — stopping at the first FAIL would just reproduce
  `omarchy-kids-session`'s own start behavior with extra steps.
- **`omarchy-kids-ask-grownup`'s tty detection actually attempts the write** (`{ : > /dev/tty; }
  2>/dev/null`) rather than checking `[[ -w /dev/tty ]]` first. The permission-bit check can look
  writable with no controlling terminal attached (common in a test run, or a session started in
  an unusual way) and then fail with `ENXIO` on the real write — attempting the open directly and
  falling back to stdout on failure sidesteps that instead of trusting the permission bits.

## Verify in the VM

This has never run against a real Hyprland, SDDM, or `pam_namespace` setup — everything below is
open until it has:

1. Provision a kid (`docs/provision.md`) so `/etc/omarchy-kids/kids/<account>.conf` and every
   R-DESK-2 lock actually exist, then pin that account to the `omarchy-kids` session via
   AccountsService (`docs/provision.md`'s step 10 does this automatically for a kid `add`; to
   force it by hand, `Session=omarchy-kids` / `XSession=omarchy-kids` in
   `/var/lib/AccountsService/users/<account>`).
2. Run `omarchy-kids session --install-configs` (or run it manually as root once) so
   `/etc/omarchy-kids/hyprland/L<level>.lua` exists — check (g) fails closed without it.
3. Log in as the kid at the SDDM portal. Confirm: the level's Hyprland session starts, the kid's
   own `~/.config/hypr` is never touched, and `Super+Home`/the level's other binds
   (`docs/levels.md`) work.
4. Break one lock on purpose (e.g. `chmod 000` the browser policy file, or
   `systemctl unmask getty@tty2.service`), log in again, and confirm the "Ask a grown-up" message
   appears naming that check, then the session exits back to the portal after ~15s.
5. Read `$XDG_RUNTIME_DIR/omarchy-kids/session-<uid>.log` from a still-open terminal (or from the
   parent's session with sufficient access) and confirm every check's result is there.
6. `omarchy-kids-session --check` from a terminal in the kid's own session (or `su`'d to that
   account) and confirm the table matches what actually happened at login.

## Verified live (2026-09-02, QEMU test VM)

Cold boot with a kid's password → LUKS slot recorded → per-boot autologin into the `omarchy-kids`
session → every R-DESK-2 check passed (private `/tmp` a warning) → `Hyprland --config
/etc/omarchy-kids/hyprland/L1.lua` → `omarchy-kids-session-start` wrote the tile file and started
the Level 1 launcher (Quickshell): nine tiles for the 6-8 pack plus the web app, a clock, keyboard
highlight. Fixes that came out of the run: the polkit check goes through `pkcheck` (the rules
directory is 0750 root:polkitd), `Hyprland --verify-config` is a fail-closed check because
emergency mode binds a terminal, the level configs set their own Lua path, and all launcher state
lives under the kid's `XDG_RUNTIME_DIR`.

Confirmed again later the same night on a clean package install and a cold boot with no manual
step: slot recorded, `omarchy-kids-boot-login` wrote the drop-in, kid-cy on seat0, `Hyprland`
and `quickshell` running as the kid, the control file present. The owner's disk password on the
same machine lands on the owner's own desktop (R-BOOT fail-safe), not the portal. Two package
gaps found by this run are now assert locks: `units` (the package's units must be enabled) and
the earlier `limine-editor`.

## Source header (moved from `bin/omarchy-kids-session-start`, issue #49)

Kept for reference; the file itself now carries a 3-line pointer instead.

```text
omarchy-kids-session-start: run once per kid Hyprland session via
`exec-once`/`hl.on("hyprland.start", ...)` from share/hyprland/L1.lua,
L2.lua, and L3.lua (SPEC.md R-DESK-1, R-DESK-3, R-DESK-5, Appendix E).

Writes the Level 1/2 launcher's tile list to
$XDG_RUNTIME_DIR/omarchy-kids/launcher-<uid>.json from the kid's
effective allowlist (`omarchy-kids-apps allowlist`, R-APPS-4: the
band's pack plus apps.extra minus apps.hidden -- not the raw
`omarchy-kids-conf get <kid> allowlist`, so a hide/show lands here too)
and pack metadata (share/packs/<band>.toml), then starts the right
thing for the level:
  Level 1 -> the standalone big-tile launcher (quickshell -p ...), the
             *only* thing running (R-DESK-5: not a shell plugin).
  Level 2/3 -> Omarchy's own shell, the same way Omarchy's own
             default.hypr.autostart does (`omarchy-launch-shell`), after
             also writing the same allowlist to $RUN/allowlist.json
             (docs/apps.md) for the trimmed-menu extension to read.

Also starts, detached, the screen-time engine's per-session daemon
(bin/omarchy-kids-time daemon, SPEC.md R-TIME-1..5) -- see that
file's own header for what it does and lib/time.sh's for the ledger
trust boundary. The exit overlay (bin/omarchy-kids-exit, R-EXIT-1) is
bound directly in share/hyprland/L1.lua etc., not started from here.

Every path below is overridable for tests, same convention as
omarchy-kids-conf and docs/conf.md:
  OMARCHY_KIDS_ETC     kid overrides root (default /etc/omarchy-kids)
  OMARCHY_KIDS_SHARE   bands.toml, packs/, launcher/ (default /usr/share/omarchy-kids)
  OMARCHY_KIDS_RUN     runtime state root (default $XDG_RUNTIME_DIR/omarchy-kids)
  OMARCHY_KIDS_ROOT    scratch prefix for /var/lib/omarchy-kids (issue
                                  #42: reads the same apps-queue file
                                  bin/omarchy-kids-apps writes, to tell
                                  a merely-missing tile apart from one
                                  that's mid-install; same convention
                                  omarchy-kids-apps itself uses)
  OMARCHY_KIDS_ACCOUNT  kid account (default: this process's own user)
  OMARCHY_KIDS_LEVEL    1/2/3 (default: omarchy-kids-conf get <account> level)
  OMARCHY_KIDS_BAND     3-5/6-8/9-12/13+ (default: omarchy-kids-conf get <account> band)
  OMARCHY_KIDS_APPLICATIONS_DIRS  colon-separated .desktop dirs to search
                                  for a pack app's launcher entry
                                  (default /usr/share/applications:/usr/local/share/applications)
  OMARCHY_KIDS_SESSION_START_NO_EXEC=1  write the JSON, print the exec
                                  line that would run, and return 0
                                  instead of exec'ing it (test hook --
                                  also skips starting omarchy-kids-time,
                                  same as it skips the real exec below)
```

## Source header (moved from `bin/omarchy-kids-session`, issue #49)

Kept for reference; the file itself now carries a 3-line pointer instead.

```text
omarchy-kids-session: the kid session launcher (SPEC.md R-DESK-1,
R-DESK-2, R-WEB-4, R-FND-2a, I-3, I-4, I-9, §5.2 "Kid login").

Run by /usr/share/wayland-sessions/omarchy-kids.desktop
(desktop/omarchy-kids-session.desktop), which SDDM starts through
/usr/share/sddm/scripts/wayland-session the same way it starts
Omarchy's own `uwsm start -g -1 -e -D Hyprland hyprland.desktop`.

Sequence: figure out the account (`id -un`), run every R-DESK-2 check
in order, and on the first fail-closed miss show a full-screen "Ask a
grown-up" (omarchy-kids-ask-grownup) and exit 1 -- fail closed, never
a silent, unfenced desktop (I-4, I-9). Once every fail-closed check
passes, export the account/level/band and exec Hyprland with the
level's root-owned config -- never the kid's own `~/.config/hypr`
(R-DESK-6, I-3).

--check runs every check and prints a PASS/FAIL/WARN table without
starting anything, for `omarchy-kids-check` to reuse.

--install-configs copies the level configs this package ships
($OMARCHY_KIDS_SHARE/hyprland/*.lua) to the root-owned copy under
$OMARCHY_KIDS_ETC/hyprland the level files' band overlays `dofile()`
at Hyprland config-parse time. Meant to be called by the package's
post_install/post_upgrade hook and by `omarchy-kids-assert`
(R-TRUST-5) so that copy can never silently go stale -- neither of
those callers exists yet (both are separate issues' stubs as of this
one); wiring this flag into them is that issue's job, not this one's.

Never runs anything as root itself and never assumes it -- every path
below is overridable so this (and test/shell.d/session-test.sh) can
run entirely as a normal user against a scratch tree (AGENTS.md rule
8):
  OMARCHY_KIDS_ETC              kid overrides root (default /etc/omarchy-kids;
                                the level configs this reads/writes for
                                --install-configs live at $OMARCHY_KIDS_ETC/hyprland)
  OMARCHY_KIDS_SHARE            package data root (default /usr/share/omarchy-kids;
                                --install-configs' source is $OMARCHY_KIDS_SHARE/hyprland)
  OMARCHY_KIDS_ROOT             scratch prefix for the system paths this
                                doesn't own -- /etc/chromium/policies/managed
                                and /etc/polkit-1/rules.d -- default empty
                                (the real paths); same convention
                                bin/omarchy-kids-provision and lib/posture.sh
                                already use for /etc/polkit-1 et al.
  OMARCHY_KIDS_RUN_DIR           per-session log directory. Default
                                $XDG_RUNTIME_DIR/omarchy-kids (falling back to
                                /run/user/<uid>/omarchy-kids) -- deliberately
                                NOT /run/omarchy-kids, which is root-owned and
                                this process is never root.
  OMARCHY_KIDS_ASK_GROWNUP_BIN    path to omarchy-kids-ask-grownup (default:
                                resolved beside this script, else /usr/bin)
  OMARCHY_KIDS_ASK_GROWNUP_SLEEP  seconds omarchy-kids-ask-grownup sleeps for
                                (default 15; tests set this to 0)
```

## Level and band are outputs, not inputs (issue #58)

`bin/omarchy-kids-session-start` used to prefer `$OMARCHY_KIDS_LEVEL` / `$OMARCHY_KIDS_BAND` over
the root-owned profile, so a 13+ kid on Level 1 could run
`OMARCHY_KIDS_LEVEL=2 omarchy-kids-session-start` from their terminal and get Omarchy's full shell
and launcher inside their own session (review §3.4). Both now come from
`omarchy-kids-conf get <account> <key>` unconditionally, and the account comes from `id -un`.

`bin/omarchy-kids-session` execs `/usr/bin/Hyprland` (a constant, not `$OMARCHY_KIDS_HYPRLAND_BIN`
and not a bare name resolved through the kid's own `PATH`, which a kid can set through
`~/.config/environment.d/`). And `share/hyprland/L{1,2,3}.lua` set a fixed `package.path` instead
of `(os.getenv("OMARCHY_PATH") or …) .. package.path`, and `dofile` the band overlay from a fixed
`/etc/omarchy-kids/hyprland` — otherwise anything that seeded the session environment could make
`require("default.hypr.helpers")` load kid-authored Lua at config-parse time, which is the whole
Level 1 fence (review §3.5).

## The trust boundary (issue #58)

This command resolves `lib/` and every sibling `omarchy-kids-*` from its own resolved location
(`readlink -f "$0"`), else the installed prefix — never from the environment. `$OMARCHY_KIDS_LIB`,
the `*_BIN` / `*_PY` overrides, the socket paths and the `*_REQUIRE_ROOT` escapes are gone:
`AGENTS.md` rule 9 states the rule and `test/shell.d/trust-boundary-test.sh` enforces it, with the
allowlist of the data settings that stay. A test that needs a stub places it beside a copy of the
command in a scratch tree (`test/shell.d/tree.sh`), or substitutes a build-time constant, the way
`PKGBUILD` substitutes `KIDS_PY` at package time.
