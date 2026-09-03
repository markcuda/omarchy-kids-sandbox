# The portal: `share/sddm-theme/` (SPEC.md R-LOGIN-1..5, R-BOOT-3, R-SEC-3, I-5, I-7; issue #14, issue #39)

An SDDM greeter theme: one big tile per kid, a smaller parent tile last, arrow keys to move,
Enter to select, a password field that appears under the highlighted tile (or logs straight in
for a "no password" 3-5 profile), Esc to back out, no session picker. Replaces Omarchy's own
password-only greeter (`userModel.lastUser` plus a text field — confirmed against
`omacom/omarchy`'s shipped theme, see below) with one theme selection drop-in, never a hand-edit
of Omarchy's own files (I-7).

## What's here

| Path | What |
| --- | --- |
| `share/sddm-theme/metadata.desktop` | `[SddmGreeterTheme]`: `Name`, `MainScript=Main.qml`, `ConfigFile=theme.conf`, `QtVersion=6` |
| `share/sddm-theme/theme.conf` | `[General]` color/font keys, read back in `Main.qml` as `config.<key>` |
| `share/sddm-theme/Main.qml` | The greeter itself — see its own header comment for exactly which SDDM/Qt APIs each piece rests on and where that was confirmed |
| `share/avatars/*.svg` | Twelve hand-written, flat, single-color 128×128 animal avatars (fox, owl, panda, frog, whale, cat, bear, bee, koala, otter, penguin, tiger), CC0 (`share/avatars/LICENSE`) |
| `lib/posture.sh`: `posture_write_sddm_theme_dropin` / `posture_remove_sddm_theme_dropin` | Writes/removes `/etc/sddm.conf.d/zz-omarchy-kids-theme.conf` (`[Theme]` `Current=omarchy-kids`) |
| `lib/posture.sh`: `posture_write_sddm_xhr_dropin` / `posture_remove_sddm_xhr_dropin` | Writes/removes `/etc/systemd/system/sddm.service.d/omarchy-kids-portal-xhr.conf` (`Environment=QML_XHR_ALLOW_FILE_READ=1`), issue #39 |
| `lib/posture.sh`: `posture_write_portal_json` | Writes `/etc/omarchy-kids/portal.json` (root-owned 0644), issue #39 |
| `omarchy-kids-provision`: `usermod -c "<display name>"` | Sets the passwd GECOS field so the greeter's `realName` role shows the kid's name, issue #39 |

Installed by the package to `/usr/share/sddm/themes/omarchy-kids/` (PKGBUILD's `package()`) —
**not** under `/usr/share/omarchy-kids/`, even though `share/sddm-theme/` also gets swept into
that dir along with every other `share/**` subtree (docs/packaging.md); SDDM only looks for
greeter themes under `/usr/share/sddm/themes/<name>/`, so the theme needs its own, separate
`install`/`cp -a` line in `package()` to land where SDDM can actually find it.

## How the theme gets selected

Omarchy's own installer writes `/etc/sddm.conf.d/10-theme.conf` (`[Theme]` `Current=omarchy`).
`Current=` is SDDM's own documented key (`data/man/sddm.conf.rst.in` upstream): every file under
`/etc/sddm.conf.d/` is read in filename order, later files' keys winning. `posture_write_sddm_theme_dropin`
writes `/etc/sddm.conf.d/zz-omarchy-kids-theme.conf` — `Current=omarchy-kids` — which, sorting
after Omarchy's `10-`, wins without ever touching `10-theme.conf` itself (I-7). This is the exact
same "`zz-` prefix wins by sorting last" convention `docs/boot.md`'s
`zz-omarchy-kids-autologin.conf` already uses.

The writer is called once from `omarchy-kids-provision add` (`bin/omarchy-kids-provision`,
alongside the polkit rules) and re-asserted by `omarchy-kids-assert` as the `sddm-theme` lock
(machine-level, alongside `polkit-admin`/`polkit-deny` — see `docs/assert.md`). Like those polkit
rules, it is a **machine-level** lock: `omarchy-kids-provision remove` leaves it in place
(R-FND-6) since the portal is still the right greeter as long as any other kid remains
provisioned; only Remove Kids Mode (§5.2) takes it out, by removing the package (and with it
`/usr/share/sddm/themes/omarchy-kids/`) — `posture_remove_sddm_theme_dropin` exists for that step
even though nothing currently calls it (a `TODO` for whichever issue wires up Remove Kids Mode's
full teardown).

## Display names, parent detection, and avatars (issue #39)

V1's first live boot into the portal (docs/phase1/V1.md; this file's own "Verified live" section
below) found three things that only show up once real tiles actually render: tiles showed the
bare account suffix (`ada`, `cy`) instead of the profile's display name; the parent tile wasn't
distinguished when the machine's *owner* account happened to be named `kid-vm` (a VM test
fixture); and avatars never rendered, always falling back to the letter-circle.

