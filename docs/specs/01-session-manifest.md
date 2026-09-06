# Session Manifest

## Goal

Build one root-owned session manifest per kid so login, the launcher, the browser, and later shell surfaces consume the same validated account state without rescanning desktop files or trusting a kid-writable runtime document.

## Today

`bin/omarchy-kids-session-start:67-71` reads level, band, allowlist, and web mode separately. It scans desktop files and resolves commands at `bin/omarchy-kids-session-start:77-177`, then writes executable strings into `/run/user/<uid>/omarchy-kids/launcher-<uid>.json` at `bin/omarchy-kids-session-start:179-218`. `share/launcher/shell.qml:89-105` accepts that path from the environment, and `share/launcher/shell.qml:167-183` runs a selected string through `sh -c`. Issue #60 proposes `lib/launcher-map.sh` and `/etc/omarchy-kids/launchers/<kid>.json`; neither exists at commit `ca267b2`. This design absorbs that map and installed file instead of creating a second launcher contract.

## Interface

The package adds `lib/session-manifest.sh`. It uses `lib/launcher-map.sh` as the only mapping from an allowed launcher id to fixed argv. If issue #60 lands first, its map is extended in place; it is not copied. Source data stays in `share/bands/bands.toml`, `share/packs/<band>.toml`, and the profile.

The installed manifest is `/etc/omarchy-kids/sessions/<kid>.json`, schema version 1. It contains the account, display name, avatar, band, level, theme, `show_missing` setting, allowlist, web mode and policy id, time settings, and launcher tiles. Each tile has an id, label, icon, installed state, and an argv array. It never has a shell command string. Older schema-version-1 documents without `show_missing` remain valid and default to `false` during freshness comparison.

`omarchy-kids-session --manifest` has no kid or path argument. It derives the account from `id -un`, opens only `/etc/omarchy-kids/sessions/<account>.json`, validates the schema and account, and prints the document. Normal session startup reads the same document once, then performs live lock checks before Hyprland starts.

The builder has internal `build <kid>` and `check <kid>` verbs. Root may write. The named kid may read only their manifest through `omarchy-kids-session --manifest`; root may read every manifest. The directory is `0750 root:omarchy-kids`; documents are `0640 root:omarchy-kids` and replaced atomically.

An unknown launcher id, mutable executable, invalid profile, wrong owner, symlink, malformed JSON, schema mismatch, or account mismatch is fatal. A missing optional application is represented as unavailable and is not executable. A rebuild failure leaves the last valid manifest in place; first login without a valid manifest fails closed.

AGENTS.md rule 9 is absolute: no environment variable or kid-writable value selects the manifest, schema, launcher map, executable, library, or root check. Commands resolve sibling code from their own `readlink -f "$0"` location, root checks use `lib/kids.sh` `is_root`, identity comes from `id -un`, and tests relocate only build-time constants in a copied tree. Root never opens a kid-owned path to build this document.

## Migration

First ship the builder and parity tests while current startup remains active. Build and validate manifests for existing profiles without changing their `.conf` files. If `/etc/omarchy-kids/launchers/<kid>.json` already exists from issue #60, import its validated fixed argv through `lib/launcher-map.sh`; after a valid session manifest is installed, the separate launcher file is no longer read. If it does not exist, build launcher entries directly from package-owned pack data through the same map.

Next make `omarchy-kids-session` and `omarchy-kids-session-start` consume the manifest. Existing logged-in sessions keep their current runtime files until logout. New logins fail closed if migration has not produced a valid manifest. Last, remove desktop scanning, string commands, the launcher JSON under `/run/user`, and its environment-selected path.

`omarchy-kids-assert` re-asserts the sessions directory and one valid, current, root-owned manifest per provisioned kid. Package upgrades rebuild atomically after validating all source data. Assert never repairs an invalid profile by guessing a value.

## Requirements

- R-MANIFEST-1: A provisioned kid has one schema-versioned manifest at `/etc/omarchy-kids/sessions/<kid>.json` with the required ownership and mode.
- R-MANIFEST-2: The manifest represents every session setting currently resolved by session startup, including launcher tiles as fixed argv arrays.
- R-MANIFEST-3: `lib/launcher-map.sh` is the sole launcher id-to-argv map, including when issue #60 lands before this work.
- R-MANIFEST-4: `omarchy-kids-session --manifest` derives the caller from `id -un` and rejects a missing, mutable, linked, malformed, stale, or mismatched document.
- R-MANIFEST-5: Session startup performs no desktop-file scan and reads no kid-writable launcher or configuration document.
- R-MANIFEST-6: A failed rebuild preserves the last valid manifest; a first login without one fails closed.
- R-MANIFEST-7: Assert checks and re-asserts every provisioned kid's manifest without changing valid profile intent.

## Tests

`test/shell.d/session-manifest-test.sh` covers schema, atomic replacement, modes, launcher-map parity, missing applications, stale data, and failure preservation. `session-test.sh` and `session-start-test.sh` prove one read, no desktop scan, no `sh -c`, and fail-closed login.

`test/shell.d/trust-boundary-test.sh` rejects runtime path, binary, library, schema, and account overrides; kid-writable manifests; shell command fields; and any second launcher map.

`test/live/10-cold-boot-kid.sh` compares the manifest to the rendered tiles, launches each available tile, and captures `10-session-manifest-launcher.png`. `test/live/30-portal-login-and-finish.sh` corrupts a scratch manifest, proves login refusal, restores it with assert, and captures `30-session-manifest-recovered.png`.

## Out of Scope

This work does not redesign packs, add applications, change screen-time authority, combine QML processes, or change the profile file format.

## Tickets

1. **Define and build the manifest**
   - Files: `lib/session-manifest.sh`, `lib/launcher-map.sh`, `test/shell.d/session-manifest-test.sh`
   - Acceptance: Existing profiles produce deterministic, valid manifests with fixed launcher argv and atomic failure preservation.
   - Satisfies: R-MANIFEST-1, R-MANIFEST-2, R-MANIFEST-3, R-MANIFEST-6
2. **Expose the caller-bound manifest**
   - Files: `bin/omarchy-kids-session`, `test/shell.d/session-test.sh`, `test/shell.d/trust-boundary-test.sh`
   - Acceptance: A kid can read only their validated manifest through `--manifest`, and hostile environment values cannot redirect the read.
   - Satisfies: R-MANIFEST-4
3. **Move session startup to the manifest**
   - Files: `bin/omarchy-kids-session-start`, `share/launcher/shell.qml`, `test/shell.d/session-start-test.sh`
   - Acceptance: A new session uses one manifest, executes argv directly, and creates no runtime launcher JSON.
   - Satisfies: R-MANIFEST-2, R-MANIFEST-5, R-MANIFEST-6
4. **Re-assert and prove migrated sessions**
   - Files: `lib/assert-locks.sh`, `bin/omarchy-kids-assert`, `test/shell.d/assert-test.sh`, `test/live/10-cold-boot-kid.sh`, `test/live/30-portal-login-and-finish.sh`
   - Acceptance: Assert restores a missing manifest without changing profile intent, and VM evidence proves the launcher and recovery path.
   - Satisfies: R-MANIFEST-7
