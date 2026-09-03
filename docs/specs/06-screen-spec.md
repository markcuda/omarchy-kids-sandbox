# Screen Specification

## Goal

Make each wizard and panel screen a named package-owned specification so content, choices, defaults, validation, and keyboard behavior are reviewable without tracing positional shell calls.

## Today

`lib/tui.sh:270-575` exposes choose, input, confirm, and summary functions with seven to nine positional arguments, named arrays, and function-name validators. `lib/wizard-screens.sh:9-322` repeats those calls for each wizard screen. Panel flows build more positional screens in `lib/panel-home.sh:32-80`, `lib/panel-kid.sh:14-352`, and `lib/panel-requests.sh`. Although SPEC.md R-WIZ-9 names `tui/screens/*.toml`, no `share/tui` screen data exists.

## Interface

Each source screen is `share/tui/screens/<id>.toml`, installed at `/usr/share/omarchy-kids/tui/screens/<id>.toml`. Schema version 1 fields are `id`, `kind`, `title`, `body`, `choices`, `default`, `footer`, `show_omy`, `omy_line`, `step`, `total`, `validator`, and `choice_provider`. Only fields valid for the declared kind may appear.

Kinds are `choose`, `input`, `confirm`, and `summary`. Static choices live in the screen. Dynamic choices use allowlisted provider ids such as `bands`, `avatars`, `themes`, `kids`, or `requests`. Validators likewise use allowlisted ids. Text supports only documented placeholders such as `kid_name`, `band`, and `level`; it has no shell interpolation.

Shell callers set typed values with `tui_context_set <key> <value>`, then call `tui_screen <id>`. `tui_init` loads and validates the fixed screen directory once per process. `tui_screen` returns 0 for accept, 1 for back, and 130 for leave, with the selected value in `TUI_REPLY`. It returns 2 for an unknown screen, malformed spec, missing context, unknown placeholder, validator, or provider, or a scripted answer that is invalid for the screen.

Package/root may write screen specifications. Wizard and panel processes may read them. Kids cannot write them. The renderer remains the single owner of gum invocation, theme color, focus, Esc, Ctrl+C, and answer-file behavior.

AGENTS.md rule 9 applies to screen data: no environment variable or kid-writable value selects the screen directory, parser, validator, provider, executable, library, or root check. Screen files cannot name shell functions or commands. Fixed ids dispatch through code allowlists without `eval`. `OMARCHY_KIDS_TUI_ANSWERS` remains an allowlisted test-data input, validated at read time; relocation uses only rewritten build-time constants in a copied tree.

## Migration

Add the loader and convert wizard screens one flow at a time while wrappers preserve the 0/1/130 contract, gum style, keyboard order, and scripted answers. Convert panel screens after wizard parity is proven. Existing machines have no persistent screen data to migrate; package upgrade installs the specifications.

Keep positional renderer functions private during transition, then make a static test reject calls outside `lib/tui.sh`. Remove named-array and dynamic-validator dispatch after the last caller moves.

`omarchy-kids-assert` does not rewrite package-owned screen specifications. Package integrity owns them; `omarchy-kids-check` may report a missing or invalid installed screen. A missing required screen makes the interactive command fail before changing configuration.

## Requirements

- R-SCREEN-1: Every wizard and panel screen has one schema-versioned specification at the fixed package-owned screen path.
- R-SCREEN-2: `tui_init` validates and loads screen data once, and `tui_screen <id>` is the only public render call.
- R-SCREEN-3: Screen kinds, fields, placeholders, validators, providers, and dynamic values are type- and allowlist-validated before rendering.
- R-SCREEN-4: Migrated flows preserve the 0/1/130 status contract, `TUI_REPLY`, keyboard completion, theme behavior, and scripted answers.
- R-SCREEN-5: No screen specification can select a shell function, command, executable, parser, code path, or privileged action.
- R-SCREEN-6: Wizard and panel callers contain no positional screen definitions after migration.
- R-SCREEN-7: Missing or invalid required screen data fails before any configuration write.

## Tests

`test/shell.d/tui-test.sh` covers schema validation, one-time loading, all kinds, context substitution, allowlists, status codes, scripted answers, and failure before render. `wizard-test.sh` and `panel-test.sh` compare every migrated screen's choices, defaults, navigation, and writes to the current contract and reject positional calls outside the renderer.

`test/shell.d/trust-boundary-test.sh` rejects screen-directory, parser, validator, provider, command, library, and root-check overrides; `eval`; executable fields; and unvalidated answer-file data.

`test/live/60-wizard-easy.sh` completes the keyboard-only wizard and captures each changed visible state, including `60-screen-welcome.png`, `60-screen-band.png`, `60-screen-web.png`, `60-screen-time.png`, and `60-screen-summary.png`. A new `test/live/70-panel-screens.sh` navigates the panel without a pointer and captures `70-screen-home.png`, `70-screen-kid.png`, and `70-screen-requests.png`.

## Out of Scope

This work does not redesign copy or visuals, create a general form language, move enforcement into screen data, or allow third-party screens.

## Tickets

1. **Define and validate the screen format**
   - Files: `share/tui/screens/*.toml`, `lib/tui.sh`, `test/shell.d/tui-test.sh`
   - Acceptance: The loader validates every screen once and `tui_screen <id>` preserves the renderer's status and reply contract.
   - Satisfies: R-SCREEN-1, R-SCREEN-2, R-SCREEN-3, R-SCREEN-5
2. **Migrate the wizard screens**
   - Files: `share/tui/screens/wizard-*.toml`, `lib/wizard-screens.sh`, `lib/wizard-advanced.sh`, `test/shell.d/wizard-test.sh`
   - Acceptance: The keyboard-only wizard uses named specifications with behavior and scripted-answer parity.
   - Satisfies: R-SCREEN-1, R-SCREEN-4, R-SCREEN-6, R-SCREEN-7
3. **Migrate the panel screens**
   - Files: `share/tui/screens/panel-*.toml`, `lib/panel-home.sh`, `lib/panel-kid.sh`, `lib/panel-requests.sh`, `test/shell.d/panel-test.sh`
   - Acceptance: Every panel screen uses the named interface and invalid data fails before a settings write.
   - Satisfies: R-SCREEN-1, R-SCREEN-4, R-SCREEN-6, R-SCREEN-7
4. **Remove dynamic dispatch and prove the UI**
   - Files: `lib/tui.sh`, `test/shell.d/trust-boundary-test.sh`, `test/live/60-wizard-easy.sh`, `test/live/70-panel-screens.sh`
   - Acceptance: No positional or dynamic function dispatch remains, and VM screenshots prove keyboard-complete wizard and panel flows.
   - Satisfies: R-SCREEN-4, R-SCREEN-5, R-SCREEN-6
