# Boot Mode

## Goal

Make boot behavior an explicit machine choice. `disk` keeps the current cold-boot path: each passworded kid gets a LUKS key slot, the initramfs records the unlocking slot, and that slot selects the first desktop. `portal` leaves the stock disk-unlock and SDDM autologin paths alone; kids enter only through the Kids Mode SDDM portal after the machine is up.

This choice must make Kids Mode safe to install and administer over SSH on an encrypted laptop when nobody is present to type a disk passphrase. A portal setup never adds a key slot, installs an active mkinitcpio drop-in, rebuilds a UKI, or edits Limine.

## Non-goals

- This does not change the SDDM portal, kid passwords in shadow, session pinning, or the rule that a no-password profile has no LUKS slot.
- This does not remove full-disk encryption, obtain a disk passphrase remotely, or make `disk` valid on an unencrypted root.
- This does not change the parent's stock SDDM autologin setting. Portal mode preserves it byte for byte.
- This does not make environment-selected paths, devices, accounts, or helpers part of the production interface.

## Design

### Authority and convergence

`/etc/omarchy-kids/machine.conf` is the sole authority. It contains exactly one `boot=disk` or `boot=portal` line alongside the existing machine keys. The file is a regular file owned by `root:root`, mode `0644`, and is replaced atomically. The setter fsyncs the replacement before rename and the containing directory afterward, and reports whether rename committed even if durability or readback then fails. A shared installed reader rejects a symlink, wrong owner, group/world write permission, duplicate `boot` keys, a missing key after migration, or any other value.

Every root path resolves that reader and its transition helper from its own installed location. The path to `machine.conf`, the LUKS device, the slots map, mkinitcpio, the UKI, Limine, and boot-login files cannot come from an environment variable. Tests rewrite build-time constants in a copied command tree. The pacman hook delegates the read to `omarchy-kids-assert`; it has no separate mode detector.

Mode changes serialize on a root-created lock under `/run/omarchy-kids/`. A successful command means the selected mode has converged, not merely that `machine.conf` changed. Repeating the current value repairs its owned artifacts or reports a failure.

### Disk mode

Disk mode requires a LUKS root and the supported `encrypt` mkinitcpio path. A passworded kid has one active LUKS slot and one validated mapping in `/etc/omarchy-kids/luks-slots`; a no-password kid has neither. Provision add and remove add or kill that kid's slot. Secrets travel on stdin or already-open file descriptors, never argv, disk, environment, or logs.

The package ships the initcpio hook and the `omarchy_kids.conf` template under `/usr`, but only the disk transition installs the template at `/etc/mkinitcpio.conf.d/omarchy_kids.conf`. It then runs one `mkinitcpio -P`, verifies that the current UKI contains `omarchy-kids-unlock`, and refreshes the existing Limine integration where present. Assert may repair these disk-mode artifacts and the current Limine locks.

At boot, a valid recorded slot and mapping create the temporary Kids Mode SDDM autologin drop-in. A kid slot selects `omarchy-kids.desktop`; the recorded parent slot selects the stock Omarchy session. A present but invalid or unmapped slot fails closed to the portal. If `/run/omarchy-kids/boot-slot` does not exist, boot-login writes nothing and preserves the stock SDDM autologin configuration. Cleanup removes only a drop-in that boot-login created on that boot.

### Portal mode

Portal mode has no kid LUKS slots or slot map, no `/etc/mkinitcpio.conf.d/omarchy_kids.conf`, and no Kids Mode hook in the current UKI after a completed transition. Provision add and remove never invoke `cryptsetup`, even when the root is encrypted. Disk-only CLI options are rejected instead of silently ignored.

Assert still restores session locks, policies, PAM, the portal theme, and other non-boot state. It does not inspect or rebuild the UKI, call mkinitcpio, call a Limine command, or read or write a Limine file. The ordinary all-package pacman hook therefore cannot mutate the UKI or Limine in portal mode.

Boot-login and its cleanup command read `boot=portal`, make no filesystem change, and return success so display-manager startup follows the stock path. They do not create an empty `User=` override. Kids reach their session only by choosing their tile in the SDDM portal. The parent's existing stock autologin may still start the parent session first.

### Wizard choice and authentication

