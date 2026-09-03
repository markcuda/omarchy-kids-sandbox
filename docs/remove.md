# Remove Kids Mode: `omarchy-kids-remove`

SPEC.md R-TRUST-1, R-TRUST-4, R-FND-6, section 5.2's Remove flow.

`omarchy-kids-remove` is the parent's undo button: it reverses every lock this package ever wrote,
removes every kid account and its LUKS slot, but never touches a kid's own files. It is also
reachable as `omarchy-kids remove-kids-mode` (`bin/omarchy-kids`'s one piece of subcommand
dispatch ahead of the panel this will eventually live behind — issue #8's follow-ons). It does
**not** uninstall the package itself: the last thing it does is print the `pacman -R` command that
does, never run it (docs/packaging.md already documents that `pacman -R` alone leaves every group
and account in place — Remove Kids Mode is the separate, explicit step that actually reverses
things, run first).

## What it does, in order

1. **Offers a Snapper snapshot**, if `snapper` is on `PATH`: `snapper -c root create -d "before
   Remove Kids Mode"` (R-TRUST-1). Skippable with `--no-snapshot`; silently does nothing if
   `snapper` isn't installed.
2. **For every kid** (every `$OMARCHY_KIDS_ETC/kids/<account>.conf`), in this order:
   1. Unmounts the home's noexec bind mount (`umount`), and best-effort stops whatever transient
      systemd mount unit fstab's own generator may have made for it (`systemd-escape --path
      --suffix=mount` then `systemctl stop`, both skipped quietly if `systemd-escape` isn't
      available or there's no such unit) — this has to happen *before* the fstab line goes, and
      before the home can be moved.
   2. Removes the `/etc/fstab` bind line (`lib/posture.sh`'s `posture_remove_fstab_line`).
   3. Kills the account's LUKS key slot (looked up by *number* in `/etc/omarchy-kids/luks-slots`,
      same as `omarchy-kids-provision remove` — a kid's own password isn't available here) and
      rewrites `luks-slots` without that entry.
   4. Removes the account's `pam_namespace.conf` lines (`posture_remove_namespace_lines`).
   5. Removes the AccountsService pin (`posture_remove_accountsservice`).
   6. Removes the SDDM face-icon file (`posture_remove_face_icon`, issue #39 — distinct from the
      AccountsService `Icon=` line above; see that lock's own comment for why both exist).
   7. Removes the account: `userdel` (never `-r`) — or `userdel -r` under `--delete-homes`, which
      also takes the home with it in the same step (see "Homes" below).
   8. Removes the profile (`$OMARCHY_KIDS_ETC/kids/<account>.conf`).
   9. Keeps the home: moves it to `<parent home>/Kids Mode/<display name>/` (R-FND-6, the exact
      convention `omarchy-kids-provision remove` already uses for a single kid — see "Homes"
      below), unless `--delete-homes` already took it away in step 7.
3. **Machine level**, once per run regardless of how many kids there were:
   - Removes the polkit admin rule (`40-omarchy-kids.rules`) and the deny rule
     (`41-omarchy-kids-deny.rules`).
   - Unmasks `getty@tty2..6`.
   - Removes the SDDM portal theme drop-in (`posture_remove_sddm_theme_dropin`).
   - Rebuilds `theme.conf.user` (issue #39's `portal-conf` lock) from whatever's actually left
     under `$OMARCHY_KIDS_ETC/kids/` — by this point every kid's own profile is already gone, so a
     full run rewrites it down to just the parent, same "recompute the whole thing" shape
     `luks-slots` uses.
   - Removes the parent-unlock PAM line from both stacks — `sddm` and whatever
     `posture_parent_unlock_lock_stack` names (`omarchy-lock-password` on Omarchy 4.0.2) —
     (`posture_remove_parent_unlock_line`).
   - Removes every `/etc/chromium/policies/managed/omarchy-kids-*.json` this package wrote.
   - Restores `/etc/default/limine`: drops our `MAX_SNAPSHOT_ENTRIES=0` line and its
     `# omarchy-kids: was MAX_SNAPSHOT_ENTRIES=<old>` marker, putting `<old>` back if there was
     one. `editor_enabled` is left exactly as it is — the parent chose that, Kids Mode never owned
     it, so there's nothing of ours to undo there (see "Judgment calls").
   - Removes `/etc/mkinitcpio.conf.d/omarchy_kids.conf` and runs `mkinitcpio -P` so the very next
     boot's image no longer carries the `omarchy-kids-unlock` hook.
   - Removes the per-boot SDDM autologin drop-in (`zz-omarchy-kids-autologin.conf`) if this boot
     happened to still have one around.
   - Disables and stops the package's units: `omarchy-kids-boot-login.service`, its cleanup unit,
     `omarchy-kids-assert.service`, `omarchy-kids-authd.socket`, `omarchy-kids-time.timer`
     (issue #23's screen-time ledger — not yet checked by `omarchy-kids-assert`'s own "units" lock
     as of this checkout, but this command tears down every unit the package ships regardless),
     `omarchy-kids-authd.service`, and `omarchy-kids-time-ledger.service`.
   - Deletes `/etc/omarchy-kids` and `/var/lib/omarchy-kids` — which is also what takes every
     kid's recorded screen-time state (`/var/lib/omarchy-kids/<account>/usage/`) with it — after
     first taring both into `/root/omarchy-kids-removed-<YYYYmmdd-HHMMSS>.tar.gz`, so a parent (or
     a future issue's "undo the undo") has one place to look if something in there mattered after
     all.
   - Prints the `pacman -R omarchy-kids` command. Never runs it.
4. **Idempotent**: every step above checks whether there's anything left to do before touching
   anything, and reports `skipped` if not — running the whole command again finds nothing left for
   every destructive step. The one deliberate exception is the snapshot offer itself (see
   "Judgment calls").

## The plan/confirm/dry-run contract

Every run prints **the plan first**: every step above, either `skipped` (nothing to undo) or
`would-remove`. Nothing is written during this pass, no matter which mode was requested.

- **`--dry-run`** stops right there. Exit 0, nothing changed.
- **Without `--yes`**, the plan is followed by a `Type "yes" to continue` prompt; anything else
  (including EOF) cancels with exit 1 and changes nothing.
- **With `--yes`**, or after typing `yes`, a second pass runs for real, reporting `removed` /
  `skipped` / `FAILED` per step, printed under a `Removing:` header. **One bad step never stops the
  rest** — the whole point of Remove Kids Mode is to get as much of the machine back to stock as it
  can, matching `omarchy-kids-assert`'s own "one bad lock never stops the rest" contract (exit code
  1 if anything reported `FAILED`, 0 otherwise).

This is the same `AGENTS.md` rule 8 exception `omarchy-kids-assert` already documents (see
`docs/assert.md`'s "Judgment calls"): a command whose whole reason to exist is a single, deliberate
real action shouldn't need `--apply` bolted on top of its own explicit confirmation step. Every
real path below is still fully overridable for tests.

## Homes

Every kid's own files are kept by default, exactly the way R-FND-6 and `omarchy-kids-provision
remove` already keep a single kid's home: `userdel` (no `-r`) leaves the home on disk, and it is
then moved to `<parent home>/Kids Mode/<display name>/` — a parent's own home is the one place
obviously theirs to browse, not a `/home` sibling next to accounts that no longer exist. The
`Kids Mode` folder itself is created `0700` and the moved-in copy is `chown -R`'d to the parent
(best-effort — see "Judgment calls"); the files inside are left exactly however the kid's own
account left them, since `mv` never touches file content or per-file ownership. `parent_home_dir`
(which account is `mark`? which directory is that account's home?) is duplicated from
`bin/omarchy-kids-provision`'s own function of the same name rather than shared — see "Judgment
calls".

`--delete-homes` instead runs `userdel -r <account>`, which removes the home as part of the same
step — the "home" step later in the sequence then finds nothing left (`home_present` is false) and
reports `skipped`, with no separate `rm -rf` or move needed.

## Left behind on purpose

- **The `omarchy-kids*` and `omarchy-parents` groups, and any group membership.** Nothing in this
  package ever deletes a group — not `omarchy-kids-provision remove`, not `pacman -R`
  (`docs/packaging.md`'s `post_remove` says so explicitly), and not this command either. A stray
  empty group is harmless; deleting one that some other tool might still reference is not a risk
  worth taking for a "Remove Kids Mode" button.
- **`editor_enabled` in `/boot/limine.conf`.** `omarchy-kids-assert`'s `limine-editor` lock sets it
  to `no` as a fence, but that's the parent's own boot-menu setting to keep or change — Remove Kids
  Mode only reverses what it *owns* (`MAX_SNAPSHOT_ENTRIES` in `/etc/default/limine`, a different
  file), never something a parent may have deliberately left off.
- **The `pam_namespace.so` session line and its marker in `/etc/pam.d/sddm` and
  `/etc/pam.d/systemd-user`** (`posture_ensure_pam_namespace`'s own machine-level enablement,
  distinct from the per-account lines in `namespace.conf`, which *are* removed per kid above). The
  task's own machine-level checklist names the polkit rules, the getty masks, the SDDM theme, and
  the parent-unlock line explicitly, but not this one. Left alone deliberately rather than guessed
  at: the line is inert once no account has a matching `namespace.conf` entry (pam_namespace simply
  has nothing to polyinstantiate), so leaving it costs nothing, and a future issue can add its
  removal once R-FND-2a's owner confirms it should be reversed too.
- **The boot hook's own binaries** (`/usr/lib/initcpio/hooks/omarchy-kids-unlock`,
  `/usr/lib/initcpio/omarchy-kids-open`) and every other package-installed file under `/usr` —
  those belong to `pacman -R omarchy-kids`, the step this command tells the parent to run next, not
  to this command itself (I-7-adjacent: this package doesn't reach into its own `/usr` files any
  more than it would another package's).

## Judgment calls

- **`chown -R` on the moved-in "Kids Mode" copy is best-effort**, same reasoning
  `docs/assert.md`'s Chromium-policy lock already documents: a real run is always root, at which
  point it always succeeds; a non-root context (every test on this repo's dev machine, AGENTS.md
  rule 8) is expected to fail it harmlessly. `install -d -m 0700`, which *does* work as the
  directory's own creator regardless of privilege, is what makes the folder itself non-browsable
  by anyone but the parent even when `chown` can't run for real.
- **`--parent-password-stdin` is optional, not required**, even though killing a LUKS slot is the
  single most security-relevant step here. `cryptsetup luksKillSlot --batch-mode` run as root does
  not need a passphrase at all — `omarchy-kids-provision remove` already relies on exactly that.
  When the flag *is* given, the password is passed through as `--key-file=<(...)`, which makes the
  deletion authenticated (cryptsetup verifies it unlocks the device before honoring the kill)
  instead of an unauthenticated root operation — strictly more evidence of a legitimate parent
  action, in the spirit of R-SEC-2's "every parent prompt uses the verifier", without inventing a
  requirement cryptsetup itself doesn't have and `omarchy-kids-provision remove` doesn't enforce
  either. Never on argv, matching every password in this repo.
- **The Snapper snapshot offer is the one non-idempotent step on purpose.** Every other step checks
  "is there anything left to undo" before acting; a snapshot has no such notion — running Remove
  Kids Mode twice on purpose (say, once that fails partway and once that finishes) legitimately
  might want a fresh "before" snapshot each time, and Snapper itself is the tool responsible for
  pruning old ones, not this command.
- **The "mount unit if any" step is best-effort and untested outside a VM.** No writer in this repo
  ever creates a persistent mount unit file for a kid's home — `/etc/fstab`'s own entry is enough
  for a real boot, and systemd may or may not have synthesized a transient
  `home-<account>.mount`-shaped unit for it depending on how it was mounted. `systemd-escape` isn't
  on this dev machine (or in the test's stub `PATH`, deliberately, since nothing here needs to
  exercise that branch to prove the rest of "mount:<account>" works), so this path is exercised for
  real only on the test laptop; see "What needs the VM to verify" on the PR body / commit for the
  reminder.
- **`group_for_band`-style duplication.** `luks_slots_parent_line`, `luks_slots_kid_entries`,
  `luks_slot_for_account`, `detect_luks_device` (minus its `--luks-device` flag, which `remove`
  commands never take), `parent_home_dir`, `portal_conf_entries`/`portal_conf_expected` (minus its
  `EXCLUDE` argument — nothing to exclude, since the account it would have named is already gone
  from `$KIDS_DIR` by the time this runs), and the `/etc/default/limine` restore logic are all
  duplicated from `bin/omarchy-kids-provision` / `bin/omarchy-kids-assert` rather than shared, for
  the same reason `docs/assert.md`'s "Judgment calls" already gives for `group_for_band`: both
  source files are scripts with their own `main "$@"`, not libraries, and each duplicated block is
  small, stable, and already documented in full at its original home.
- **`--dry-run` still runs every check function for real** (`findmnt`, `id`) even though it writes
  nothing — exactly how `omarchy-kids-assert`'s own check functions behave under `--dry-run`. Only
  the destructive fix side is ever skipped.

## Every path is overridable, for tests

| Env var | Default | Affects |
| --- | --- | --- |
| `OMARCHY_KIDS_ETC` | `/etc/omarchy-kids` | profiles, `luks-slots` |
| `OMARCHY_KIDS_LIB` | `lib/` beside `bin/`, else `/usr/lib/omarchy-kids` | where `lib/conf.sh`, `lib/posture.sh` are sourced from |
| `OMARCHY_KIDS_ROOT` | (none — the real paths) | every real machine path this touches: `lib/posture.sh`'s own list, plus `/etc/systemd/system` (getty masks, package units), `/etc/chromium/policies/managed`, `/etc/mkinitcpio.conf.d`, `/etc/default/limine`, and `/root` (the pre-delete tarball) |
| `OMARCHY_KIDS_HOME_ROOT` | (none — the real `/home`) | prefixes `/home/<account>` and `<parent>`'s own home for `umount`/`mv`/`rm` (`parent_home_dir` falls back to this prefix when `getent` isn't available) |
| `OMARCHY_KIDS_LUKS_DEVICE` | (none) | the LUKS device, since `remove` has no `--luks-device` flag (same as `omarchy-kids-provision remove`) |

`test/shell.d/remove-test.sh` builds a fully-provisioned scratch tree the same way
`test/shell.d/assert-test.sh` does (seeding every lock directly through `lib/posture.sh`'s own
writers, plus the same verbatim real `/etc/pam.d/sddm` and `/etc/pam.d/omarchy-lock-password`
fixtures), with a stub `PATH` (fake `userdel`, `cryptsetup`, `systemctl`, `mkinitcpio`, `snapper`,
`findmnt`, `umount`, `id`, and a `tar` *spy* that logs argv but still runs the real archiver, so the
test can confirm what actually landed in the pre-delete backup) — never touches the real `/etc`,
`/var`, or `/home` (`AGENTS.md` rule 8).

## What needs the VM to verify

- The "mount unit if any" best-effort `systemd-escape`/`systemctl stop` path (no such tool on the
  dev machine or in the test's stub `PATH` — see "Judgment calls").
- That `mkinitcpio -P` actually drops `omarchy-kids-unlock` from the rebuilt image (the test only
  confirms the command was invoked with `-P`, via `docs/boot.md`'s own verification recipe).
- That `systemctl disable --now` (a real, unprefixed run, `OMARCHY_KIDS_ROOT` empty) really stops
  the live units, not just removes their `.wants` symlinks — the test only exercises the `--root=`
  path, where `--now` is never passed (systemd refuses to combine the two).
- That a real Snapper is actually present and takes a real "before Remove Kids Mode" snapshot on
  a stock Omarchy install with Btrfs/Snapper configured the way the installer sets it up.
- That `chown -R` to the parent actually succeeds and produces a browsable
  `~/Kids Mode/<name>/` folder on a real (root) run — the test only confirms the call happens,
  never its real-filesystem effect (AGENTS.md rule 8: no test here runs as root).
- End to end: reboot after a real `omarchy-kids-remove --yes` run, confirm the portal is gone, the
  parent's own login is unaffected, and each kid's `~/Kids Mode/<name>/` folder still has their
  files — the acceptance-level check R-TRUST-4 and SPEC.md section 8 item 8 actually ask for.

## Source header (moved from `bin/omarchy-kids-remove`, issue #49)

Kept for reference; the file itself now carries a 3-line pointer instead.

```text
omarchy-kids-remove -- "Remove Kids Mode" (SPEC.md R-TRUST-1, R-TRUST-4,
R-FND-6, section 5.2's Remove flow): the parent's undo button. Reverses
every lock omarchy-kids-provision and the rest of the package ever wrote,
removes every kid account and its LUKS slot, but never a kid's files --
each kid's home is kept, moved to "<parent home>/Kids Mode/<name>/"
(R-FND-6, same convention `omarchy-kids-provision remove` already uses
for a single kid) unless --delete-homes, offers the pre-removal Snapper
snapshot, and ends by
printing (never running) the pacman command that actually uninstalls the
package. See docs/remove.md for the exact order, per-step reasoning, and
what is deliberately left behind.

Usage:
  omarchy-kids-remove [--yes] [--dry-run] [--delete-homes]
                       [--parent-password-stdin] [--no-snapshot]
  omarchy-kids-remove --help

Also reachable as `omarchy-kids remove-kids-mode` (see bin/omarchy-kids).

Always prints the plan first: every step, "skipped" (nothing to do) or
"would-remove". --dry-run stops right there and writes nothing. Without
--yes, a parent has to type "yes" before anything real happens. The real
pass then reports "removed"/"skipped"/"FAILED" per step -- one bad step
never stops the rest, matching omarchy-kids-assert's own contract: the
whole point of Remove Kids Mode is to get as much of the machine back to
stock as it can, not to stop at the first thing that goes wrong.
Idempotent: a second run finds nothing left to do and reports "skipped"
for everything (see docs/remove.md's "Judgment calls" for the one
deliberate exception -- the snapshot offer).

Every path is overridable for tests, the same convention every other
command in this repo uses:
  OMARCHY_KIDS_ETC          default /etc/omarchy-kids (profiles, luks-slots)
  OMARCHY_KIDS_LIB          default lib/ beside bin/, else /usr/lib/omarchy-kids
  OMARCHY_KIDS_ROOT         scratch prefix for every real machine path this
                            touches: lib/posture.sh's own list, plus
                            /etc/systemd/system (getty, package units),
                            /etc/chromium/policies/managed,
                            /etc/mkinitcpio.conf.d, /etc/default/limine,
                            and /root (the pre-delete tarball)
  OMARCHY_KIDS_HOME_ROOT    scratch prefix for /home/<account> itself
  OMARCHY_KIDS_LUKS_DEVICE  overrides LUKS auto-detection; remove has no
                            --luks-device flag, same as
                            omarchy-kids-provision remove
```
