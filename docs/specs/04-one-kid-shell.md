# One Kid Shell

## Goal

Run one Quickshell instance per kid session and route every launcher, modal, toast, and shelf request through typed IPC while keeping the kid-side shell strictly display-only.

## Today

Level 1 starts a launcher shell in `bin/omarchy-kids-session-start:223-225`. Time starts additional QML processes at `bin/omarchy-kids-time:97-120`, ask executes another shell at `bin/omarchy-kids-ask:97-116`, and exit does the same at `bin/omarchy-kids-exit:61-85`. `bin/omarchy-kids-launcher-ctl:8-38` writes an environment-selected control file that `share/launcher/shell.qml:113-147` polls every 150 ms. Separate roots under `share/ask`, `share/exit-modal`, `share/time`, `share/wifi`, and `share/plugins` duplicate process and surface setup.

## Interface

The package installs one configuration at `/usr/share/omarchy-kids/shell/shell.qml` with component files under the same directory. Session startup runs exactly `/usr/bin/qs -p /usr/share/omarchy-kids/shell --no-duplicate`.

The root QML object declares a Quickshell v0.3.1 `IpcHandler` with target `kids`. Bash calls it only through `lib/shell-ipc.sh`, which executes `/usr/bin/qs -p /usr/share/omarchy-kids/shell ipc call kids <function> [arguments...]`. This follows the [Quickshell v0.3.1 IPC contract](https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/IpcHandler/): functions have explicit argument and return types and no more than ten arguments.

The typed functions are `ping()`, `showLauncher()`, `activateLauncher()`, `showExit()`, `showAsk(kind, requestId)`, `showToast(message)`, `showTimeUp(reason, deadline)`, `hideTimeUp()`, `showWifi()`, `showPlugins()`, and `hideModal()`. Bash-facing verbs use the same names. Unknown functions, invalid enums, malformed ids, excessive text, and unavailable shell instances return nonzero without opening a surface.

Only one exclusive modal is visible. Priority is time-up, exit or ask, then Wi-Fi or plugins. A higher-priority surface replaces a lower one; lower-priority requests fail while a higher one is open. The launcher may remain behind a modal. Esc and keyboard navigation preserve the existing contracts.

The shell is display-only. It never chooses an account, level, policy, launcher argv, budget, lights-out result, grant, lock, or termination. It reads the caller-bound session manifest, renders root time state, and submits fixed requests to trusted commands. No IPC function accepts a path, executable, QML component, shell fragment, account, or privileged action. QML uses argv arrays and never `sh -c`.

The kid may call display verbs. Root may request a time display through the kid's session, but enforcement proceeds without it. Package/root owns all QML and the IPC adapter; the kid may write none of them.

AGENTS.md rule 9 applies at both ends: environment variables and kid-writable files cannot select the QML tree, IPC target, `qs` binary, sibling command, manifest, control socket, or root check. `/usr/bin/qs`, the installed shell path, and target `kids` are fixed build-time constants. Commands self-resolve libraries. Typed data is range- and allowlist-validated before display. There is no control-file polling seam.

## Migration

Install the aggregate shell beside existing QML roots and prove `ping`. Start it once for new kid sessions while existing logged-in sessions retain their old processes until logout. Move launcher control first, then exit and ask, then time, Wi-Fi, and plugins to IPC calls.

Keep old QML entry points only while a caller still uses them. After every caller and live scenario moves, delete the duplicate roots and runtime control files. If the aggregate shell cannot start or answer `ping`, login fails closed for a kid; parent login remains untouched.

`omarchy-kids-assert` re-asserts package-dependent session manifest and service state, not a kid process. Pacman owns the QML files. Session preflight verifies that the fixed shell entry point exists, is package-owned, and answers `ping` after launch.

## Requirements

- R-SHELL-1: Each kid session runs exactly one Quickshell process from the fixed installed configuration.
- R-SHELL-2: Bash invokes typed display functions through the exact fixed-path `qs ... ipc call kids` contract.
- R-SHELL-3: Launcher, exit, ask, time, Wi-Fi, and plugins share one modal coordinator and keyboard-complete shell.
- R-SHELL-4: The shell is display-only and cannot select or perform policy, executable, account, grant, lock, or termination decisions.
- R-SHELL-5: No QML or controller uses `sh -c`, an environment-selected path, a kid-writable control file, or polling for commands.
- R-SHELL-6: Invalid IPC input fails without changing visible or privileged state, and modal priority is deterministic.
- R-SHELL-7: A missing or unresponsive shell fails kid login closed without touching the parent session.

