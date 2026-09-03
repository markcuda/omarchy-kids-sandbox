# Packaging (R-FND-1, R-BUILD-2, R-BUILD-4, R-TRUST-5)

`omarchy-kids` is one Arch package, built from this checkout by `PKGBUILD` in the repo root.
There is no upstream tarball: `source=()` is empty on purpose, and `package()` reads straight
from `$startdir` (the checkout itself). This means the package can only be built from a git
checkout, never from a bare PKGBUILD file.

## Building on the test laptop

Never build or install as root, and never run this on a development machine — only on the test
laptop or in a VM (see the test-machine rule in `AGENTS.md`).

```sh
# in the checkout, as the normal (non-root) user
makepkg -sf
```text

`-s` resolves and installs missing `depends`/`makedepends` with pacman (will prompt for sudo);
`-f` rebuilds even if a package of the same version already exists, which is the common case
while pkgver stays at `0.1.0` during early development.

Install the result:

```sh
sudo pacman -U omarchy-kids-0.1.0-1-x86_64.pkg.tar.zst
```text

pacman will run `omarchy-kids.install`'s `post_install` (or `post_upgrade` on a reinstall), which
creates the groups and reloads systemd unit files — see below.

## AUR readiness (issue #32, R-BUILD-2)

Nothing here is published. This is what's true about the checkout so a real publish, whenever
that's decided, has nothing left to figure out.

- **`.SRCINFO`** at the repo root is hand-written in `makepkg --printsrcinfo` format, since this
  dev checkout has no `makepkg` to generate it. **Regenerate it with
  `makepkg --printsrcinfo > .SRCINFO` on the test laptop before ever publishing to the AUR** — a
  hand-written file is a starting point, not a substitute for the real generator, and any
  `PKGBUILD` edit that lands after this one makes the checked-in copy stale until that's run
  again.
- **`pkgver` scheme.** `0.1.0` (semver-shaped), no `pkgver()` function: `source=()` is empty and
  `package()` reads straight from `$startdir`, so there is no upstream tarball or VCS ref for a
  `pkgver()` to derive a version from — the checkout itself is the source. Bump the middle number
  for a feature milestone landing, the last number for a fix-only change, and reset to `1.0.0`
  once SPEC.md §8's acceptance list is met. `pkgrel` resets to `1` on every `pkgver` bump and
  otherwise increments only for a packaging-only fix at the same `pkgver` (a missed `depends=`, a
  wrong file mode) — never for a code change, which always earns its own `pkgver`.
