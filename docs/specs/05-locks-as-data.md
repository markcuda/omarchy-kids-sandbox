# Locks as Data

## Goal

Declare every enforced lock once with its check, repair, removal, scope, and severity so assert, check, and uninstall cannot silently drift while the lock writers remain explicit and reviewable.

## Today

`lib/posture.sh:50-430` contains explicit writers and removers for polkit, namespaces, PAM, fstab, AccountsService, faces, SDDM, and portals. `lib/assert-locks.sh:8-321` wraps their checks and repairs. `bin/omarchy-kids-assert:120-200`, `lib/check-locks.sh:1-67`, and `bin/omarchy-kids-remove:103-124,450-497` enumerate overlapping sets independently. Adding a lock therefore requires coordinated edits in several distant lists.

## Interface

`lib/locks.sh` owns one package-code registry. Each entry declares a stable id, scope (`kid`, `band`, or `machine`), severity (`fail` or `warn`), check function, fix function, undo function, and argument provider. Registry order is stable and dependencies appear before consumers.

Internal `locks_run check`, `locks_run assert`, and `locks_run remove` traverse that registry. `check` never writes. `assert` runs check and, only when root and not dry-run, fix. `remove` calls the idempotent undo path; in dry-run it reports `would-remove` without requiring a separate presence list. Results are `ok`, `warn`, `would-fix`, `fixed`, `would-remove`, `removed`, or `fail` with a lock id.

The registry covers constraints that assert can re-establish: per-kid fstab, mount, namespace, AccountService, face, groups, theme, manifest, and browser policy; and machine polkit, SDDM, portal, PAM, parent unlock, gettys, services, parent group, Hyprland, Chromium, boot hook, and time infrastructure. Account deletion, home or LUKS destruction, archives, snapshots, and package removal remain explicit lifecycle steps outside the registry.

Only package code may declare entries. Argument providers enumerate accounts from root-owned profiles, bands from package data, and fixed machine instances such as tty2 through tty6. Check may run read-only for root or the supported diagnostic caller. Fix and undo require root. Writers in `lib/posture.sh` keep quoted heredocs and explicit filenames; the registry does not turn templates into strings.

An unknown scope, severity, function id, duplicate lock id, unsafe argument, missing handler, or handler protocol violation aborts before mutation. A failed lock does not prevent later read-only checks, but assert exits nonzero. Remove reports failed undo and retains remaining lifecycle data for a retry.

AGENTS.md rule 9 is explicit: no environment variable, profile value, kid-writable file, or registry data loaded from disk selects a function, code path, root check, account source, or lock path. The registry is sourced only from the command's resolved package tree. Mutation uses `is_root`; ids and arguments are allowlisted and validated; tests relocate only build-time constants in a copied tree.

## Migration

Snapshot the current lock ids and prove registry parity before changing commands. Add adapter entries around existing `lib/assert-locks.sh` and `lib/posture.sh` functions without changing installed artifacts. Switch `omarchy-kids-assert`, then `omarchy-kids-check`, then the lock portion of remove to registry traversal.

Once parity tests prove all three verbs see the same entries, delete `lib/check-locks.sh` and the duplicate command lists. Existing provisioned machines require no file conversion. Dry-run output may gain stable lock ids but preserves its no-write contract.

`omarchy-kids-assert` re-asserts exactly the registry's current constraints, including session manifests and time infrastructure when those specifications land. It never re-creates a deliberately removed kid account or performs destructive lifecycle work.

## Requirements

- R-LOCKS-1: One package-code registry declares every re-assertable lock with id, scope, severity, check, fix, undo, and argument provider.
- R-LOCKS-2: Check, assert, and remove derive their lock order and coverage only from that registry.
- R-LOCKS-3: Every handler obeys the stable result protocol and fix and undo are idempotent and dry-run safe.
- R-LOCKS-4: Registry validation completes before mutation and rejects duplicate ids, unknown metadata, missing handlers, and unsafe arguments.
- R-LOCKS-5: Destructive lifecycle resources remain outside registry traversal.
- R-LOCKS-6: Current provisioned artifacts and checks have exact parity through migration.
- R-LOCKS-7: Registry loading, dispatch, identity, and root checks comply with AGENTS.md rule 9.

## Tests

`test/shell.d/locks-test.sh` checks registry validation, stable order, scopes, severity, handler results, dry-run, idempotence, and failure continuation. A fixture lock added once must appear automatically in check, assert, and remove tests. Existing `assert-test.sh`, `check-test.sh`, and `remove-test.sh` prove parity with their pre-migration lock inventories.

`test/shell.d/trust-boundary-test.sh` rejects external registry paths, dynamic sourcing, environment-selected handlers, unvalidated function dispatch, account overrides, and alternate root checks.

`test/live/90-remove.sh` proves dry-run changes nothing, real removal undoes every registered lock, and a second removal is cleanly idempotent. This candidate has no new visible UI, so it requires command and filesystem evidence rather than screenshots.

## Out of Scope

This work does not rewrite lock templates, change policy meaning, absorb destructive account lifecycle, or create a general plugin system.

## Tickets

1. **Declare and validate the lock registry**
   - Files: `lib/locks.sh`, `lib/assert-locks.sh`, `test/shell.d/locks-test.sh`
   - Acceptance: One validated registry reproduces the current lock inventory and rejects unsafe declarations before mutation.
   - Satisfies: R-LOCKS-1, R-LOCKS-4, R-LOCKS-6, R-LOCKS-7
2. **Drive check and assert from the registry**
   - Files: `bin/omarchy-kids-assert`, `bin/omarchy-kids-check`, `lib/check-locks.sh`, `test/shell.d/assert-test.sh`, `test/shell.d/check-test.sh`
   - Acceptance: Check and assert traverse the same ordered entries with stable results and no coverage loss.
   - Satisfies: R-LOCKS-2, R-LOCKS-3, R-LOCKS-6
3. **Drive lock removal from the registry**
   - Files: `bin/omarchy-kids-remove`, `lib/posture.sh`, `test/shell.d/remove-test.sh`, `test/shell.d/locks-test.sh`
   - Acceptance: Dry-run and real removal invoke every lock's idempotent undo while leaving lifecycle resources explicit.
   - Satisfies: R-LOCKS-2, R-LOCKS-3, R-LOCKS-5
4. **Delete duplicate lists and prove uninstall**
   - Files: `lib/check-locks.sh`, `test/shell.d/trust-boundary-test.sh`, `test/live/90-remove.sh`
   - Acceptance: No second lock inventory remains, hostile overrides fail, and VM removal is complete and repeatable.
   - Satisfies: R-LOCKS-2, R-LOCKS-6, R-LOCKS-7
