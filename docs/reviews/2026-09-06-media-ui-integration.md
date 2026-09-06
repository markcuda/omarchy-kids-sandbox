# Media UI integration candidate

This local candidate preserves the histories of media recovery `6592b157`
(#138 collected-unit cleanup and #139 GUI selection), main `f28a4614`
(#136 empty Wi-Fi replies), #140 `4d380bcd` (bar FileView reload), and
#143 `eaa8cd1e` (empty Wi-Fi guidance and retry).

The integration adjustment verifies one settled Wi-Fi state in both the readiness
frame and the release frame: list navigation with join/close keys, no networks
with retry/close keys, or the scan-error message with retry/close keys. A captured
error is evidence of that UI state, not a successful scan or join. Loading,
title-only, password, incomplete retry, and a final frame that regresses to loading
are rejected by owned behavioral fixtures executing the copied driver. The OCR
stub checks supplied frame text; it does not prove real rendering or Vision OCR.

Pending before acceptance:

- Independent review and the ordered formatter, Mac suite, VM suite, and full media run.
- #140: verify the enabled parent plugin copy matches the packaged QML. Keep the
  same shell PID across atomic status updates (empty, live, changed minutes/paused,
  absent), checking the open menu and keyboard cursor in both themes. Package
  replacement alone does not update the plugin copy in the parent's home.
- #143: named installed Wi-Fi proof in both themes, including retry with pointer
  and keyboard, loading suppression, masked password and Back. Existing Air
  preview evidence remains separate from installed-package acceptance.

No live run, package deployment, parent configuration change, or ticket closure
is claimed by this integration commit. Keep the issue PRs separate.

Local checks: focused media-driver, Wi-Fi, and QML theme checks; Bash syntax,
ShellCheck warnings, and diff whitespace checks. The local machine has no shfmt;
formatting remains part of the ordered gate. The six AGENTS review shapes were
checked: all scenario commands and OCR are owned fixtures, no new state mutation
or locking is introduced, OCR arguments remain literal, and error-state evidence
is explicitly distinguished from successful networking.
