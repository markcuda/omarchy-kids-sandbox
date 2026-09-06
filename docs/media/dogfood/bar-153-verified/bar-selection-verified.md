# Parent bar reload and selection verified

Source `831d74784861e9b56409b74b156af0f36f42059d`, installed VM run 49981, September 6, 2026. Scope: #140, #151, and #153.

In Tokyo Night and Catppuccin Latte, the open menu keeps a visible selection when the status file disappears. The child actions disappear, Open requests becomes selected, and recreating valid status restores the readable child actions with the first row selected. The six attached original frames show the last row selected before removal, the absent-file state, and recreation in each theme.

| Theme | Before removal | Status absent | Status recreated |
| --- | --- | --- | --- |
| Tokyo Night | [Frame](bar-selection-tokyo-night-before-removal.png) | [Frame](bar-selection-tokyo-night-status-absent.png) | [Frame](bar-selection-tokyo-night-status-recreated.png) |
| Catppuccin Latte | [Frame](bar-selection-catppuccin-latte-before-removal.png) | [Frame](bar-selection-catppuccin-latte-status-absent.png) | [Frame](bar-selection-catppuccin-latte-status-recreated.png) |

The gate runner inspected all 20 retained frames, including empty/live status, changed minutes, paused status, arrows, and Escape, and recorded exit 0. The wrapper checks the same Quickshell PID around each capture within each theme. This independent evidence review inspected the six linked frames and their checksums; it does not constitute another code review.

The [ordered gate log](gate-summary.log) records formatter, Mac suite, and serial VM suite PASS. The [installation summary](install-summary.log) reports 181 files and zero altered files. The [gate-runner record](gate-runner-review.md) reports restoration to Catppuccin Latte, greeter only on seat0, timer active/waiting, status mode 0640 owned by root:omarchy-parents, and removal of the recovery receipt and backup.

The menu opened through IPC, so keyboard opening is unproven. These are invented VM accounts and controlled status fixtures. No grant or end action was activated. The ledger was quiesced; #152 actual-ledger publication remains a separate pending acceptance check. This is bar evidence, not a complete release-media or Wi-Fi acceptance claim.

Image bytes are unchanged from the archived originals. [SHA256SUMS](SHA256SUMS) records the staged copies.
