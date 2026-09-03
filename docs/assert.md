# Re-asserting locks: `omarchy-kids-assert`

SPEC.md I-4, R-TRUST-5, R-BOOT-5, R-WEB-1, R-FND-2..6, §5.1.

I-4 says every lock must be re-asserted after updates and verified at every kid login, and
R-TRUST-5 names the two callers: the pacman hook and Omarchy's own post-update hook.
`omarchy-kids-assert` is the one command both call — and the boot unit besides — to put back
anything a package upgrade, a stray edit, or a snapshot rollback silently dropped. It never
*creates* a kid or a machine-level feature that was never provisioned in the first place: for
every check below, "nothing provisioned" means "nothing to assert", not "provision it now". That
job belongs to `omarchy-kids-provision` (`docs/provision.md`), which is also where every writer
this command calls (`lib/posture.sh`) is documented in full; this file only covers what
`omarchy-kids-assert` checks, when, and what it does when a check fails.

## When it runs

| Caller | How | Flags |
| --- | --- | --- |
| `pacman/omarchy-kids.hook` | After *every* pacman transaction (install, upgrade, or remove of any package) | `--quiet` |
| `systemd/omarchy-kids-assert.service` | At boot, `Before=display-manager.service`, `After=local-fs.target` | `--quiet` |
| Omarchy's own post-update hook | `omarchy hook install post-update omarchy-kids-assert` (a line to add to that hook's config, not something this repo runs — see "Omarchy's post-update hook" below) | `--quiet` |
| A parent, from the panel or a terminal | Directly | none, or `--dry-run` to preview |
| `omarchy-kids-session`'s R-DESK-2 preflight | Does **not** call this command — it checks the same facts read-only, at login, and fails closed (full-screen "Ask a grown-up") rather than trying to fix anything mid-login | — |

### Omarchy's post-update hook

Upstream Omarchy ships a mechanism for third-party packages to run something after `omarchy
update` finishes, independent of pacman's own per-transaction hook. Wiring this repo's package
into it is one line, added to that hook's install step (not part of this issue's deliverable —
recorded here so packaging picks it up):

```sh
omarchy hook install post-update omarchy-kids-assert
```

This is a **note**, not something `omarchy-kids-assert` itself runs or depends on: the pacman
hook alone already satisfies R-TRUST-5 for every package transaction, `omarchy update` included.

## The lock list

One line per lock, `<status> <lock-id>`, status one of `ok` / `fixed` / `FAIL` (`would-fix`
under `--dry-run`, see below). Per-kid locks run once for every account under
`$OMARCHY_KIDS_ETC/kids/*.conf`; machine-level locks run once per invocation, after every kid.

### Per kid (`<account>` from the profile filename)

| Lock id | Checks | Fix |
| --- | --- | --- |
| `fstab:<account>` | The exact `/etc/fstab` bind line for this account's home (R-FND-2) | `lib/posture.sh`'s `posture_add_fstab_line` (already idempotent) |
| `mount:<account>` | The home is *actually* mounted `noexec,nosuid,nodev` right now, via `findmnt`, not just that `fstab` says it should be | `mount --bind` (only if not already a mountpoint) then `mount -o remount,bind,nosuid,nodev,noexec` |
| `namespace:<account>` | Both `/etc/security/namespace.conf` lines for `/tmp` and `/dev/shm` (R-FND-2a) | `posture_add_namespace_lines` |
| `accountsservice:<account>` | `/var/lib/AccountsService/users/<account>` matches exactly (R-LOGIN-3) | `posture_write_accountsservice` |
| `groups:<account>` | Member of `omarchy-kids` and the band group (`omarchy-kids-3-5`/`6-8`/`9-12`/`13plus`) | `usermod -aG` with only the groups actually missing |

### Machine-level (once per run, only while at least one kid is provisioned)

