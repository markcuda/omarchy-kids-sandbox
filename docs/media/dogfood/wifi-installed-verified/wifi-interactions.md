Wi-Fi interaction evidence for #143 and #145

Source: 831d74784861e9b56409b74b156af0f36f42059d. Installed picker QML was unchanged; a temporary fixture backend supplied invented HomeNet/OpenNet responses. This verifies UI behavior and password transport, with no real network association or policy claim. #148 joined-message persistence is excluded.

The ordered formatter, Mac suite and serial VM suite passed; see [gate summary](gate-summary.log). The VM operator reviewed all 28 archived images. An independent reviewer inspected 12: both themes’ empty, valid held scan, scan error, masked password, reopened empty password and held join. Labels fit, retry controls are visible, passwords stay masked, reopened fields are empty, and busy screens omit Enter actions. Ten unchanged images are selected below.

The independent review checked all 44 [fixture events](actions.log). Offsets are zero-based:

| Evidence | Tokyo Night | Catppuccin Latte |
| --- | --- | --- |
| Valid held scan: one started/success pair, one PID | 7–8 | 25–26 |
| Keyboard retry, error, recovered list | 6, 9–10 | 27–29 |
| Protected join: expected line, EOF, deliberate failure | 11–14 | 30–33 |
| Retry: expected line, EOF, held, success, refreshed list | 15–20 | 34–39 |
| Open join: zero input bytes, success, refreshed list | 21–23 | 40–42 |

The operator reports two extra Enter presses during each valid held scan and protected join; the archived receipt records those inputs, and the event ranges contain one backend invocation each. The first dark held attempt, offsets 2–5, timed out and is excluded. Four protected invocations each received the expected fixture line followed by EOF; two open invocations received zero bytes.

The operator reports Escape closed light PID 529508 and repeated dark PID 553766, with process absence checked before cleanup. Those live probes were not independently rerun. The initial dark Escape attempt is excluded because a close command preceded its independent probe.

Recovery: scenario 30387 exited 0 and restored the original client bytes and 0755 root:root ownership, but its [first postflight](postflight-original.log) found a Wi-Fi client modification-time mismatch. The private test helper had failed to preserve that metadata. A separately reviewed [timestamp repair](timestamp-repair.log) restored the exact installed-package timestamp and verified 181 files with zero altered. It changed no client bytes or QML. The original scenario alone did not pass complete recovery.

A subsequent [readback](postflight-final.log) passed package integrity, client bytes/ownership/permissions/timestamp, QML hash, both machines’ themes, Cy’s recorded time settings and theme, the active timer, collected test unit, greeter-only state and absence of active recovery receipts or temporary live config. The original outer scenario had checked restoration of its Wi-Fi setting. Interaction acceptance is complete with this separately verified repair; it does not claim the original helper restored metadata correctly. The corrected helper has separate owned tests and review, but has not yet been used in a live run.

Tokyo Night: [empty](wifi-831-dark-empty.png), [loading-60](wifi-831-dark-loading-60.png), [scan-error](wifi-831-dark-scan-error.png), [password-masked](wifi-831-dark-password-masked.png), [joining](wifi-831-dark-joining.png).

Catppuccin Latte: [empty](wifi-831-light-empty.png), [loading](wifi-831-light-loading.png), [scan-error](wifi-831-light-scan-error.png), [password-masked](wifi-831-light-password-masked.png), [joining](wifi-831-light-joining.png).