- **`depends`/`optdepends`** are reviewed against every external binary `bin/` actually shells out
  to, not against what SPEC.md names — see the comment beside each entry in `PKGBUILD` for the
  reasoning. `quickshell` was missing before this issue: `omarchy-kids-exit`, `-ask`, and
  `-session-start` all `exec quickshell -p ...` with no fallback, unlike `hyprctl`/`loginctl`
  elsewhere in `bin/`, which are genuinely best-effort and guarded with `command -v`. `snapper`
  and `limine-snapper-sync` moved to `optdepends`: both are guarded the same `command -v` way in
  `omarchy-kids-assert`/`-remove`, so a machine without Snapper still installs and runs, only
  without the pre-apply snapshot (R-TRUST-1) and the hidden-snapshot-entries lock (issue #38).
- **`CHANGELOG.md`** at the repo root is seeded from `git log`'s merge commits, one entry per
  merged issue branch, oldest first within each milestone-shaped group. It is not yet a "v0.1.0"
  release changelog — there has been no tagged release — so everything so far sits under
  `[Unreleased]`.

## What gets installed where

Mirrors SPEC.md §5.1, restricted to what package() actually lays down today (some of §5.1's
paths, like `/etc/omarchy-kids/kids/<account>.conf`, are written at runtime by commands that
don't exist yet, not by the package itself).

| Repo path | Installed to | Mode | Note |
| --- | --- | --- | --- |
| `bin/omarchy-kids-*` | `/usr/bin/` | 755 | Every command, present or stubbed (R-BUILD-4) |
| `initcpio/hooks/omarchy-kids-unlock` | `/usr/lib/initcpio/hooks/omarchy-kids-unlock` | 755 | mkinitcpio runtime hook (R-BOOT-1) |
| `initcpio/install/omarchy-kids-unlock` | `/usr/lib/initcpio/install/omarchy-kids-unlock` | 755 | mkinitcpio install hook |
| `initcpio/omarchy-kids-open` | `/usr/lib/initcpio/omarchy-kids-open` | 755 | Shared `cryptsetup open` helper |
| `etc/mkinitcpio.conf.d/omarchy_kids.conf` | `/etc/mkinitcpio.conf.d/omarchy_kids.conf` | 644 | Inserts the hook into `HOOKS` (R-BOOT-2); a pacman `backup=` file, so a local edit survives an upgrade as a `.pacnew` |
| `systemd/*.service`, `systemd/*.socket` | `/usr/lib/systemd/system/` | 644 | authd socket/service, boot-login + its cleanup unit, the boot-time re-assert unit (`docs/assert.md`) |
| `share/**` (minus `.gitkeep`) | `/usr/share/omarchy-kids/` | — | bands, packs, hyprland, tui, policy, avatars, menu, sddm-theme data |
| `pacman/omarchy-kids.hook` | `/usr/share/libalpm/hooks/omarchy-kids.hook` | 644 | Re-assert hook (see below) |
| `desktop/omarchy-kids.desktop` | `/usr/share/applications/omarchy-kids.desktop` | 644 | "Kids Mode" in the app drawer |
| `desktop/omarchy-kids-session.desktop` | `/usr/share/wayland-sessions/omarchy-kids.desktop` | 644 | The kid Wayland session, offered by SDDM |
| `LICENSE` | `/usr/share/licenses/omarchy-kids/LICENSE` | 644 | |

Not laid down by the package (written at runtime by commands not built yet, per §5.1):
`/etc/omarchy-kids/kids/<account>.conf`, `/etc/omarchy-kids/machine.conf`,
`/etc/omarchy-kids/luks-slots`, `/etc/chromium/policies/managed/omarchy-kids-<band>.json`,
`/etc/polkit-1/rules.d/4x-omarchy-kids*.rules`, `/etc/sddm.conf.d/zz-omarchy-kids-*.conf`,
`/run/omarchy-kids/`, `/var/lib/omarchy-kids/`.

### Groups

`omarchy-kids.install`'s `post_install`/`post_upgrade` create six groups with `groupadd -f`
(idempotent -- safe to run again on every upgrade):

- `omarchy-kids` -- every kid account
- `omarchy-kids-3-5`, `omarchy-kids-6-8`, `omarchy-kids-9-12`, `omarchy-kids-13plus` -- one per band
- `omarchy-parents` -- the machine's owner(s)

No account is added to any of these by the package itself; that is `omarchy-kids-provision`'s job
(not built yet). `post_install`/`post_upgrade` also run `systemctl daemon-reload` when systemd is
running, and print a one-line hint to run `omarchy-kids`.

`post_remove` deliberately leaves every group and every kid account in place -- removing the
package is not the same as Remove Kids Mode (R-TRUST-4), which is a separate, explicit action.

## The pacman hook

`/usr/share/libalpm/hooks/omarchy-kids.hook` fires `omarchy-kids-assert --quiet` after every
pacman transaction (install, upgrade, *or* remove of any package, not just this one) so that an
unrelated update -- a kernel bump, a config-file overwrite -- can never silently drop a lock
(R-TRUST-5, I-4). `omarchy-kids-assert` is the one place that re-applies every lock idempotently
-- polkit rules, pam_namespace, fstab/mount, group membership, the AccountsService pin, masked
getty units, the hyprland config copies, Chromium policy file modes, and the boot hook -- for
every provisioned kid and the machine as a whole; see `docs/assert.md` for the full list, when it
runs, and its exit codes.

## Removing

```sh
sudo pacman -R omarchy-kids
```text

This removes the files in the table above and prints `post_remove`'s notice. It does **not**:

- remove the `omarchy-kids*`/`omarchy-parents` groups
- remove any kid account, its home, or its LUKS slot
- touch `/etc/omarchy-kids/`, `/var/lib/omarchy-kids/`, or `/run/omarchy-kids/`

Reversing all of that is Remove Kids Mode (R-TRUST-4), run from the app before uninstalling the
package -- not a side effect of `pacman -R`.

## Known gaps (2026-09-02, first install in the VM)

- The package does not enable `omarchy-kids-boot-login.service` and its cleanup unit; today they
  are enabled by hand after install. They should be enabled by `omarchy-kids-provision add` when
  the first kid is created and re-checked by `omarchy-kids-assert`.
- Installing over files placed by `scripts/deploy-boot-hook.sh` conflicts, as pacman should;
  run the deploy script's `--remove` first on a machine that used it.