| Lock id | Checks | Fix |
| --- | --- | --- |
| `polkit-admin` | `/etc/polkit-1/rules.d/40-omarchy-kids.rules` names the parent from `machine.conf` (R-FND-3) | `posture_write_polkit_admin_rule` |
| `polkit-deny` | `/etc/polkit-1/rules.d/41-omarchy-kids-deny.rules` (R-FND-4) | `posture_write_polkit_deny_rule` |
| `sddm-theme` | `/etc/sddm.conf.d/zz-omarchy-kids-theme.conf` selects the portal (`[Theme] Current=omarchy-kids`, R-LOGIN, issue #14) | `posture_write_sddm_theme_dropin` |
| `pam:sddm`, `pam:systemd-user` | The `pam_namespace` marker + line in `/etc/pam.d/sddm` and `/etc/pam.d/systemd-user` (R-FND-2a) | `posture_ensure_pam_namespace`, seeding from `/usr/lib/pam.d` when needed |
| `getty:tty2` .. `getty:tty6` | Each unit is masked — a symlink to `/dev/null` at `/etc/systemd/system/getty@ttyN.service` (R-FND-5), read directly rather than shelled out to `systemctl` | `systemctl mask getty@ttyN.service` |
| `units` | The package's units are enabled: `omarchy-kids-boot-login`, its cleanup unit and `omarchy-kids-assert` in `multi-user.target.wants`, `omarchy-kids-authd.socket` in `sockets.target.wants` (R-BOOT-3, R-SEC-2); without the first the owner's stock autologin wins every boot | `systemctl enable` of the four |
| `hyprland-configs` | Every `*.lua` under `$OMARCHY_KIDS_SHARE/hyprland` is byte-identical to its copy under `/etc/omarchy-kids/hyprland` (R-DESK-1) | `omarchy-kids-session --install-configs` if that ever exists (it does not yet in this checkout — verified by grep before writing this), else copies the files directly |
| `chromium-policy:<band>` | *Only for policy files that already exist* — `/etc/chromium/policies/managed/omarchy-kids-<band>.json` is mode `0640` (R-WEB-1) | `chmod 0640`; group ownership (`root:omarchy-kids-<band>`) is attempted best-effort and never decides ok/fixed/FAIL (see "Judgment calls") |
| `boot-hook` | *Only if `/usr/lib/initcpio/hooks/omarchy-kids-unlock` is present* — the current UKI's initramfs contains the hook (R-BOOT-5), via `objcopy -O binary --only-section=.initrd <uki> img && lsinitcpio img \| grep omarchy-kids-unlock` | `mkinitcpio -P` |

## Exit codes

- **0** — every lock is (or now is) fine, or nothing is provisioned.
- **1** — at least one lock could not be fixed. One bad lock never stops the rest from being
  checked; the exit code just reflects that something still needs a human.

`--quiet` prints only `fixed`/`FAIL` lines (no `ok` lines, and no notice at all when nothing is
provisioned — the pacman hook and the boot unit both use this). Without `--quiet`, an all-clear
run still prints one `ok` line per lock, and a no-kids run prints one line explaining why it did
nothing. `--dry-run` reports what *would* change (`would-fix` instead of `fixed`) and writes
nothing at all.

## Judgment calls

- **`--dry-run` opts out of writing; there is no `--apply`.** Every other command in this repo
  defaults to `DRY_RUN=1` (AGENTS.md rule 8) and needs `--apply`/`DRY_RUN=0` to act for real. This
  command inverts that on purpose: it is the thing the pacman hook and the boot unit call with no
  flags but `--quiet`, and the entire point of R-TRUST-5 is that it self-heals without anyone
  passing a flag. Nothing about this changes AGENTS.md rule 8's actual protection — every real
  path below is still overridable by `OMARCHY_KIDS_ETC`/`OMARCHY_KIDS_SHARE`/`OMARCHY_KIDS_ROOT`/
  `OMARCHY_KIDS_HOME_ROOT`, and `test/shell.d/assert-test.sh` never sets any of them to the real
  filesystem, so this default-to-real-writes behavior only ever touches a scratch tree on this
  dev machine.
- **`group_for_band` is duplicated from `bin/omarchy-kids-provision`**, not sourced or moved into
  `lib/`. It is a stable, four-line, pure mapping (also documented in `docs/packaging.md`'s group
  list); `omarchy-kids-provision` is a script with its own `main "$@"`, not a library, so sourcing
  it to reuse the one function would run its whole CLI. Extracting it into `lib/` instead was
  considered and rejected as more churn than a fifth issue justifies for four lines; worth
  revisiting if a third command ever needs it too.
- **Group membership (`groups:<account>`) has no `lib/posture.sh` writer to reuse.**
  `omarchy-kids-provision` sets it once via `useradd -G` at account creation and never touches it
  again, so unlike every other per-kid lock here, this one is implemented directly in
  `bin/omarchy-kids-assert` rather than reusing an existing idempotent function, per the issue's
  own `usermod -aG` instruction.
- **Getty masking is checked as a symlink, not via `systemctl is-enabled`.** A masked unit *is* a
  symlink to `/dev/null` at the unit's path — that's the whole mechanism, and it's what
  `systemctl --root=DIR mask` itself does (a pure filesystem operation; `--root` never talks to a
  live systemd). Reading that symlink directly needs no `systemctl` at all and matches how every
  other lock here checks state (file content), reserving the stubbed `systemctl` call for the fix
  path only, same division `omarchy-kids-provision` already uses for masking.
- **Chromium policy files: mode only, ownership best-effort.** This mirrors
  `docs/provision.md`'s own stated reasoning for its writers: a real run is always root (the
  pacman hook, the boot unit, or a parent's polkit-elevated action), at which point `chown` always
  succeeds anyway; a `chown` failure in a non-root context (every test on this repo's dev machine,
  per AGENTS.md rule 8) is expected and silently ignored rather than turned into a `FAIL` that
  would make the test suite red on a laptop that was never supposed to run this as root in the
  first place. `chmod`, which *does* work as the file's own owner, is what ok/fixed/FAIL is based
  on.
- **The Chromium policy and hyprland-config locks never create files that don't already exist.**
  No writer for `/etc/chromium/policies/managed/omarchy-kids-<band>.json`'s *content* exists in
  this repo yet (confirmed by grep before writing this: `bin/omarchy-kids-session-start` reads
  the path, nothing writes it) — that is a separate issue's deliverable (R-WEB-2/R-WEB-3). This
  command only fixes the mode of a file that's already there, exactly as the issue's own wording
  says ("if they exist").
- **`OMARCHY_KIDS_UKI`** is a new env var, not in the issue's original list
  (`OMARCHY_KIDS_ETC`/`OMARCHY_KIDS_SHARE`/`OMARCHY_KIDS_ROOT`), for the same reason
  `omarchy-kids-provision`'s `OMARCHY_KIDS_HOME_ROOT` isn't in R-FND-2's either: `objcopy`/
  `lsinitcpio` need a real path to act on, even a scratch one, and no existing env var names a
  UKI file. Without it (and without a real `/boot/EFI/Linux/*.efi`, i.e. on this dev machine),
  the first match under `$OMARCHY_KIDS_ROOT/boot/EFI/Linux/*.efi` is used instead; if neither
  exists there is nothing to check and `boot-hook` reports `ok` (fail-safe, matching I-9's stance
  elsewhere in this repo: absence of evidence is not treated as a broken lock).
- **`getty@ttyN.service` and the Chromium policy directory are also read under
  `OMARCHY_KIDS_ROOT`**, even though the issue's own env-var list only names `/etc/polkit-1`,
  `/etc/security`, `/etc/pam.d`, `/etc/fstab`, and `/var/lib/AccountsService` (`lib/posture.sh`'s
  header). Same reasoning as `OMARCHY_KIDS_HOME_ROOT` in `docs/provision.md`: these are more real
  machine paths this command has to act on from a non-root scratch tree, and `OMARCHY_KIDS_ROOT`
  is already the established "everything under `/etc` and `/var` this feature touches" prefix, so
  extending its reach here (rather than inventing yet another env var) keeps the surface small.
- **One line per file, not one line per feature, for `getty` and `chromium-policy`.** The issue's
  prose groups "getty@tty2..6 masked" as a single bullet and "the per-band Chromium policy files"
  as another, but reporting (and fixing) each unit/file as its own lock line makes the "delete
  each lock in turn, expect exactly that lock to report fixed" test meaningfully check that a
  broken `tty4` mask, say, doesn't get lost inside a coarser "getty" line, or reported as fixed
  when only `tty2` actually needed it.