**Display name.** SDDM's `UserModel` reads its `realName` role from the passwd GECOS field
(`getpwnam(3)`'s `pw_gecos`), not from AccountsService — so `omarchy-kids-provision add` now runs
`usermod -c "<display name>" <account>` (chfn's non-interactive equivalent: no PAM prompt, no
argv password beyond the name itself) right after the account is created. `Main.qml`'s
`displayNameFor()` prefers `realName` first, then falls back to `portal.json`'s own
`kids[account].name` (below), then the account name with `kid-` stripped and the first letter
capitalized. Re-asserted as the `gecos:<account>` lock (`docs/assert.md`).

**Parent detection.** `omarchy-kids-provision add`/`remove` write `/etc/omarchy-kids/portal.json`
(root-owned 0644, rebuilt in full every time from the current, known-correct set of kid profiles
plus `machine.conf`'s `parent=` — the same "never append, always rewrite" shape `luks-slots`
already uses, via `lib/posture.sh`'s `posture_write_portal_json`):

```json
{"parent":"mark","kids":{"kid-ada":{"name":"Ada Lovelace","avatar":"fox"}}}
```

`Main.qml` reads this file once at startup with a synchronous
`XMLHttpRequest("file:///etc/omarchy-kids/portal.json")` and decides `isParentAccount(name)` by an
exact match against `parent`, never by the `kid-` username prefix, when the read succeeds. **This
read is likely broken as shipped, not merely untested**: Qt 6's own QML documentation
(`doc.qt.io/qt-6/qml-qtqml-xmlhttprequest.html`, fetched 2026-09) states "By default, you cannot
use the `XMLHttpRequest` object to read files from your local file system," lifted only by the
process environment variable `QML_XHR_ALLOW_FILE_READ=1`. SDDM's own greeter source
(`sddm/sddm`'s `src/greeter/GreeterApp.cpp`, fetched 2026-09) never sets it — grepped for
`qputenv`/`setenv` there: only `QT_QPA_PLATFORM` is ever read, nothing XHR-related is ever set.
`lib/posture.sh`'s `posture_write_sddm_xhr_dropin` writes a systemd drop-in on `sddm.service`
(`/etc/systemd/system/sddm.service.d/omarchy-kids-portal-xhr.conf`, never a hand-edit of the
vendor unit — I-7) exporting that variable, on the **unverified** assumption that the greeter
process, spawned by `sddm.service`'s own PID, inherits it. If it doesn't, `Main.qml` catches the
read failure and falls back to the old `kid-` prefix heuristic — the same fail-safe shape every
other best-effort writer in this repo uses (I-9: absence of confirmation is not treated as
"broken," but it is also not treated as "working"). Both `portal.json` and the drop-in are
re-asserted (`portal-json` and `sddm-xhr` locks, `docs/assert.md`).

**Avatars.** `posture_write_accountsservice` already points AccountsService's `Icon=` at
`/usr/share/omarchy-kids/avatars/<avatar>.svg`; `Main.qml`'s `avatarSourceFor()` uses that role,
falling back to rebuilding the same path from `portal.json`'s `kids[account].avatar` if the
AccountsService role comes back empty (a kid provisioned before an avatar was assigned). What was
actually missing on the live VM was Qt's SVG image plugin, `qt6-svg` — now listed explicitly in
`PKGBUILD`'s `depends=` (unverified whether `sddm`/`qt6-declarative` already pull it in
transitively; there is no `pacman` on this dev machine to check with `pacman -Si sddm`'s own
dependency tree).

## Ground truth this was checked against (2026-09, no local SDDM/Qt install)

Everything below was fetched and read from source, not guessed, since this machine has no SDDM
or Qt to test against:

- `omacom/omarchy`'s own shipped theme (`default/sddm/omarchy/{metadata.desktop,theme.conf,Main.qml}`,
  `default/sddm/hyprland.lua`): password-only, `userModel.lastUser`, `sddm.login(user, password,
  sessionIndex)`, `QtVersion=6`, no `import SddmComponents` types actually used, and a greeter
  Hyprland config with no keybinds of its own (so nothing there should be catching our
  `Ctrl+Shift+P` first — not itself confirmed, see Main.qml's header).
- `sddm/sddm` upstream C++ (`src/greeter/UserModel.{h,cpp}`, `SessionModel.{h,cpp}`,
  `GreeterProxy.h`, `GreeterApp.cpp`, `src/common/{ThemeConfig,ThemeMetadata,Session}.cpp`,
  `data/man/sddm.conf.rst.in`): the exact role names on `userModel` (`name`, `realName`,
  `homeDir`, `icon`, `needsPassword`) and `sessionModel` (`directory`, `file`, `type`, `name`,
  `exec`, `comment`, plus `lastIndex`); that `file` is an *absolute path*, not a bare filename;
  that `config` is a `QQmlPropertyMap` of `theme.conf`'s `[General]` keys with no `General/`
  prefix (Qt's `QSettings` special-cases that one group name); `sddm.login`/`powerOff`/
  `canPowerOff` and the `loginFailed`/`loginSucceeded` signals; that `QQuickView` uses
  `SizeRootObjectToView` (so the root item is stretched full-screen regardless of the
  width/height it declares); and that `[Theme]` `Current=` is SDDM's own documented config key.

What none of that can confirm without a real engine: that this exact QML parses and renders,
that the avatar `Image`s actually rasterize the SVGs (needs Qt's SVG image plugin,
typically `qt6-svg` — not an explicit `depends=` here since SDDM/Qt normally pull it in already;
worth confirming in the VM), font availability, and real keyboard routing through the greeter's
Hyprland compositor. `share/sddm-theme/Main.qml`'s own header comment has the complete list.

## Deliberately not implemented here: R-LOGIN-5

> R-LOGIN-5 The parent password opens any kid's tile (R-SEC-2). No option to hide the parent
> tile in v1 (Q25).

`sddm.login(user, password, sessionIndex)` only ever authenticates `user`'s *own* password
through PAM — there is no QML-level way to say "also accept the parent's password for this
account." Making that true needs a PAM-level change: a `pam_exec` line ahead of `pam_unix` on kid
accounts' auth stack, calling the R-SEC-2 verifier (`omarchy-kids-authd` / a thin
`omarchy-kids-parent-auth` client, per SPEC.md's R-SEC-2) so a kid's login accepts *either* the
kid's own shadow hash or a parent-verified password. Grepped this checkout before writing this
file: no `authd`/`omarchy-kids-parent-auth` files exist yet, so there is nothing to wire this
theme into. This theme only ever submits whatever was typed for the tile's own account; R-LOGIN-5
is an open follow-up for whichever issue builds that PAM stack.

## How to test in the VM

Nothing here can be verified without a real SDDM/Qt engine. Once a VM is up (`docs/vm.md`) and at
least one kid is provisioned (`docs/provision.md`):

1. Build and copy the package over (never `pacman -U` from this dev checkout — build on the test
   machine, per AGENTS.md rule 8 and the PKGBUILD's own header):

   ```sh
   ssh vm 'cd ~/omarchy-kids-sandbox && git pull && makepkg -sf --noconfirm'
   ssh vm 'printf "omarchy\n" | sudo -S -p "" pacman -U --noconfirm ~/omarchy-kids-sandbox/omarchy-kids-*.pkg.tar.zst'
   ```

2. Provision at least two kids (one 3-5 band with `--no-password`, one older band with a
   password) plus confirm the parent account exists, so the portal has something interesting to
   show (a "no password" tile, a password tile, and the smaller parent tile last).
3. Confirm the drop-ins and portal.json landed and re-assert (issue #39 additions in bold):

   ```sh
   ssh vm 'cat /etc/sddm.conf.d/zz-omarchy-kids-theme.conf'
   ssh vm 'cat /etc/systemd/system/sddm.service.d/omarchy-kids-portal-xhr.conf'   # sddm-xhr
   ssh vm 'cat /etc/omarchy-kids/portal.json'                                     # portal-json
   ssh vm 'getent passwd kid-<slug> | cut -d: -f5'                                # gecos: should be the display name
   ssh vm 'printf "omarchy\n" | sudo -S -p "" omarchy-kids-assert'
   # expect "ok      sddm-theme", "ok      sddm-xhr", "ok      portal-json", "ok      gecos:<account>"
   # (or "fixed" the first time)
   ```

4. Restart SDDM from the SSH session (this kills the active graphical session on the console —
   expected, that's the point). If `sddm.service` was already active before step 3 wrote the new
   `omarchy-kids-portal-xhr.conf` drop-in, a plain `restart` may not be enough for systemd to
   notice a brand-new drop-in file under a unit it already has loaded — run `daemon-reload` first
   to be sure (harmless if it was already picked up):

   ```sh
   ssh vm 'printf "omarchy\n" | sudo -S -p "" systemctl daemon-reload'
   ssh vm 'printf "omarchy\n" | sudo -S -p "" systemctl restart sddm'
   ```

5. Screenshot the console over QMP from the Mac (`scripts/vm-qmp.sh`, `docs/vm.md`):

   ```sh
   VM_DIR=~/vm scripts/vm-qmp.sh shot portal.png
   ```

   Confirm visually: one tile per kid (avatar or fallback letter-circle, name below), the parent
   tile last and visibly smaller, no session-picker dropdown or list anywhere, a clock.
6. Keyboard-complete (I-5), driven via `scripts/vm-qmp.sh key <qcode>...` (no mouse):
   - Left/Right move the highlight between tiles.
   - Enter on the "no password" 3-5 tile logs straight in with no password field ever appearing.
   - Enter on a password-required tile shows a password field under that tile only.
   - Typing a wrong password and pressing Enter: the tile shakes, the field clears, no login.
   - Esc from the password field returns to plain tile navigation with the field gone.
   - The correct password logs in, and lands the account on the session AccountsService pinned
     it to (`omarchy-kids` for a kid, `omarchy` for the parent) — confirm with `loginctl
     show-session` or `who` after logging in, not by trusting this file's claim.
   - `Ctrl+Shift+P` powers the machine off (confirm on a VM you don't mind losing — or just
     confirm `sddm.canPowerOff` gates it and stop short of actually invoking it, by reading the
     journal for the greeter process instead of pressing it for real).
7. Confirm R-LOGIN-1's "last-used tile preselected": log in and back out (Ctrl+Alt+F-key or log
   out) as a kid other than the first-created one, restart sddm, screenshot again, confirm that
   kid's tile is the one highlighted on the fresh portal.
8. Confirm avatars: set a kid's `--avatar` to something other than the default and reprovision
   (or hand-edit the AccountsService `Icon=` line), restart sddm, screenshot, confirm that
   specific animal renders (not just the letter-circle fallback) — this is the one check that
   directly answers "does Qt's SVG plugin actually load these files," which nothing static in
   this repo can answer.

## What is untested / unverified, in one place

- The entire QML runtime behavior of `Main.qml` — parsing, rendering, focus routing through the
  greeter's own Hyprland compositor, the shake animation's timing/amplitude. See the file's own
  header comment for the full, itemized list and exactly what upstream source each other claim
  rests on.
- Whether `qt6-svg` (or equivalent) is actually present so the avatar SVGs rasterize, rather than
  always falling back to the letter-circle — `PKGBUILD` now depends on it explicitly (issue #39),
  which should settle this, but that dependency line itself is unverified against a real
  `pacman -Si sddm` dependency tree.
- Whether `JetBrainsMono Nerd Font` (theme.conf's default `fontFamily`) is available to the
  greeter's own fontconfig, separate from whatever's available inside a logged-in session.
- **Likely broken, not merely untested (issue #39):** whether `Main.qml`'s
  `XMLHttpRequest("file:///etc/omarchy-kids/portal.json")` read ever succeeds at all. Qt 6's own
  docs say local-file XHR reads are refused by default without `QML_XHR_ALLOW_FILE_READ=1` in the
  process environment; `posture_write_sddm_xhr_dropin`'s systemd drop-in on `sddm.service` is an
  attempt to set that, but whether the greeter process SDDM spawns actually inherits it is
  unconfirmed. If it doesn't, parent detection and the portal.json-derived name/avatar fallbacks
  silently degrade to their pre-#39 behavior — see "Display names, parent detection, and avatars"
  above.
- R-LOGIN-5 (parent password overrides a kid's own) — not implemented in this theme at all; see
  above. Needs a PAM-level change in a follow-up issue.
- `posture_remove_sddm_theme_dropin` and `posture_remove_sddm_xhr_dropin` — written, unit-tested
  directly (`test/shell.d/portal-test.sh`), but not yet called from anywhere (no Remove Kids Mode
  command exists in this checkout to call them from).
- Whether Ctrl+Shift+P actually reaches this QML given the greeter's compositor config, rather
  than being consumed earlier — Omarchy's own `default/sddm/hyprland.lua` has no binds of its own
  (confirmed by reading it), but the greeter's overall input routing wasn't otherwise checked.

## Verified live (2026-09-02, QEMU test VM)

A boot with a disk password whose LUKS slot maps to no kid recorded slot 4, the boot-login
unit wrote no autologin, and SDDM started the greeter with this theme (journal: `Loading theme
configuration from /usr/share/sddm/themes/omarchy-kids/theme.conf`, no QML warnings). One
face tile per account, clock, keyboard highlight. By keyboard only: Left moved the highlight
to Cy, Enter opened the password field under the tile, the kid password logged in and SDDM
started `omarchy-kids-session` for kid-cy, whose Hyprland and Level 1 launcher came up.
Not yet exercised live: the wrong-password shake, the power-off chord, the parent password on
a kid tile (needs #15), and the display-name and avatar polish in #39. `sddm-greeter-qt6
--test-mode` aborts inside a Hyprland session (stock theme too), so a real boot into the portal
is the only way to see the theme.

**Issue #39's fixes (display name, parent detection via portal.json, avatars) have not yet been
verified against this VM or any other real engine.** Step 8 of "How to test in the VM" above
covers the avatar check; confirming the display name shows instead of the bare account suffix,
and that the parent tile is correctly distinguished even when the machine owner's account starts
with `kid-`, both need a fresh boot after `pacman -U`ing a build that includes this issue's
changes. Confirming whether the `QML_XHR_ALLOW_FILE_READ` drop-in actually reaches the greeter
needs checking the greeter process's own environment on the VM (e.g. `cat
/proc/$(pgrep sddm-greeter)/environ`), not just that the drop-in file exists.