## Tests

`test/shell.d/shell-ipc-test.sh` uses a fake `qs` to assert exact argv, typed validation, modal priority, one process, and nonzero failures. Existing launcher, exit, ask, time, Wi-Fi, and plugins tests verify their fixed IPC calls. `test/shell.d/qml-theme-static-test.sh` verifies one themed QML root and direct argv execution.

`test/shell.d/trust-boundary-test.sh` rejects executable, QML path, IPC target, socket, account, library, and root-check overrides; control-file polling; `sh -c`; and privileged functions in the QML surface.

`test/live/10-cold-boot-kid.sh`, `30-portal-login-and-finish.sh`, `40-time-lights-out.sh`, and `50-ask-grant.sh` count one Quickshell process and capture their existing visible states as `10-one-shell-launcher.png`, `30-one-shell-exit.png`, `40-one-shell-time.png`, and `50-one-shell-ask.png`. A new `test/live/55-shell-tools.sh` captures `55-one-shell-wifi.png` and `55-one-shell-plugins.png` and proves each surface appears within 500 ms of the IPC call.

## Out of Scope

This work does not make QML an enforcement service, redesign the visuals, replace parent authentication, or change the policies displayed by a surface.

## Tickets

1. **Build the aggregate shell and IPC adapter**
   - Files: `share/shell/shell.qml`, `share/shell/KidsTheme.qml`, `lib/shell-ipc.sh`, `test/shell.d/shell-ipc-test.sh`
   - Acceptance: One fixed-path shell answers typed `ping` and enforces deterministic modal priority.
   - Satisfies: R-SHELL-1, R-SHELL-2, R-SHELL-6
2. **Move launcher, exit, and ask to IPC**
   - Files: `bin/omarchy-kids-session-start`, `bin/omarchy-kids-launcher-ctl`, `bin/omarchy-kids-exit`, `bin/omarchy-kids-ask`, `share/shell/Launcher.qml`, `share/shell/ExitModal.qml`, `share/shell/AskModal.qml`, `test/shell.d/session-start-test.sh`, `test/shell.d/exit-test.sh`, `test/shell.d/ask-test.sh`
   - Acceptance: Launcher, exit, and ask share one process, use no command file, and invoke no shell command string.
   - Satisfies: R-SHELL-3, R-SHELL-5
3. **Move time, Wi-Fi, and plugins to IPC**
   - Files: `bin/omarchy-kids-time`, `bin/omarchy-kids-wifi`, `bin/omarchy-kids-plugins`, `share/shell/TimeToast.qml`, `share/shell/TimeUp.qml`, `share/shell/WifiPicker.qml`, `share/shell/PluginsShelf.qml`, `test/shell.d/time-test.sh`, `test/shell.d/wifi-test.sh`, `test/shell.d/plugins-test.sh`
   - Acceptance: All remaining surfaces use typed IPC and contain no enforcement or privileged action.
   - Satisfies: R-SHELL-3, R-SHELL-4, R-SHELL-5
4. **Remove duplicate shells and prove the session**
   - Files: `share/launcher/shell.qml`, `share/ask/shell.qml`, `share/exit-modal/shell.qml`, `share/time/timesup.qml`, `share/wifi/shell.qml`, `share/plugins/shell.qml`, `bin/omarchy-kids-session`, `test/shell.d/trust-boundary-test.sh`, `test/live/10-cold-boot-kid.sh`, `test/live/30-portal-login-and-finish.sh`, `test/live/40-time-lights-out.sh`, `test/live/50-ask-grant.sh`, `test/live/55-shell-tools.sh`
   - Acceptance: New sessions have one responsive shell, fail closed without it, and produce screenshot evidence for every visible surface.
   - Satisfies: R-SHELL-1, R-SHELL-4, R-SHELL-5, R-SHELL-7
