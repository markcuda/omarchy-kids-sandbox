# Provisioning: `omarchy-kids-provision add` / `remove`

R-FND-2..6, R-SEC-3..5, R-LOGIN-3, R-DESK-1, Appendix B.

`omarchy-kids-provision` is the one command that turns "a display name and a band" into a real
Unix account a kid can log into, and the one command that turns it back into nothing. Everything
it writes is listed below, in the order it writes it. `lib/posture.sh` holds the actual writers
(polkit rules, pam_namespace lines, the fstab line, the AccountsService pin, the luks-slots
rewrite) as small, idempotent functions; `bin/omarchy-kids-provision` is the sequencing and the
policy (bands, passwords, LUKS).

`DRY_RUN=1` is the default everywhere (AGENTS.md rule 8): every action below is printed, not
run, unless `--apply` is passed or `DRY_RUN=0` is set. The few things that only *decide* what to
do — the slug collision check, LUKS device/slot detection, reading `luks-slots` and
`machine.conf` — always happen for real, dry run or not, since reading never changes anything.

## `add <display-name> --band <band> [--avatar ID] [--password-stdin | --no-password] [--parent-password-stdin | --parent-password-fd N] [--luks-device DEV]`

1. **Account name** (Appendix B.1): `omarchy-kids-conf slug "<display-name>"` gives the base
   `kid-<slug>`; if a profile already exists for it (`$OMARCHY_KIDS_ETC/kids/<slug>.conf`), or
   `getent passwd` already knows it, `-2`, `-3`, ... is appended until one is free.
2. **The account itself** (R-FND-2): `useradd -m -s /bin/bash -G omarchy-kids,<band-group>
   <account>`. Band groups: `omarchy-kids-3-5`, `omarchy-kids-6-8`, `omarchy-kids-9-12`,
   `omarchy-kids-13plus` (docs/packaging.md).
3. **Password** (R-SEC-3): with `--password-stdin`, the kid's password is the first line of
   stdin, piped straight into `chpasswd` as `<account>:<password>` — never on argv, never
   logged. With `--no-password` (3-5 only; refused for every other band, checking
   `password_optional` from `omarchy-kids-conf band <band>`), the account is locked instead
   (`usermod -L`).
4. **Display name** (R-LOGIN, issue #39): `usermod -c "<display-name>" <account>` sets the passwd
   GECOS field. SDDM's greeter reads its `realName` role from GECOS (`getpwnam(3)`'s
   `pw_gecos`), not from AccountsService, so this is a separate call from the AccountsService pin
   below, not folded into it. Re-asserted as the `gecos:<account>` lock (`docs/assert.md`).
5. **Home, bind-mounted `nosuid,nodev,noexec`** (R-FND-2): a line is appended to
   `/etc/fstab` — `/home/<account> /home/<account> none bind,nosuid,nodev,noexec 0 0` — and then
   `mount -o remount,bind,nosuid,nodev,noexec /home/<account>` applies it immediately, without
   waiting for the next boot.
6. **The profile** (Appendix B): `omarchy-kids-conf set <account> name|avatar|band|password|onboarded ...`
   writes `name`, `avatar`, `band`, `password` (`set` or `none`), `onboarded=no` to
   `$OMARCHY_KIDS_ETC/kids/<account>.conf`.
7. **Polkit** (R-FND-3, R-FND-4): `/etc/polkit-1/rules.d/40-omarchy-kids.rules` (admin identity
   `["unix-user:<parent>"]` for `omarchy-kids` members — the parent's name comes from `parent=`
   in `$OMARCHY_KIDS_ETC/machine.conf`, written by machine setup before any kid exists) and
   `/etc/polkit-1/rules.d/41-omarchy-kids-deny.rules` (outright `polkit.Result.NO`, no prompt, for
   NetworkManager settings-modify, udisks2 mount/unlock/loop-setup, systemd1 manage-units,
   packagekit, flatpak, and any `org.omarchy.*` action). Both are written once and are
   idempotent: a second kid's `add` compares content and leaves an unchanged file alone, so
   there's never a duplicate rule block.
