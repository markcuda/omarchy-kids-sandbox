# Review 2 — omarchy-kids-sandbox @ fd072a9

Second pass, read against round one (`docs/reviews/2026-09-03-antagonistic.md`), `AGENTS.md`,
`docs/style.md`, and Omarchy v4.0.2 as the house style. Since round one: #51 (security), #47
(theme), #49 (structural refactor: `lib/kids.sh`, dispatchers, strict mode, headers), #50 (wizard
card), #54 (launcher layout), #52 (packs audit), the launch-fold fix.

`test/all` is green: 31 files, 4 skipped checks now *listed* (a real improvement). `shellcheck -x`
on `bin/` + `lib/` is clean. Comment ratio in `bin/`+`lib/` is down from 26% to 17.0%
(2,280 / 13,453). None of that is what follows.

---

## 1. Round one, item by item

### §1 — the ten changes

| # | Verdict | Evidence |
| --- | --- | --- |
| 1. Kid grants themselves anything | **fixed** | `bin/omarchy-kids-ask:170` (`submit` builds argv with no `--state`), `:352-364` (`collect` only ever calls `ask.py reopen`), `lib/ask.py:143-146`, `:256-290` (`reopen` forces `state:"open"` and re-derives `kid`), `bin/omarchy-kids-authd:226-258` (GRANT matches SO_PEERCRED against the request's `kid`). Covered by `test/shell.d/ask-test.sh:284-328`. |
| 2. Verifier a kid controls | **partly** | Fixed: `bin/omarchy-kids-parent-auth:29-45` (env + `--socket` root-only), `share/exit-modal/shell.qml:157`, `share/wifi/shell.qml:83`, `bin/omarchy-kids-session-start:284` all absolute. Not fixed: `bin/omarchy-kids-parent-auth:13` sources `$LIB/sock.sh` where `LIB="${OMARCHY_KIDS_LIB:-…}"` — a kid-owned env var, in the binary `lib/posture.sh:190` wires into the hyprlock PAM stack. See §2.1. Bare names remain at `share/time/timesup.qml:95,99`, `share/plugins/shell.qml:124`, `share/wifi/shell.qml:209,213`, `share/launcher/shell.qml:225`. |
| 3. `limine-editor` nested under the boot hook | **fixed** | `bin/omarchy-kids-assert:188-197` — `boot-hook` is inside the `if`, `limine-editor` is outside it, with a comment naming S5. Regression test at `test/shell.d/assert-test.sh:674-695` removes the hook file and asserts `limine-editor` still fires. |
| 4. Dry run prints both secrets | **fixed** | `lib/provision-add.sh:149-157` (fds 3/4 in a real run, `<secret> <secret>` in the preview), `:233-238` (`add_luks_slot` reads `<&3`/`<&4`, never argv, never through `run`). |
| 5. Shipped app entry runs in preview | **fixed** | `bin/omarchy-kids-panel:41-49`, `bin/omarchy-kids-wizard:52-60` (`launched_by_a_human` → `DRY_RUN=0`), `desktop/omarchy-kids.desktop:5` sets `OMARCHY_KIDS_LAUNCHED_BY`. `test/shell.d/wizard-test.sh` covers all three cases. |
| 6. `kid-` username heuristic in `boot-login` | **fixed** | `bin/omarchy-kids-boot-login:36-42` — `[[ -f "$ETC/kids/$1.conf" ]]` decides. |
| 7. Seven copies of `run()` | **partly** | `lib/kids.sh:14-153` now owns `run`, `group_for_band`, `home_dir_for`, `parent_home_dir`, `detect_luks_device`, `file_stat`, `kids_bin`, `kids_list`, `portal_conf_entries`, the modal pidfile pair; `lib/sock.sh:15` owns the socket client. Still duplicated, with the apology comments intact: `band_field` (`bin/omarchy-kids-provision:107` and `bin/omarchy-kids-wizard:108`, whose comment at `:105-107` re-argues the case round one rejected), `is_valid_band` ×4 (`provision:90`, `web:65`, `apps:83`, `plugins:64`), `VALID_BANDS=(…)` ×6 (`apps:28`, `plugins:23`, `wizard:62`, `conf:35`, `provision:31`, `web:19`), `validate_budget_minutes`/`validate_lights_out`/`friendly_web_mode` (`panel:190,196,175` vs `wizard:288,296,354` — byte-identical), `launched_by_a_human` (`panel:41`/`wizard:52`), `run_priv` (`panel:109`/`wizard:184`), `is_known_kid` (`ask:312`/`time-ledger:42`). And `lib/data.sh:83` re-implements the GNU/BSD `stat` wrapper that `lib/kids.sh:77` was created to replace — with the BSD-first bug `kids.sh:72-76` documents. See §2.3. |
| 8. 26% comments, headers contradicting the code | **partly** | `bin/`+`lib/` fell to 17.0%; the ten-worst table's entries 2,3,4,5,6,9,10 are gone. Untouched: `share/sddm-theme/Main.qml:1-144` (entry 1, still 144 lines), `share/exit-modal/shell.qml:1-52` (entry 7, still 52 lines, still opening `====== UNTESTED ======` / "has never run against a real Quickshell or Hyprland"), now contradicted three ways *inside the same file*: `:68` "Verified live 2026-09-02", `:70` sets the `WlrLayershell.keyboardFocus` the banner at `:35-39` says "is NOT set below at all", `:191` "seen live 2026-09-02". `share/launcher/shell.qml` 49-line run, `share/bar/KidsModule.qml` 55. |
| 9. `a && b \|\| c` on `--finish`; pgrep modal guard | **partly** | `bin/omarchy-kids-exit:190-194` is now an `if`; `lib/kids.sh:141-153` is a real pidfile + `/proc/<pid>/comm` check, used at `exit:63` and `ask:102`. But `bin/omarchy-kids-time:107` and `:132` still do `pgrep -f "quickshell -p $1"` / `pkill -f` on the QML path — the identical bug, in the file that enforces bedtime. See §2.6. |
| 10. LUKS slot detection | **fixed** | `lib/provision-add.sh:218-223` (`luks_occupied_slots`), `:240-242` (rejects a kid password that already unlocks the device), `:244-253` (before/after diff, no `\|\| true`). |

### §2 — security findings

| ID | Verdict | Evidence |
| --- | --- | --- |
| S1 kid-authored "approved" applied by root | **fixed** | as item 1. `lib/ask.py:144-146` states it; `bin/omarchy-kids-ask:352-364` enforces it. |
| S2 `apply_record` trusts the `kid` field | **fixed** | `bin/omarchy-kids-ask:293-310` derives the owner from the uid in the `/run/user/<uid>/…` path; `:333-340` skips an outbox whose owner is not a provisioned kid; `bin/omarchy-kids-authd:251-253` refuses a GRANT whose `kid` ≠ the peer's account. |
| S3 root path traversal via `kid` | **fixed** | `lib/ask.py:53-55` (`RE_ACCOUNT`), `:64-91` (`validate_grant` rejects `..`, `/`, leading dot), called from `reopen` (`:277`), `request-json` (`:302`), `validate` (`:317`). Test fixture at `test/shell.d/ask-test.sh:294-296`. |
| S4 PATH/env redirection of the verifier | **partly** | The env var and `--socket` are now root-only (`bin/omarchy-kids-parent-auth:34-37,41-44`) and the PAM binary path is absolute (`lib/posture.sh:190`). The `OMARCHY_KIDS_LIB` source at `parent-auth:13,15` reopens the whole hole. See §3.1. |
| S5 `editor_enabled: no` unenforced without the hook | **fixed** | `bin/omarchy-kids-assert:192-197`; the non-atomic `cat "$tmp" > "$f"` is gone — `lib/assert-limine.sh:20-24` and `:65,93-94` are temp-file-then-rename. |
| S6 both secrets in the default dry run | **fixed** | `lib/provision-add.sh:148-157`. |
| S7 anyone local can lock the parent out | **partly** | `bin/omarchy-kids-authd:136-184` is per-uid with a 300 s decay; `:449-451` is one thread per client. Still: the socket is `0666` (`systemd/omarchy-kids-authd.socket:7`, `bin/omarchy-kids-authd:386`) and the thread pool is unbounded — see §2.5. |
| S8 Wi-Fi password echoed back | **fixed** | `bin/omarchy-kids-wifid:128-131` — only `args[0]`, with a comment naming S8. |
| S9 unquoted heredoc generating a polkit rule | **fixed, then re-broken by its own guard** | `lib/posture.sh:50-52` (`posture_valid_account`), `:56-59`, `:467-470`. But the guard's `return 1` is swallowed at `:78` and `:502`. See §2.2 — this is now worse than the original. |
| S10 display name never validated | **fixed** | `bin/omarchy-kids-provision:97-103`, called at `lib/provision-add.sh:37`; `lib/posture.sh:477-480` drops a legacy bad name rather than corrupting the greeter. |
| S11 fail-open self-checks | **partly** | `bin/omarchy-kids-assert:83-99` gives `*_ok` a three-way status, and `bin/omarchy-kids-check:118-124,189-190` turns `warn` into exit 1. `gecos_ok` (`lib/assert-locks.sh:60`), `parent_unlock_ok` (`:181`), `parent_group_ok` (`:234`), `hyprland_ok` (`:252`) all return 2 now. Still fail-open: `lib/assert-locks.sh:286-292` — `chromium_fix` chowns best-effort and `return 0` regardless, so a policy file owned by the wrong group reports `fixed`. And `lib/assert-limine.sh:10` returns 2 on *every* non-Limine box, so a GRUB or systemd-boot machine permanently reports `warn limine-editor` and `omarchy-kids-check` permanently exits 1. |
| S12 bare-name exec of privileged-ish commands | **partly** | Fixed: `bin/omarchy-kids-super-tap:13` (`/usr/bin/omarchy-kids-exit`), `share/exit-modal/shell.qml:157,193-195`, `bin/omarchy-kids-session-start:284` (`/usr/bin/omarchy-launch-shell`). Not fixed: `share/time/timesup.qml:95,99` (`execDetached(["omarchy-kids-exit","--finish"])` — the one that ends a session), `share/plugins/shell.qml:124`, `share/wifi/shell.qml:209,213` (same file that got the absolute path at `:83`), `share/launcher/shell.qml:225`, `bin/omarchy-kids-session:19` (`HYPRLAND_BIN="${OMARCHY_KIDS_HYPRLAND_BIN:-Hyprland}"`), `bin/omarchy-kids-time:96`. |

### §6 — dead, unreachable, half-built

Fixed: `share/tui/screens/` deleted; `bin/omarchy-kids-provision:228`'s empty banner gone (the file
is a dispatcher now); `_ = account` gone from `bin/omarchy-kids-wifid`; the double `mkdir` in
`session-start` gone; `--pause`'s kid-settable env gate replaced by a hardcoded
`property bool pauseAvailable: false` (`share/exit-modal/shell.qml:126`); `omarchy-kids.install`'s
"nothing runs until Apply" is closed *indirectly* — `pacman/omarchy-kids.hook:17` runs
`omarchy-kids-assert`, and `bin/omarchy-kids-assert:125-136` now enables units with zero kids.