Step 2 remains the only parent-password prompt. Package installation enables and starts the authd socket before the first wizard run. The wizard verifies the candidate through the same `omarchy-kids-parent-auth` to `omarchy-kids-authd` path used by PAM; it never treats `sudo -v` as proof of identity. Bootstrap verification is bound to the caller's kernel peer uid, requires that account to be an eligible non-root `wheel` parent, and fails closed if the verifier cannot check it. An unavailable verifier stops at step 2 with a repair instruction. Passwordless sudo cannot turn a wrong candidate into success.

After PAM succeeds, the wizard uses the same in-memory candidate to establish privilege non-interactively and keeps that authorization alive for the run. Later privileged calls never allow sudo to read from the terminal. If authorization expires or cannot be established, Apply stops and returns to step 2; no second password prompt appears. The candidate is cleared on exit and never logged or stored.

The wizard detects the initial default after step 2. It selects `disk` only when the root is LUKS, the installed hook shape is supported, and the verified candidate also unlocks that LUKS device in test-passphrase mode. Otherwise it selects `portal`. Advanced always shows a `Boot` row with `disk` and `portal`; portal is always selectable. Disk is accepted only when those preconditions pass, so the wizard never asks for a second disk secret. If existing passworded kids need slots, Advanced collects each kid's current password before the summary. Apply remains noninteractive. The summary names the chosen startup behavior before Apply.

Apply writes `parent=` and converges `boot=` before it provisions the first kid. In disk mode it passes the already-held parent candidate and kid password to provisioning. In portal mode it passes no disk secret or device option. The conf command remains the route for later mode changes.

### Mode transitions

`portal` to `disk` validates the LUKS root and all required secrets before changing boot artifacts. It securely prompts for the current disk passphrase and, in deterministic account order, each existing passworded kid's current password. Before adding a slot it atomically writes one root-only recovery record containing the prior map state and every planned addition. Portal authority rolls those additions back; disk authority verifies the committed slots and map before deleting the same record. It adds and verifies every missing kid slot, writes the slot map, installs the mkinitcpio drop-in, rebuilds once, verifies the UKI, updates Limine where present, and writes `boot=disk` last. A failure keeps `boot=portal`, rolls back slots added by that attempt, and does not report success.

Limine's saved prior value records ownership, not completion. Disk convergence writes its completion marker only after `limine-snapper-sync` succeeds. A power cut or failed synchronization therefore leaves completion absent, and the next disk convergence synchronizes again before it can succeed.

`disk` to `portal` first requires an inspectable current UKI, then writes `boot=portal` so concurrent assert and boot-login become no-ops for disk behavior. It kills every recorded kid slot, removes the slot map, restores only Kids Mode-owned Limine state, and copies the known-good UKI before removing the mkinitcpio drop-in. It runs exactly one `mkinitcpio -P` and verifies that the hook is absent from the rebuilt UKI. A failed or unverifiable rebuild restores the saved image. Failure returns nonzero and leaves portal as the authoritative safe mode; rerunning the same command resumes convergence.

Per-kid removal in disk mode kills only that kid's slot and does not rebuild the UKI. Per-kid removal in portal mode requires the portal invariants and never touches LUKS. Full Remove Kids Mode reads the mode before changing anything: disk mode removes all disk artifacts with one final rebuild; portal mode removes no LUKS, UKI, or Limine state. An invalid or missing mode blocks provision, assert, and removal before mutation. Boot-login is the early-boot exception: it makes no change and exits 0.

### Requirements