8. **Text consoles masked** (R-FND-5): `systemctl mask getty@tty2.service` .. `tty6.service`.
   Also idempotent (masking an already-masked unit is a no-op).
9. **A private noexec tmpfs for `/tmp` and `/dev/shm`** (R-FND-2a, issue #10 finding c): two
   lines appended to `/etc/security/namespace.conf` —
   `/tmp /tmp/kids-inst/ tmpfs:mntopts=nosuid,nodev,noexec <account>` and the same shape for
   `/dev/shm` — plus, in `/etc/pam.d/sddm` and `/etc/pam.d/systemd-user`, a marker comment
   (`# omarchy-kids: pam_namespace for kid sessions (R-FND-2a)`) followed by
   `session required pam_namespace.so`, appended once per file and never duplicated (the marker
   is the idempotence check).
10. **The parent-unlock verifier line** (R-SEC-2, R-SEC-3; `docs/authd.md`), machine-level and
   idempotent: `lib/posture.sh`'s `posture_ensure_parent_unlock_line` inserts the
   `pam_exec.so … omarchy-kids-parent-auth` line (a fixed `[success=done default=ignore]`
   control — "done" ends the stack on a verified parent password before pam_unix is ever
   consulted with it; "ignore" on anything else falls through to the stack's normal chain, which
   reuses the already-typed token via `try_first_pass`) into `/etc/pam.d/sddm` and
   `/etc/pam.d/omarchy-lock-password` (`posture_parent_unlock_lock_stack` — the only lock-screen
   PAM service Omarchy 4.0.2 actually writes; there is no `hyprlock` service on that box). The
   line lands right after each stack's own leading `auth … pam_faillock.so … preauth` line if it
   has one, else right before its first non-comment `auth` line — confirmed against real
   `/etc/pam.d/sddm` and `/etc/pam.d/omarchy-lock-password` content, neither of which has a
   `pam_unix.so` line worth jumping around (`lib/posture.sh`'s own header comment has the full
   placement rule). A stack that doesn't exist yet on this box (the lock screen hasn't been
   configured) is a warning, not a reason to fail the whole `add` — see "Judgment calls" below.
11. **A LUKS key slot** (R-SEC-4), only when a password was given *and* an encrypted device is
   found (`--luks-device`, or auto-detected via `lsblk` for the first `crypto_LUKS` device — see
   "Known gap" below): the parent's own passphrase (needed to authorize the add; the second line
   of stdin with `--parent-password-stdin`, or an already-open fd with `--parent-password-fd`)
   unlocks the device long enough to add the kid's password as a new slot
   (`cryptsetup luksAddKey --key-file=<(parent password) DEVICE <(kid password)`); the new slot's
   *number* is then read back by testing the kid's password
   (`cryptsetup open --test-passphrase --verbose --key-file=<(kid password) DEVICE`, parsing its
   own `Key slot N unlocked.` line) — see "Why luks-slots is rewritten whole" below for why this
   step exists at all instead of just remembering the slot cryptsetup handed out.
12. **AccountsService** (R-LOGIN-3): `/var/lib/AccountsService/users/<account>` gets
    `Session=omarchy-kids`, `XSession=omarchy-kids`, `Icon=/usr/share/omarchy-kids/avatars/<avatar>.svg`
    so the tile has no session picker at all.