Not fixed: `polkit/` and `sudoers/` are still `.gitkeep` directories `AGENTS.md`'s Layout table
describes as holding templates. `PKGBUILD:66`'s `bin/omarchy-kids-*` glob still ships
`omarchy-kids-tui-demo` to `/usr/bin`. `PKGBUILD:43` still has no dependency on `omarchy`, `sddm`
or `hyprland`, though `share/hyprland/L1.lua:50-54` requires `/usr/share/omarchy/default/hypr/*`
and `bin/omarchy-kids-session-start:284` execs `/usr/bin/omarchy-launch-shell`.
`bin/omarchy-kids-provision:173-192` still writes `migrations.log` from a "documented guess …
TODO(#10)". The Pause button is still rendered and preselected
(`share/exit-modal/shell.qml:328-352`, preselected at `:130-131`, hinted away at `:219-220`) for a feature `bin/omarchy-kids-exit:159-162`
refuses. `README.md:50-53` is still the two interleaved sentences, verbatim. Nine files still carry
`UNTESTED`/`UNVERIFIED` banners. And `lib/assert-locks.sh:245-248` now says
`omarchy-kids-session --install-configs` "doesn't yet exist — verified against this checkout"
while `bin/omarchy-kids-session:58` implements it — the comment inverted from speculative to false.

### On the tests

Skip counting: **fixed** (`test/all:12-27`); the run prints "4 skipped check(s) — these did NOT
run". The four are still `authd-test.sh`'s live password checks (`:309`), `wifi-test.sh` section B
(the SO_PEERCRED authorization boundary), the `luac` check, and the POSIX-sh check — i.e. the
honesty improved and the coverage did not. Implementation-pinning greps: **not fixed** —
`test/shell.d/portal-test.sh` still has 16 `grep -q` calls including `:140` (asserting the
*absence* of `new XMLHttpRequest`) and `:145` (`charAt(0).toUpperCase()`); `ask-test.sh` 11,
`exit-test.sh` 5. Security boundary tests: S1/S2/S3 now have real ones
(`ask-test.sh:284-328`), S5 has one (`assert-test.sh:674-695`), S4's env/`--socket` half has one
(`authd-test.sh:193-203`) — and `authd-test.sh:214` *exports* `OMARCHY_KIDS_LIB` to point the
binary at a different `lib/`, which is precisely the bypass nothing tests for.

---

## 2. New findings introduced by the refactor and the merges

### 2.1 `OMARCHY_KIDS_LIB` turns every command into a `source` of kid-chosen shell (critical, regression from #49)

`bin/omarchy-kids-parent-auth:13-15`, and the identical two lines in all 21 `bin/omarchy-kids-*`
bash commands:

```text
LIB="${OMARCHY_KIDS_LIB:-$DIR/lib}"; [[ -f "$LIB/sock.sh" ]] || LIB=/usr/lib/omarchy-kids
source "$LIB/sock.sh"
```text

Before #49 these commands had their socket client inline. Extracting it into `lib/` was right; the
resolver was not. `OMARCHY_KIDS_LIB` is read from the environment with no root gate — in the one
file whose whole header (`:7-9`) says *"it trusts nothing from its own environment"*.

**Failure scenario.** A kid writes `~/evil/sock.sh` containing
`kids_sock_request() { printf 'ok\n'; }`, then `export OMARCHY_KIDS_LIB=$HOME/evil` in
`~/.bashrc`/`~/.profile`. `lib/posture.sh:190` has installed
`auth [success=done default=ignore] pam_exec.so quiet expose_authtok /usr/bin/omarchy-kids-parent-auth`
into `omarchy-lock-password`; hyprlock runs as the kid, so pam_exec inherits the kid's environment.
Any password now unlocks the screen, and `success=done` ends the stack before pam_unix is
consulted. The same variable also redirects `bin/omarchy-kids-ask:11`, `-exit:11`, `-time:11`,
`-session:11` and `-check:12` (`bin/omarchy-kids-check:74` additionally `source`s whatever
`OMARCHY_KIDS_ASSERT_BIN` names).

**Fix.** Same shape as the `--socket` fix already in this file: honour `OMARCHY_KIDS_LIB` only when
`EUID == 0`, or (better) drop it and have the packaged copies hardcode `/usr/lib/omarchy-kids`
with a build-time substitution, the way `TEST_SOCKET_ROOT` (`parent-auth:23`) already works.

### 2.2 The S9 guard writes an empty polkit admin rule instead of refusing (critical)

`lib/posture.sh:78`:

```text
posture_install_if_changed "$file" "$(posture_polkit_admin_rule_text "$parent")" 0644
```text

`posture_polkit_admin_rule_text` returns 1 and prints nothing for an unusable `parent` (`:56-59`).
A `$(…)` in an argument list swallows that under `set -e` — verified: the caller runs with an
empty second argument and `rc=0`. `posture_install_if_changed` then writes a file containing a
single newline.

**Failure scenario.** `machine.conf` has `parent=Bob Smith` (a space — `posture_valid_account`
refuses it; `omarchy-kids-conf machine set parent` at `bin/omarchy-kids-conf:296-299` accepts any
non-empty single-line value, so this is reachable through the wizard's own Apply). `assert` →
`polkit_admin_fix` → `/etc/polkit-1/rules.d/40-omarchy-kids.rules` becomes empty, and assert
prints `fixed polkit-admin`. polkit has no admin rule, so every admin action in a kid's session
falls back to asking for **root's** password — the exact failure mode the guard's own comment
(`:47-49`) says it exists to prevent. Worse, it then reports green forever:
`lib/assert-locks.sh:109` compares `$(cat "$file")` against `$(posture_polkit_admin_rule_text …)`,
and `""=="" `passes.

`lib/posture.sh:502` has the identical shape for `theme.conf.user` — an unusable parent silently
produces a greeter with no `parent=` and no `kids=` line.

**Fix.** `local text; text="$(posture_polkit_admin_rule_text "$parent")" || return 1` before the
call, in both writers. Add a test that `posture_write_polkit_admin_rule 'Bob Smith'` returns
non-zero and leaves no file.

### 2.3 `lib/data.sh:83` kept the exact `stat` bug `lib/kids.sh:77` was created to remove

`lib/kids.sh:72-76` documents it in full: *"a BSD-first form silently misreads on Linux
(`stat -f` there means 'filesystem status', not BSD's 'format', seen live 2026-09-02…)"*. Two
files later:

```text
data_stat_inode() { stat -f '%i' "$1" 2>/dev/null || stat -c '%i' "$1" 2>/dev/null; }
```text

BSD-first. On Linux `stat -f '%i'` succeeds and returns the *filesystem* ID, identical for every
file on the same mount.

**Failure scenario.** `data_fold_launches` (`lib/data.sh:129-133`) uses that value to notice
"this is a new file after a fresh login". On Arch it never changes, so the inode half of the guard
is dead and only the `off > size` half survives — exactly the case `:117-122` says a size check
alone can miss. A kid who logs out and back in mid-day, whose new runtime log grows past the old
offset before the next tick, has the overlapping prefix silently dropped from
`/var/lib/omarchy-kids/<kid>/launches.log`.

**Fix.** `file_stat` grew one `case` arm short. Add `i) stat -f '%i'` under the BSD branch and
`stat -c '%i'` under the GNU branch (`lib/kids.sh:77-88`), then delete `data_stat_inode`.

### 2.4 A kid-written JSON field reaches bash arithmetic in the parent's panel (critical)

`lib/panel-requests.sh:56-59`:

```text
while IFS=$'\t' read -r id kid kind what minutes asked_at; do
    ...
    age="$(human_age $(($(date +%s) - asked_at)))"
```text

`asked_at` is not validated anywhere. `lib/ask.py:285` copies it verbatim out of the kid's own
outbox record into the root-owned queue (`"asked_at": record.get("asked_at") or int(time.time())`)
— `validate_grant` (`:64-91`) checks `kid`, `kind`, `what` and `minutes`, and nothing else.
`cmd_list_open` prints it at `:249`. Bash evaluates a variable named inside `$(( ))` as an
arithmetic *expression*, and an array subscript there performs command substitution.

**Failure scenario.** A kid writes into `$XDG_RUNTIME_DIR/omarchy-kids/ask-outbox/x.json`:

```text
{"kid":"kid-ada","kind":"time","what":"10","minutes":10,"state":"open",
 "asked_at":"x[$(cp /bin/bash /tmp/s; chmod u+s /tmp/s)]"}
```text

`collect` (root, every minute) validates and queues it. The parent opens the panel → Requests. The
payload runs **as the parent**, in a process that has just warmed `sudo -v`
(`bin/omarchy-kids-panel:95-104`) — so the kid gets the parent account and, through the cached
credential, root. Confirmed the mechanism directly: `v="a[\$(touch /tmp/PWNED)0]"; : $(( v ))`
creates the file.

**Fix.** Two lines. `lib/ask.py:285` — coerce: `int(record.get("asked_at") or time.time())` inside
a `try`, dropping the record on failure, the same way every other field is handled.
`lib/panel-requests.sh:59` — guard: `[[ "$asked_at" =~ ^[0-9]+$ ]] || asked_at=0`. Do both; the
panel must not trust the queue any more than the queue trusts the outbox.

### 2.5 `authd` traded a serialization bug for an unbounded thread spawn (medium)

`bin/omarchy-kids-authd:440-451` starts one `threading.Thread` per `accept()` with no cap, no
semaphore, and no per-peer connection limit, on a socket that is `0666`
(`systemd/omarchy-kids-authd.socket:7`). Each thread holds a 5 s timeout
(`CLIENT_TIMEOUT`, `:40`).

**Failure scenario.** A kid loops `socat - UNIX-CONNECT:/run/omarchy-kids/auth.sock` a few thousand
times without sending a line. Each spawns a root thread that lives 5 s. At a modest rate the
daemon's RSS and thread count climb until Python raises `RuntimeError: can't start new thread`;
`main`'s `while True` has no handler for it, `Restart=on-failure` bounces the unit, and the parent's
exit modal and the GRANT path are down for as long as the kid keeps looping — the S7 outcome by a
different route. The rate limiter does not help: it only fires after a password is read.

**Fix.** A `threading.Semaphore(16)` acquired before `Thread(...).start()` and released in
`handle_client`'s `finally`, plus a per-uid in-flight cap. Or drop threads and use
`Accept=yes` in the socket unit, letting systemd's `MaxConnections`/`MaxConnectionsPerSource` do it.

### 2.6 The pidfile fix landed in `lib/kids.sh` and `omarchy-kids-time` did not adopt it (high)

`bin/omarchy-kids-time:105-108`:

```text
overlay_running() { pgrep -f "quickshell -p $1" >/dev/null 2>&1; }
```text

used at `:112` (`show_toast`), `:119` (`show_timesup`) and `:131-132` (`dismiss_timesup`, a
`pkill -f` on the same string). This is round one §1.9's bug, in the file that enforces bedtime,
while `lib/kids.sh:141-153` sits two `source` lines away with the correct pidfile check.

**Failure scenario.** A kid with a terminal (bands 9-12 and 13+ — `share/packs/13+.toml` ships one)
runs
`bash -c 'exec -a "quickshell -p /usr/share/omarchy-kids/time/timesup.qml" sleep 99999' &`.
`overlay_running` now returns 0 forever, `show_timesup` returns at `:119` without drawing anything,
and lights-out never appears. No toast either, by the same trick on `toast.qml`.

**Fix.** Give `omarchy-kids-time` the same `$RUN/timesup.pid` treatment `exit` and `ask` already
have, via `modal_already_open`/`modal_write_pid`; kill by that pid, not by `pkill -f`.

### 2.7 `pipefail` + `head -1` in the band-defaults reader (low, latent)

`bin/omarchy-kids-provision:110` and its verbatim twin `bin/omarchy-kids-wizard:111`:

```text
printf '%s\n' "$out" | sed -n "s/^${key}=//p" | head -1
```text

Both files run `set -euo pipefail`. `head -1` exits after one line; if `sed` has not finished it
takes SIGPIPE and the pipeline returns 141. `band_field` is called as a bare assignment
(`lib/provision-add.sh:48`, `:63`) — under `set -e` that aborts `provision add` mid-way, after
`useradd`/`chpasswd` in the worst ordering. It does not fire today only because the band dump is
short enough that `sed` always finishes first. `bin/omarchy-kids-web:77` and
`bin/omarchy-kids-time-ledger:53` have the same shape.

**Fix.** `sed -n "0,/^${key}=/s///p"`, or `awk -F= -v k="$key" '$1==k{print substr($0,length(k)+2); exit}'`
— no second process, no SIGPIPE. And put it in `lib/kids.sh` once, not twice.

### 2.8 Strict mode was added and then switched off exactly where the writes are

#49's own note in `docs/style.md` §2 records the three `set +e` regions. In practice:
`bin/omarchy-kids-panel:259` turns `-e` off before `screen_home` and never turns it back on until
`:262`, after the entire screen tree has run — every write in the panel happens with `-e`
disabled. Same at `bin/omarchy-kids-wizard:448-478`, wrapping the whole 15-step dispatch including
`screen_apply`. `bin/omarchy-kids-tui-demo` likewise. The 0/1/130 contract is real and needs
handling, but the fix is `if screen_home; then rc=0; else rc=$?; fi` — the shape
`bin/omarchy-kids-session:254` already uses correctly — not a global disable. As written, the
`set -euo pipefail` line at `panel:6` and `wizard:6` is decoration on those two files.

### 2.9 `assert` writes to `/etc` by default, and `AGENTS.md` still says it doesn't

`bin/omarchy-kids-assert:27` is `DRY_RUN=0` and `:46-48` says so. `AGENTS.md` rule 8 still reads:
*"`DRY_RUN=1` is the default for every non-interactive command — `provision`, `assert`, `web`,
`apps`, `remove`"*. `pacman/omarchy-kids.hook:12,17` runs `omarchy-kids-assert --quiet` after
*every* pacman transaction on *any* target. So on any machine with the package installed —
including a dev box — an unrelated `pacman -Syu` writes `/etc/pam.d/sddm`, `/etc/fstab`,
`/etc/polkit-1/rules.d/`, `/boot/limine.conf` and runs `mount --bind`. That may well be the right
behaviour for a self-healing lock, but the rule the repo has committed to says otherwise, and the
rule is what a reviewer reads first. Pick one.

### 2.10 `lib/assert-limine.sh:22` can report FAIL on a file it fixed correctly

```text
{ printf 'editor_enabled: no\n'; grep -vE '^editor_enabled:' "$f"; } > "$tmp" || { rm -f "$tmp"; return 1; }
```text

A `limine.conf` whose only line is `editor_enabled: yes` makes `grep -v` exit 1 with no output; the
group's status is grep's, so the (correct) temp file is deleted and the lock reports `FAIL
limine-editor` on every run. Append `|| true` to the `grep`.

---

## 3. What a kid's session can still influence

1. **`OMARCHY_KIDS_LIB` → arbitrary shell inside the PAM verifier.** §2.1. This is the single
   worst thing in the tree.
2. **`asked_at` → command execution in the parent's panel.** §2.4. Reaches root through the panel's
   warmed sudo.
3. **The kid's own runtime `launches.log` is `tail`ed by root into a 0644 file.**
   `lib/data.sh:126` `[[ -r "$src" ]]` follows symlinks; `:138`
   `tail -c "+$((off + 1))" "$src" >>"$dest"`; `:137` creates `$dest` mode 0644. *Scenario:* the kid
   replaces `$XDG_RUNTIME_DIR/omarchy-kids/launches.log` with a symlink to `/etc/shadow`. The next
   `omarchy-kids-time-ledger tick` (root, every minute, `bin/omarchy-kids-time-ledger:131`) copies
   the parent's password hash into `/var/lib/omarchy-kids/<kid>/launches.log`, which the kid can
   read. Offline cracking then defeats the whole product. **Fix:** open the source with
   `O_NOFOLLOW` (in shell: refuse when `[[ -L "$src" ]]`), and `stat` it to confirm it is a regular
   file owned by that kid's uid, before reading a byte.
4. **`OMARCHY_KIDS_LEVEL` and `OMARCHY_KIDS_BAND` decide the desktop.**
   `bin/omarchy-kids-session-start:69-70` prefer the environment over the root-owned profile.
   *Scenario:* a 13+ kid on Level 1 runs `OMARCHY_KIDS_LEVEL=2 omarchy-kids-session-start` from
   their terminal; line 284 execs `/usr/bin/omarchy-launch-shell`, giving them Omarchy's full shell
   and launcher inside the session. **Fix:** these two are outputs of the profile, not inputs —
   read them from `conf` unconditionally and keep the env override behind `OMARCHY_KIDS_ROOT`-style
   test gating, or drop it.
5. **`OMARCHY_PATH` decides which Lua the root-owned level config loads.**
   `share/hyprland/L1.lua:50` — `package.path = (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/?.lua;" .. package.path`,
   under a comment (`:48-49`) claiming it searches Omarchy's path *only*. `bin/omarchy-kids-session`
   exports four `OMARCHY_KIDS_*` variables before `exec` (`:270-273`) and does not export
   `OMARCHY_PATH`. Anything that seeds the session environment (a future uwsm/systemd-user path,
   `environment.d`) makes `require("default.hypr.helpers")` load kid-authored Lua at compositor
   config-parse time — arbitrary keybinds, i.e. the whole Level 1 fence. **Fix:** one line —
   export a fixed `OMARCHY_PATH` in `omarchy-kids-session` alongside the other four, and replace
   `.. package.path` with a fixed path list in `L1/L2/L3.lua`.
6. **Four environment variables switch off a root check in a shipped binary.**
   `OMARCHY_KIDS_TIME_LEDGER_REQUIRE_ROOT` (`time-ledger:106`),
   `OMARCHY_KIDS_DATA_REQUIRE_ROOT` (`data:21,59,347`),
   `OMARCHY_KIDS_EXIT_REQUIRE_ROOT` (`exit:125`),
   `OMARCHY_KIDS_TIME_REQUIRE_ROOT` (`time:80`). Today each is backstopped by filesystem
   permissions, so none is an escalation on its own — but the *check* they gate is now decorative,
   and a future writer who assumes the check held will be wrong. 77 distinct `OMARCHY_KIDS_*`
   variables are honoured across `bin/`, `lib/` and `share/`.
7. **`require_root_or_self` believes an environment variable.** `bin/omarchy-kids-data:63`
   `me="${OMARCHY_KIDS_ACCOUNT:-$(id -un)}"`. *Scenario:* kid A runs
   `OMARCHY_KIDS_ACCOUNT=kid-bo omarchy-kids-data sites kid-bo` and passes the authorization check;
   whether they get kid B's browsing history then depends only on `HOME_MODE`. `cmd_launches`
   (`:87`) has no check at all, and `/var/lib/omarchy-kids/<kid>/launches.log` is 0644
   (`lib/data.sh:137`) — every kid can read every sibling's app history today. **Fix:** authorize on
   `id -u`, never on `$OMARCHY_KIDS_ACCOUNT`; make the launches log 0640 root:omarchy-parents like
   `status.json` already is (`time-ledger:100-101`).
8. **`omarchy-kids-web launch`'s fail-closed check is pointed by the caller.**
   `bin/omarchy-kids-web:15` `SYSROOT="${OMARCHY_KIDS_ROOT:-}"`, `:284` checks
   `"$SYSROOT/etc/chromium/policies/managed/omarchy-kids-$band.json"`, and `:14` `SHARE` supplies
   the flag list at `:298`. A kid sets `OMARCHY_KIDS_ROOT=$HOME/fake`, creates the file, and R-WEB-4
   passes on a machine where the real policy is absent. (Managed policy still applies from the real
   `/etc` path, so this is a broken *check*, not a broken *fence* — but the check is what the
   session and the tile both rely on.)
9. **`omarchy-kids-wifi portal` is a kid-facing control that cannot work and does not clean up.**
   `bin/omarchy-kids-wifi:203-208`: `run "$WEB_BIN" install "$band" --allow … --apply` writes
   `/etc/chromium/policies/managed/` (root-only), and `run systemd-run --on-active=10min` needs
   `org.freedesktop.systemd1.manage-units`, which `lib/posture.sh:95` denies to every kid outright.
   So for the kid it fails; and in the one context where it *would* work (root), a `systemd-run`
   that fails leaves `neverssl.com` allowed for the whole band permanently, for every sibling in
   it. `:219` then runs `chromium --new-window` — bare name, Arch's wrapper, and no R-WEB-4 check
   at all, bypassing the fence `cmd_launch:284` and `session-start:202-211` both enforce.
10. **`wifid`'s "no extra flag can be smuggled in" claim is not enforced.** The docstring
    (`bin/omarchy-kids-wifid:14-17`) promises a fixed argument list. `cmd_join:162-166` builds
    `["device","wifi","connect", ssid, "password", password, "name", name]` with no `--` separator
    and no leading-dash rejection on `ssid` (arbitrary, up to 4096 bytes from the socket) or
    `password`. Add `RE_SSID`-style validation and a `--` before the first user value.
11. **`cmd_join` activates the connection before locking DNS down.** `:166` connects, `:168-175`
    then sets `ipv4.ignore-auto-dns`/`ipv6.ignore-auto-dns` and `connection.zone kids` — a
    firewalld zone nothing in this repo creates, so that call fails on a stock box, `run_nmcli`
    raises, and the kid is left **connected with the network's DNS**, which is precisely what
    R-WIFI-2 exists to prevent. Fail closed: create the profile with `connection.autoconnect no`,
    apply every setting, then `connection up`; delete the profile on any failure.
12. **Screen-time enforcement is a process the kid owns.** `bin/omarchy-kids-session-start:302`
    starts `omarchy-kids-time daemon` as the kid; `show_timesup` (`:118-128`) starts a
    kid-owned Quickshell overlay whose own countdown calls `execDetached(["omarchy-kids-exit",
    "--finish"])` (`share/time/timesup.qml:99`). Nothing root-side ever ends a session at
    lights-out — `omarchy-kids-time-ledger` only counts. `pkill quickshell`, or never letting the
    daemon start, and bedtime does not exist. `README.md:39-41` lists this under "What works
    today". Either move termination to the root ledger (it already knows the session id) or say in
    the README that lights-out is advisory for bands with a terminal.
13. **The exit modal's parent password protects an action the kid can already take.** `Finish`
    (`share/exit-modal/shell.qml:193-195`) ends the kid's own session — reachable without any
    password via `loginctl terminate-session`, or by closing every window. The password gate there
    is real code doing nothing; the honest version is either no password on Finish, or Finish doing
    something the kid genuinely cannot (switching to the parent's session).

---

## 4. The ten highest-payoff simplifications left

1. **Delete the test seams from the shipped binaries.** 77 `OMARCHY_KIDS_*` variables, four of
   which turn off a root check, several of which redirect the path a security decision is made
   against. Upstream has none of this. One `OMARCHY_KIDS_ROOT` prefix for the test tree, applied in
   one place, and nothing else. Everything in §3 items 1, 4, 5, 6, 7, 8 falls out.
2. **One `lib/root.sh`, as `docs/style.md` §6 already prescribes and #49 skipped.** Four
   hand-rolled `[[ "$(id -u)" != "0" ]]` checks with four different env escapes and four different
   messages. Upstream's `install/helpers/as-root.sh` is seven lines.
3. **Finish the consolidation instead of arguing with it.** `bin/omarchy-kids-wizard:105-107` still
   carries a paragraph explaining why `band_field` is copied rather than shared — the same
   paragraph round one quoted. `VALID_BANDS` is declared six times; `is_valid_band` four;
   `validate_lights_out` twice, identically. Move them; delete the paragraphs.
4. **One dry-run vocabulary.** `--apply` on `provision`/`web`/`apps`/`plugins`/`ask`, `--dry-run` on
   `assert`, both on `panel`/`wizard`, `DRY_RUN=0` as a third spelling, and `AGENTS.md` rule 8
   describing a fourth arrangement that no longer matches `bin/omarchy-kids-assert:27`. Pick
   `--apply` for scripts and real-by-default for the two interactive commands, and rewrite rule 8
   to match the code.
5. **`omarchy-kids-check` should not exist as a separate program.** It `source`s
   `bin/omarchy-kids-assert` (`:74`) to reuse its `*_ok` functions, inheriting that file's
   `DRY_RUN`, `usage()` and globals. `assert --dry-run` already prints exactly the same verdict.
   Ten `lib/check-*.sh` files, 199 lines of dispatcher and a second status vocabulary
   (`pass/warn/fail/skip` vs `ok/fixed/would-fix/FAIL`) exist to re-render one report.
6. **The QML files never got the header pass the shell files did.** `share/sddm-theme/Main.qml`
   opens with 144 comment lines; `share/exit-modal/shell.qml` with a 52-line UNTESTED banner its
   own lines 68, 70 and 191 contradict. Two lines each, and the audit trail into `docs/portal.md`
   and `docs/exit.md`, which already exist.
7. **Delete `share/menu/omarchy-kids-trimmed.jsonc`, `polkit/`, `sudoers/` and
   `bin/omarchy-kids-tui-demo` from the package.** A guessed schema nothing reads, two empty
   directories `AGENTS.md` describes as holding templates, and a demo that `PKGBUILD:66`'s glob
   ships to every user's `/usr/bin`. Name the files in `PKGBUILD` instead of globbing them.
8. **The packs audit (#52) added a second source of truth.** Every `[[app]]` in
   `share/packs/*.toml` now carries `source = "extra"|"aur"`, and nothing reads it — the code still
   branches on the `aur:` prefix in `pkg` (`bin/omarchy-kids-apps:228-231`). Meanwhile 10 of the 41
   pack entries are `aur:` and `cmd_install` never installs any of them (`:230-231` prints
   "skipping AUR package(s), not yet automated") — five of the sixteen 13+ apps. Either wire up an
   AUR helper or drop those entries; a pack that half-installs is a launcher full of grey tiles.
9. **`mark_migrations_done` should not ship.** `bin/omarchy-kids-provision:173-192` writes a real
   file into a real home in a format its own comment calls "a documented guess … TODO(#10)".
   Round one said this; it is still there. Delete it and let `omarchy-provision-user` be a hard
   requirement, or confirm the format on the test laptop — the laptop exists.
10. **Fix `README.md:50-53`.** Two sentences still interleaved, in the first screen of the front
    page of the repository. It is the cheapest thing on this list and the first thing a maintainer
    sees.

---

## 5. Verdict

**No — a maintainer would not merge this as a plugin or companion to Omarchy today.** Not because
of the architecture, which is sound and in several places (the SO_PEERCRED GRANT path, the
posture writers' atomic renames, `lib/tui.sh`) better than what it replaced. Because a package
that installs a `pam_exec` line into the lock screen has to be beyond argument about its own trust
boundary, and this one currently `source`s shell from a variable the kid controls (§2.1), lets a
kid-written JSON field reach `$(( ))` in the parent's panel (§2.4), and hands a root process a
symlink to follow into `/etc/shadow` (§3.3). Round one's findings were addressed carefully and
with real tests; the refactor that followed opened three more of the same kind. That pattern —
each pass fixing the reported instances and re-creating the class — is what a maintainer would
refuse, not any single bug.

Three things that would change their mind:

1. **A trust boundary that is stated once and holds everywhere.** No `OMARCHY_KIDS_*` variable
   changes what code is loaded, what path a check reads, or whether a root check runs, in any
   binary that a kid's session can invoke — enforced by a test that walks `bin/` and fails on a new
   one. That single rule closes §2.1, §3.4, §3.5, §3.6, §3.7 and §3.8 together.
2. **The security tests run on the machine the maintainer runs.** Today the four skipped checks are
   the password verifier's live path and `wifid`'s SO_PEERCRED boundary — the two authorization
   decisions in the product. `test/all` is honest about it now, which is progress, but a reviewer
   cannot verify the claims from a green run. Run them in the QEMU VM in CI and put the output in
   `docs/live-tests.md`.
3. **Stop shipping controls that are not enforced (I-6, the repo's own rule).** A Pause button for
   a feature that exits 2; a captive-portal helper a kid's own polkit rules forbid; a lights-out
   overlay any kid with a terminal can `pkill`; a README listing that overlay under "What works
   today"; nine `UNTESTED` banners, one of which its own file disproves three lines later. Each of
   these individually is small. Together they are the reason a maintainer cannot tell which of the
   green lines in this repo they are allowed to believe.