- R-BOOTMODE-1: A trusted `boot=disk|portal` key in root-owned `machine.conf` is the only boot-mode authority, and every root consumer reads it without an environment override.
- R-BOOTMODE-2: The wizard defaults to disk only after LUKS, hook-shape, and passphrase checks succeed; otherwise it defaults to portal, and Advanced exposes the validated override.
- R-BOOTMODE-3: Disk mode maintains one LUKS slot per passworded kid, the slot map, initramfs hook, verified UKI, Limine integration, and slot-selected first login.
- R-BOOTMODE-4: Portal mode adds no LUKS slot, installs or honors no mkinitcpio drop-in, and routes kid login only through the SDDM portal while preserving stock parent autologin.
- R-BOOTMODE-5: A missing boot-slot file causes boot-login to write nothing, so it cannot override stock SDDM with an empty `User=` line.
- R-BOOTMODE-6: In portal mode assert, including invocation by an ordinary pacman transaction, never rebuilds a UKI or reads, writes, or invokes Limine.
- R-BOOTMODE-7: Wizard parent authentication uses PAM/authd and rejects a wrong candidate even when sudo is passwordless.
- R-BOOTMODE-8: Step 2 is the only parent-password prompt; Apply and every later wizard operation either use its established noninteractive authorization or fail without prompting.
- R-BOOTMODE-9: Switching portal to disk converges the disk path for every existing passworded kid and rolls back additions on failure.
- R-BOOTMODE-10: Switching disk to portal removes all kid slots and the active hook, restores Kids Mode-owned Limine state, and rebuilds the UKI exactly once.
- R-BOOTMODE-11: Provision add/remove, assert, boot-login, full removal, and the pacman-hook path branch only on the trusted setting and preserve mode-specific invariants.
- R-BOOTMODE-12: Invalid or incomplete configuration never guesses a mode, never blocks early boot, and never reports a partially completed transition as success.

## Interfaces

The public commands are:

- `omarchy-kids-conf machine get boot` prints exactly `disk` or `portal` plus a newline.
- `sudo omarchy-kids-conf machine set boot disk` converges disk mode. On an existing portal installation it reads hidden transition secrets from the controlling terminal, never argv.
- `sudo omarchy-kids-conf machine set boot disk --secrets-stdin` is the noninteractive form used by the wizard. Stdin contains the current disk passphrase, then one password for each existing passworded kid in byte-sorted account order, one line each, and EOF. Missing or extra lines fail before mutation.
- `sudo omarchy-kids-conf machine set boot portal` converges portal mode. It asks for no disk passphrase.

`machine get boot` exits `0` on a valid value and `1` with no stdout for missing, unsafe, or invalid state. `machine set` exits `0` only after readback and mode checks pass, `1` for authorization, prerequisite, secret, or transition failure, `2` for bad syntax or a value outside `disk|portal`, and `130` when an interactive secret prompt is cancelled. Noninteractive callers that would require an unprovided secret fail with `1`; they never open `/dev/tty` unexpectedly.

`machine.conf` adds one key:

| Key | Type | Values | Required | Default |
| --- | --- | --- | --- | --- |
| `boot` | enum | `disk`, `portal` | yes after migration | wizard detection or legacy migration |

No persistent JSON file is added. `omarchy-kids-check --json` keeps its existing top-level keys: `generated_at`, `verdict`, `exit_code`, and `sections`. Its Boot section always includes `boot:mode`. Disk mode then reports `boot:unlock-hook`, `boot:luks-slots`, `boot:limine-editor`, and `boot:snapshot-entries`. Portal mode instead reports `boot:no-kid-luks-slots`, `boot:no-mkinitcpio-dropin`, and `boot:stock-autologin`; it does not inspect Limine or require a hook in the UKI. Each check keeps the existing `{ "id", "status", "detail" }` shape.

Assert keeps exit `0` for converged state and `1` when a lock or mode invariant cannot be repaired. Boot-login and cleanup return `0` for a portal no-op or a missing boot-slot no-op, `1` for an unsafe/malformed disk-mode input they cannot handle, and `2` for bad CLI syntax. The systemd boot-login unit must not prevent `display-manager.service` from starting on any nonzero result.

## Migration

The package stops owning `/etc/mkinitcpio.conf.d/omarchy_kids.conf` unconditionally and installs the template under `/usr/share/omarchy-kids/boot/`. The disk transition owns the `/etc` copy. This must land before portal-aware consumers so a package upgrade cannot recreate the drop-in behind their backs.

On upgrade, a one-time root migration writes `boot=disk` only when `machine.conf` already names a parent, at least one kid profile exists, the root is LUKS, and the existing Kids Mode mkinitcpio drop-in shows that the installation was using today's disk path. It writes `boot=portal` for an unconfigured install, an unencrypted root, or an installation without that disk evidence. It never infers from an environment value.

