# Configuration Schema

## Goal

Define every profile setting once so defaults, types, validation, labels, editors, and grouped reads cannot drift across `omarchy-kids-conf`, the wizard, the panel, and session startup.

## Today

`bin/omarchy-kids-conf:29-55` owns key lists and fallbacks, `bin/omarchy-kids-conf:95-165` owns validation, and `bin/omarchy-kids-conf:187-224` resolves precedence. The same settings are mapped again to variables, groups, labels, and editors in `lib/wizard-advanced.sh:9-93`, then written one by one in `lib/wizard-apply.sh:41-55`. `lib/panel-kid.sh:14-352` repeatedly spawns `omarchy-kids-conf` for individual values. Band defaults remain in `share/bands/bands.toml:18-84` and pack defaults remain in `share/packs/<band>.toml`.

## Interface

The package installs `/usr/share/omarchy-kids/config/schema.toml` from `share/config/schema.toml`. Schema version 1 has one entry per profile key with `key`, `type`, `required`, `default_source`, `group`, `label`, `editor`, and type-specific enum or range constraints. Default values stay in bands, packs, global settings, or the parent theme; the schema names their source and does not copy them.

The public per-profile verbs become:

- `omarchy-kids-conf get <kid> <key>`: print one resolved scalar for compatibility.
- `omarchy-kids-conf set <kid> <key> <value|--default>`: validate centrally, set an override, or remove it.
- `omarchy-kids-conf profile <kid>`: print one deterministic JSON document containing typed values, their source, and field metadata.
- `omarchy-kids-conf profile --band <band>`: print the typed seed used before a kid exists.

Only root may `set`. Root and the named kid's trusted session path may read a profile; ordinary kids cannot name another account. The wizard and panel request one profile document per refresh and use schema metadata rather than their own maps.

Unknown keys, types, sources, validators, editors, duplicate entries, malformed TOML, invalid inherited values, and missing required values are errors. `get` exits 1 for an unknown key; `profile` exits 1 and emits no partial JSON. `set` validates before an atomic profile write. `--default` removes only the named override.

AGENTS.md rule 9 applies to the schema itself: no environment variable or kid-writable file selects the schema, profile, parser, validator, editor, or root check. The installed schema and defaults are package-owned fixed paths. Validator and editor ids select fixed internal functions without `eval`. Identity comes from `id`, code from the command's resolved install tree, and test relocation rewrites build-time constants in a copy.

## Migration

Add the schema and a parity test covering every current key, band, fallback, and validation edge before changing callers. Add `profile` while retaining current verbs. Migrate session startup, then the wizard and panel, to one typed read each.

Existing `/etc/omarchy-kids/kids/<kid>.conf` files are not rewritten. Valid known keys retain current precedence. Unknown legacy lines are preserved on write and reported by validation; they are not executed or exposed as settings. Invalid security-relevant values make the profile invalid and kid login fails closed.

After all callers migrate, `show`, `reset`, `bands`, and `band` remain warning compatibility aliases for one release, then leave the public interface. Lifecycle helpers `slug` and `machine` move behind provisioning interfaces rather than remaining configuration verbs.

`omarchy-kids-assert` validates the installed schema and every profile, then re-asserts artifacts derived from a valid profile. It reports invalid intent and does not invent or rewrite values.

## Requirements

- R-CONFIG-1: One package-owned schema defines every supported profile key's type, source, validation, group, label, and editor.
- R-CONFIG-2: Schema defaults reference existing band, pack, global, or parent-theme sources and do not duplicate their values.
- R-CONFIG-3: `profile` returns all resolved settings in one deterministic, typed JSON document with source metadata.
- R-CONFIG-4: `set` is root-only, validates before atomic write, and `--default` removes only one override.
- R-CONFIG-5: Session startup, wizard, and panel contain no independent setting key, validation, label, group, or editor maps.
- R-CONFIG-6: Existing valid profiles resolve identically before and after migration; invalid profiles fail closed without automatic intent changes.
- R-CONFIG-7: Installed code and data paths comply with the rule 9 trust boundary.

## Tests

`test/shell.d/conf-test.sh` checks schema completeness, all types and bounds, precedence parity, stable JSON, atomic writes, compatibility aliases, unknown legacy preservation, and reader/writer authorization. Wizard, panel, session, and session-start tests each prove one grouped read and no local schema map.

`test/shell.d/trust-boundary-test.sh` rejects runtime schema, profile, parser, validator, editor, account, library, and root-check overrides and scans for `eval` or dynamic function execution in the schema path.

`test/live/60-wizard-easy.sh` exercises schema-driven defaults and validation and captures `60-config-schema-wizard.png`. A panel step in the same scenario changes one override, reads back its source, and captures `60-config-schema-panel.png`.

## Out of Scope

This work does not change the meaning of any setting, replace TOML profiles, redesign packs or bands, or add remote configuration.

## Tickets

1. **Declare the configuration schema**
   - Files: `share/config/schema.toml`, `bin/omarchy-kids-conf`, `test/shell.d/conf-test.sh`
   - Acceptance: A parity test proves that the schema covers every current key and reproduces every current default and validation result.
   - Satisfies: R-CONFIG-1, R-CONFIG-2, R-CONFIG-6
2. **Add typed profile reads and writes**
   - Files: `bin/omarchy-kids-conf`, `lib/settings.sh`, `test/shell.d/conf-test.sh`, `test/shell.d/trust-boundary-test.sh`
   - Acceptance: `get`, `set`, and `profile` enforce authorization and return validated deterministic values from fixed package paths.
   - Satisfies: R-CONFIG-3, R-CONFIG-4, R-CONFIG-7
3. **Migrate runtime consumers**
   - Files: `bin/omarchy-kids-session`, `bin/omarchy-kids-session-start`, `lib/wizard-advanced.sh`, `lib/wizard-apply.sh`, `lib/panel-kid.sh`, `test/shell.d/session-test.sh`, `test/shell.d/wizard-test.sh`, `test/shell.d/panel-test.sh`
   - Acceptance: Each flow reads one profile document and no caller retains a parallel settings map.
   - Satisfies: R-CONFIG-5, R-CONFIG-6
4. **Validate installed profiles and prove the UI**
   - Files: `lib/assert-locks.sh`, `test/shell.d/assert-test.sh`, `test/live/60-wizard-easy.sh`
   - Acceptance: Assert reports invalid intent without rewriting it, and VM screenshots prove schema-driven wizard and panel behavior.
   - Satisfies: R-CONFIG-6, R-CONFIG-7