13. **The SDDM portal theme selection and its local-file-XHR drop-in** (R-LOGIN, issue #14,
    issue #39): `/etc/sddm.conf.d/zz-omarchy-kids-theme.conf` selects the portal
    (`docs/portal.md`), and `/etc/systemd/system/sddm.service.d/omarchy-kids-portal-xhr.conf`
    sets `Environment=QML_XHR_ALLOW_FILE_READ=1` on `sddm.service`, an attempt to let the
    greeter's QML read `portal.json` (next step) — **unverified** whether the greeter process
    actually inherits it; see `docs/portal.md`. Both are machine-level (R-FND-6): written once,
    left alone by `remove` until Remove Kids Mode takes the package out.
14. **portal.json** (R-LOGIN, issue #39): `/etc/omarchy-kids/portal.json` (root-owned 0644) is
    rebuilt in full from every kid profile under `$OMARCHY_KIDS_ETC/kids/*.conf` plus
    `machine.conf`'s `parent=` — `{"parent":"<owner>","kids":{"<account>":{"name":...,
    "avatar":...}}}` — so `Main.qml` can decide the parent tile and each kid's name/avatar from
    the profile registry, never from the `kid-` username prefix (`docs/portal.md`'s "Verified
    live" section: a VM whose owner account happened to be named `kid-vm` broke that heuristic).
15. **Omarchy's own per-user setup** (issue #10 finding b): if `omarchy-provision-user` exists on
    the target, it's run with the new account. If it doesn't, `mark_migrations_done` writes a
    best-effort stand-in — see "Known gap" below.

## `remove <account> [--keep-home]`

Reverses every account-level step `add` took, in reverse-ish order, then removes the account:

1. **LUKS slot** (R-SEC-4): looked up by *slot number* in `luks-slots` (a kid's own password
   isn't available to `remove`, so `--test-passphrase` isn't an option here — this is the one
   place slot number, not password, is the key), killed with
   `cryptsetup luksKillSlot --batch-mode DEVICE SLOT` (device the same way `add` finds one, plus
   `OMARCHY_KIDS_LUKS_DEVICE` since `remove` has no `--luks-device` flag of its own), then
   `luks-slots` is rewritten without that entry.
2. `pam_namespace` lines for the account removed from `namespace.conf` (the `pam.d/sddm` and
   `pam.d/systemd-user` marker lines stay — they're not per-account).
3. The AccountsService file removed.
4. **portal.json rebuilt without this account** (R-LOGIN, issue #39): the same full-rewrite
   `posture_write_portal_json` `add` uses, excluding the account being removed — never an
   in-place edit, for the same reason `luks-slots` is a full rewrite (see below).
5. The home unmounted (`umount /home/<account>`) and its `fstab` line dropped.
6. The profile file (`$OMARCHY_KIDS_ETC/kids/<account>.conf`) removed.
7. `userdel <account>` (no `-r`: the home is left on disk on purpose, for the next step).
8. Unless `--keep-home`, the home moves to `<parent home>/Kids Mode/<display name>/` — the
   parent's login name comes from `machine.conf`'s `parent=`, and their home directory from
   `getent passwd` (falling back to `/home/<parent>` where `getent` isn't available, e.g. this
   repo's macOS dev environment).

**Left alone, on purpose** (R-FND-6: machine-level, only removed by Remove Kids Mode): the
`omarchy-kids*` groups, the console masks, both polkit rule files, the SDDM theme selection and
its XHR drop-in (`lib/posture.sh` has `posture_remove_sddm_theme_dropin` and
`posture_remove_sddm_xhr_dropin` for Remove Kids Mode to call later), and the parent-unlock PAM
lines on `sddm` and the lock-screen stack (`lib/posture.sh` has `posture_remove_parent_unlock_line`
for Remove Kids Mode to call later; `remove` itself doesn't, since a parent should still be able
to unlock the lock screen and SDDM even after the *last* kid is removed).

## Why `luks-slots` is rewritten whole, not appended to (issue #10 finding a)

LUKS2 hands out a *freed* slot number to the next `luksAddKey`, not necessarily the next unused
one. If `remove` frees slot 3 and a later `add` gets slot 3 back for a different kid, an
append-only `luks-slots` would end up with two `3=...` lines — one stale, one current — and
whichever the boot-time reader (`docs/boot.md`) happens to read last decides who lands on whose
desktop. So every slot change — add or remove — rewrites the *entire* file from the current,
known-correct set of mappings: `posture_write_luks_slots` (`lib/posture.sh`) always takes the
verbatim parent `0=...` line plus the full list of surviving kid entries and writes that, and
nothing else, replacing the file outright. `add`/`remove` build that list by reading the
existing file (everyone else's mapping, already correct) and only changing the one line for the
account being added or removed — never assuming a slot number that wasn't just confirmed by
`cryptsetup` itself.

## Every path is overridable, for tests and for review before trusting a dry run

| Env var | Default | Affects |
| --- | --- | --- |
| `OMARCHY_KIDS_ETC` | `/etc/omarchy-kids` | profiles, `machine.conf`, `luks-slots` |
| `OMARCHY_KIDS_SHARE` | `/usr/share/omarchy-kids` | `omarchy-kids-conf`'s bands/packs (passed through) |
| `OMARCHY_KIDS_LIB` | `lib/` beside `bin/`, else `/usr/lib/omarchy-kids` | where `lib/conf.sh`, `lib/posture.sh` are sourced from |
| `OMARCHY_KIDS_ROOT` | (none — the real paths) | prefixes every path `lib/posture.sh` writes: `/etc/polkit-1`, `/etc/security`, `/etc/pam.d`, `/etc/fstab`, `/var/lib/AccountsService`; also passed to `systemctl --root=` for the console masks |
| `OMARCHY_KIDS_HOME_ROOT` | (none — the real `/home`) | prefixes `/home/<account>` for every `mount`/`umount`/`mv` this command itself runs (**not** in the spec's original env list — added here; see "Judgment calls" below) |
| `OMARCHY_KIDS_LUKS_DEVICE` | (none) | `remove`'s LUKS device, since it has no `--luks-device` flag |
| `OMARCHY_MIGRATIONS_DIR` | `/usr/share/omarchy/migrations` | source list for `mark_migrations_done`'s guessed markers |

`test/shell.d/provision-test.sh` runs entirely against a scratch tree built from these, with a
stub `PATH` (fake `useradd`, `usermod`, `userdel`, `chpasswd`, `mount`, `umount`, `systemctl`,
`cryptsetup`, `omarchy-provision-user`) that only logs its own argv — see that file's `stub()`
helper.

## Known gap: the exact "migration done" marker (issue #10 finding b)

`omarchy-provision-user` is called when it exists on the target, which is the right thing and
needs no guessing. When it doesn't (an older Omarchy, or a dev box), `mark_migrations_done`
(`bin/omarchy-kids-provision`) writes one line per file under `OMARCHY_MIGRATIONS_DIR` into
`~/.local/state/omarchy/migrations.log`, timestamped. This repo has no access to a real Omarchy
install to confirm that this is the marker format (or location) Omarchy's own migration runner
actually reads before it decides how many migrations are "pending" — it is a documented best
effort, not a verified fact, marked `TODO(#10)` at the definition. Before this ships: run it
against a real Omarchy 4.0.x install with `omarchy-provision-user` temporarily hidden from
`PATH`, confirm the kid's fresh desktop does *not* show "Pending Omarchy Migrations", and fix the
format here if it does.

## Judgment calls made in this implementation

- **A missing lock-screen PAM stack only warns, never fails `add`** (issue #15, R-SEC-2).
  `sddm` should always exist on a real Omarchy box, but `omarchy-lock-password` might not yet —
  the lock screen may simply not be configured at the moment a kid is provisioned. Aborting the
  whole account creation over that would be worse than provisioning the account and letting
  `omarchy-kids-assert` (which re-asserts every lock idempotently, `docs/assert.md`) pick the
  lock back up automatically once that stack exists.
- **The real-world content of `/etc/pam.d/sddm` and `/etc/pam.d/omarchy-lock-password` is now
  confirmed** against an actual Omarchy 4.0.2 box (there is no `/etc/pam.d/hyprlock` there at
  all — an earlier version of this guessed one as a fallback; wrong, and removed). Neither real
  file has a `pam_unix.so` line worth anchoring on (sddm has none of its own; the lock-password
  stack's is three lines past the real anchor point), which is why
  `posture_ensure_parent_unlock_line`'s placement rule is anchor-based on the stack's first
  non-comment `auth` line, and its control is a fixed `[success=done default=ignore]` rather than
  a jump number computed off `pam_unix.so`'s own control (an earlier version did the latter; it
  matched neither real file). `lib/posture.sh`'s own header comment has the full rule and the
  reasoning; every fixture in `test/shell.d/parent-unlock-test.sh`,
  `test/shell.d/provision-test.sh`, and `test/shell.d/assert-test.sh` is now the verbatim real
  file content, not a guess.
- **`OMARCHY_KIDS_HOME_ROOT`** isn't in the issue's env-var list (`OMARCHY_KIDS_ETC`,
  `OMARCHY_KIDS_SHARE`, `OMARCHY_KIDS_LIB`, `OMARCHY_KIDS_ROOT`), but `mount`, `umount`, and the
  final `mv` to `Kids Mode/` all need *some* real path to act on, even a scratch one, and
  `/home` wasn't in `OMARCHY_KIDS_ROOT`'s list either (`/etc/polkit-1`, `/etc/security`,
  `/etc/fstab`, `/var/lib/AccountsService`, `/etc/systemd`). Added it rather than either
  skip-testing those three commands or write into the real `/home` from a test. The **text**
  written into the `fstab` line itself is always the real `/home/<account>` path regardless of
  this variable — that's what a real machine's `mount` needs to read at boot; only the
  *commands this script itself runs* honor the scratch prefix.
- **Default `--avatar`**: the issue's signature marks `--avatar ID` optional but names no
  default and no avatar SVGs are shipped yet (`share/avatars/` is empty but for `.gitkeep`).
  Defaulted to `fox`, matching the fixture avatar already used by `AGENTS.md` and
  `test/shell.d/conf-test.sh`'s `kid-ada`.
- **Password minimum enforcement**: not explicitly asked for in the issue's `add` signature, but
  R-SEC-3 sets it and `bands.toml` already carries `password_min`, so `add` reads it via
  `omarchy-kids-conf band <band>` and refuses a too-short `--password-stdin` password outright,
  rather than writing a weak key slot and finding out later.
- **`--parent-password-fd`**: added alongside `--parent-password-stdin` per the issue text ("...
  or from a file descriptor"), reading one line via `read -r pw <&"$FD"`. Not exercised by
  `test/shell.d/provision-test.sh` (which only drives the stdin form) since it needs a caller
  that pre-opens an fd — noted here rather than left silently unverified.
- **`umount` and `userdel` as additional stub commands**: the issue lists `useradd`, `usermod`,
  `cryptsetup`, `mount`, `systemctl`, `gpasswd`, `chpasswd`, `omarchy-provision-user` as the
  fakes to build; `remove` also needs to unmount a home and delete the account, so
  `test/shell.d/provision-test.sh` stubs `umount` and `userdel` too (`gpasswd` is stubbed but
  currently unused — nothing in `add`/`remove` touches group membership beyond `useradd -G` at
  creation time and `userdel` at removal).
- **LUKS device auto-detection (`lsblk`)** is implemented (first `crypto_LUKS` device it finds)
  but not exercised by the test suite, since `lsblk` doesn't exist on the macOS box this was
  built on and isn't one of the fakes the issue asked for; every test drives `--luks-device`
  (`add`) or `OMARCHY_KIDS_LUKS_DEVICE` (`remove`) explicitly instead.
- **Ownership bits** (`root:root`, `root:polkitd`, etc.) on the files this writes are left
  alone — only permission bits are set. Actually running this always requires root in
  production (`useradd`, `mount`, `cryptsetup` all do), at which point everything it creates is
  already root-owned by virtue of the process; setting an explicit `chown` would only add a
  privileged operation that fails outright in the scratch trees this had to be built and tested
  against on a non-root Mac (AGENTS.md rule 8).