A legacy installation selected as disk keeps its slots and current boot behavior, then assert validates it. One selected as portal runs the portal convergence path before the new pacman hook can report success. Migration does not claim success until `machine get boot`, the mode-specific check set, and file ownership pass. A missing or ambiguous legacy state fails closed with instructions to run one of the two explicit `machine set boot` commands; boot-login still leaves the stock path untouched.

Switching later is supported in both directions and is idempotent. Portal to disk collects fresh secrets because Kids Mode does not store passwords. Disk to portal removes the slots before declaring convergence and performs one UKI rebuild regardless of kid count. Removing one kid after either migration follows the selected mode, not the presence of stale files.

## Tests

Unit tests run through `test/all` and use copied trees and stubbed fixed binaries. Each reviewer finding has its own regression:

- `test/shell.d/boot-login-test.sh` covers R-BOOTMODE-5: with stock autologin present and no `boot-slot`, boot-login creates no Kids Mode drop-in and changes no stock byte. It also covers mapped and unmapped disk slots plus a portal no-op.
- `test/shell.d/assert-test.sh` covers R-BOOTMODE-6: portal assert, both direct and through the exact pacman-hook argv, records zero calls to mkinitcpio, UKI tools, Limine tools, and Limine paths while still repairing a non-boot lock.
- `test/shell.d/wizard-test.sh` covers R-BOOTMODE-7: a wrong candidate fails when the sudo stub is passwordless, while the PAM/authd result alone decides success.
- `test/shell.d/wizard-test.sh` also covers R-BOOTMODE-8 in a pseudo-terminal: authd accepts step 2, Apply completes with one parent-password prompt in the transcript, no sudo prompt, and no password in output or the setup log.

`test/shell.d/conf-test.sh` covers ownership, mode, atomic writes, duplicate and invalid values, exact stdout and exit codes, non-root writes, idempotence, and missing-mode behavior. `test/shell.d/boot-mode-test.sh` covers both transitions, secret order, rollback, one rebuild, UKI verification, existing kids, no-password kids, stale artifacts, and interruption recovery. Provision, remove, check, packaging, and trust-boundary tests prove every named consumer uses the shared fixed-path reader and the package does not own the active drop-in.

The disk VM scenario extends `test/live/10-cold-boot-kid.sh`. On a fresh LUKS VM it selects disk, provisions `kid-ada`, verifies the slot and UKI, cold-boots with the kid password into the kid desktop, cold-boots with the parent disk passphrase into the stock parent session, and captures the selected desktop. This proves the disk prompt, recorded slot, mapping, session selection, and fail-safe stock fallback as one chain.

The portal VM scenario extends `test/live/30-portal-login-and-finish.sh`. It records hashes and mtimes for the UKI, Limine files, and stock SDDM autologin, selects portal over SSH, provisions `kid-ada`, runs assert, performs an unrelated pacman transaction, and proves all recorded boot files stayed unchanged and no kid slot exists. After a normal boot unlock, it logs the kid in from the portal and captures the desktop. This proves safe remote administration, pacman-hook isolation, stock autologin preservation, and portal-only kid entry.

Each mode scenario finishes by switching to the other mode and back. Disk to portal must show all kid slots absent and one rebuild. Portal to disk must show slots for every existing passworded kid and a working cold boot. VM snapshots restore the fixture between destructive cases; these commands never run on the development Mac or the Air's real disk.

## Tickets

Ordered so the portal-mode consumers land before the transition machinery: the Air installs in portal mode after tickets 1-5.

1. **Add the trusted machine boot setting**
   - Files: `lib/boot-mode.sh`, `bin/omarchy-kids-conf`, `test/shell.d/conf-test.sh`, `test/shell.d/trust-boundary-test.sh`, `PKGBUILD`, `omarchy-kids.install`, `test/shell.d/packaging-test.sh`
   - Acceptance: `machine get/set boot` enforce the exact enum, ownership, atomicity, exit codes, and fixed-path trust boundary without yet changing a boot artifact; the package stops owning `/etc/mkinitcpio.conf.d/omarchy_kids.conf` and ships the template under `/usr/share/omarchy-kids/boot/` instead (Migration).
   - Satisfies: R-BOOTMODE-1, R-BOOTMODE-12
2. **Gate assert and the pacman path**
   - Files: `bin/omarchy-kids-assert`, `lib/assert-locks.sh`, `lib/assert-limine.sh`, `pacman/omarchy-kids.hook`, `test/shell.d/assert-test.sh`
   - Acceptance: Disk retains boot repair, portal repairs non-boot locks with zero UKI or Limine access, and the exact pacman-hook invocation has the same result.
   - Satisfies: R-BOOTMODE-6, R-BOOTMODE-11, R-BOOTMODE-12
3. **Preserve stock login and report mode-specific safety**
   - Files: `bin/omarchy-kids-boot-login`, `systemd/omarchy-kids-boot-login.service`, `systemd/omarchy-kids-boot-login-cleanup.service`, `lib/check-boot.sh`, `test/shell.d/boot-login-test.sh`, `test/shell.d/check-test.sh`
   - Acceptance: Portal and missing-slot runs write nothing, mapped disk slots select the right session, malformed mappings fail safe without blocking SDDM, and check JSON exposes only the selected mode's checks.
   - Satisfies: R-BOOTMODE-4, R-BOOTMODE-5, R-BOOTMODE-11, R-BOOTMODE-12
4. **Make provisioning and removal mode-aware**
   - Files: `bin/omarchy-kids-provision`, `lib/provision-add.sh`, `lib/provision-remove.sh`, `bin/omarchy-kids-remove`, `test/shell.d/provision-test.sh`, `test/shell.d/remove-test.sh`
   - Acceptance: Disk per-kid and full removal handle the exact slots and one final rebuild; portal add/remove makes zero LUKS, UKI, or Limine calls and rejects disk-only options; invalid mode mutates nothing.
   - Satisfies: R-BOOTMODE-3, R-BOOTMODE-4, R-BOOTMODE-11
5. **Make parent authentication independent of sudo**
   - Files: `bin/omarchy-kids-authd`, `bin/omarchy-kids-parent-auth`, `bin/omarchy-kids-wizard`, `lib/wizard-apply.sh`, `omarchy-kids.install`, `test/shell.d/wizard-test.sh`, `test/shell.d/authd-test.sh`
   - Acceptance: PAM/authd rejects a wrong candidate under passwordless sudo, step 2 establishes noninteractive privilege, and a pseudo-terminal Apply shows no later password prompt.
   - Satisfies: R-BOOTMODE-7, R-BOOTMODE-8
   - Root cause found on the VM (2026-09-04): `lib/wizard-apply.sh` pipes each step through `sudo tee -a /var/log/omarchy-kids/setup.log` before the first step has established the ticket, so that `sudo` prompts on the terminal (`[sudo] password for kid-vm:`) while `sudo -S -v` runs beside it in the same pipeline. Establish authorization and open the log once, before any pipeline.
6. **Add wizard detection and the Advanced boot row**
   - Files: `bin/omarchy-kids-wizard`, `lib/wizard-screens.sh`, `lib/wizard-advanced.sh`, `lib/wizard-apply.sh`, `test/shell.d/wizard-test.sh`
   - Acceptance: Detection chooses disk only with all prerequisites, Advanced can choose either valid mode, the summary explains it, and Apply converges mode before adding the first kid without another disk-secret prompt.
   - Satisfies: R-BOOTMODE-2, R-BOOTMODE-8
7. **Build idempotent mode transitions and package the inactive template**
   - Files: `lib/boot-mode-transition.sh`, `bin/omarchy-kids-conf`, `test/shell.d/boot-mode-test.sh`
   - Acceptance: Both directions converge existing profiles, portal to disk rolls back failed additions, disk to portal rebuilds exactly once.
   - Satisfies: R-BOOTMODE-3, R-BOOTMODE-4, R-BOOTMODE-9, R-BOOTMODE-10
8. **Prove both modes in the VM**
   - Files: `test/live/10-cold-boot-kid.sh`, `test/live/30-portal-login-and-finish.sh`, `docs/install.md`
   - Acceptance: The disk scenario proves cold-boot selection and both transitions, the portal scenario proves SSH-safe zero boot mutation through pacman, and install documentation states both paths without overstating live proof.
   - Satisfies: R-BOOTMODE-3, R-BOOTMODE-4, R-BOOTMODE-6, R-BOOTMODE-10, R-BOOTMODE-11
