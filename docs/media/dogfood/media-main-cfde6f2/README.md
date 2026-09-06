# Merged-main screenshots, September 6, 2026

Twenty originals cover ten screens in Tokyo Night and Catppuccin Latte. Source is main `cfde6f2c11b91fd84362202de17d62e200278402`; its runtime matches the installed `831d747` build. Only invented fixture accounts appear. Temporary budget headroom explains the large minute values.

Merged main passed the test-box formatter, all 40 Mac test files, then the same 40 VM files. Mac reported five platform/fixture skips and VM two. Authentication and SO_PEERCRED tests ran on the VM.

The full capture run exited zero. Separate restoration readback passed: 181 package files with zero alterations, original Wi-Fi bytes/metadata/QML, original themes and Cy time settings, active timer, collected temporary unit and greeter-only state. Active recovery and temporary configuration files were absent. Original images were archived and hashed before restoring generated checkout files.

The operator and an independent reviewer inspected all 20 images. These are screenshots of the merged baseline, not a finished-release claim. The setup image shows the welcome screen; no setup, approval, removal or video walkthrough is proved by this gallery. Readiness retries and setup jq diagnostics remain in the private capture log; an error-free whole log is not claimed. The earlier run interrupted by Mac disk exhaustion remains archived separately.

| Screen | Tokyo Night | Catppuccin Latte | Findings |
| --- | --- | --- | --- |
| Portal | ![Dark Portal](portal-tokyo-night.png) | ![Light Portal](portal-catppuccin-latte.png) | Parent label remains faint: [#112](https://github.com/markcuda/omarchy-kids-sandbox/issues/112). |
| Launcher | ![Dark Launcher](launcher-tokyo-night.png) | ![Light Launcher](launcher-catppuccin-latte.png) | Missing-app visibility remains: [#91](https://github.com/markcuda/omarchy-kids-sandbox/issues/91). |
| Exit | ![Dark Exit](exit-modal-tokyo-night.png) | ![Light Exit](exit-modal-catppuccin-latte.png) | Password label remains: [#118](https://github.com/markcuda/omarchy-kids-sandbox/issues/118). |
| Ask | ![Dark Ask](ask-tokyo-night.png) | ![Light Ask](ask-catppuccin-latte.png) | Password label and keyboard guidance remain: [#131](https://github.com/markcuda/omarchy-kids-sandbox/issues/131). |
| Time’s Up | ![Dark Time’s Up](times-up-tokyo-night.png) | ![Light Time’s Up](times-up-catppuccin-latte.png) | Countdown and Ask action fit. |
| Wi-Fi | ![Dark Wi-Fi](wifi-picker-tokyo-night.png) | ![Light Wi-Fi](wifi-picker-catppuccin-latte.png) | Empty state has retry and matching keyboard guidance; no wireless association tested. |
| More apps | ![Dark More apps](plugins-shelf-tokyo-night.png) | ![Light More apps](plugins-shelf-catppuccin-latte.png) | Empty-state instructions remain: [#117](https://github.com/markcuda/omarchy-kids-sandbox/issues/117). |
| Setup wizard | ![Dark Setup wizard](wizard-tokyo-night.png) | ![Light Setup wizard](wizard-catppuccin-latte.png) | Welcome screen only; no startup notices cover it. |
| Parent panel | ![Dark Parent panel](panel-tokyo-night.png) | ![Light Parent panel](panel-catppuccin-latte.png) | Child summaries and two requests fit. |
| Parent bar | ![Dark Parent bar](bar-module-tokyo-night.png) | ![Light Parent bar](bar-module-catppuccin-latte.png) | Live rows and actions fit; request count remains absent: [#155](https://github.com/markcuda/omarchy-kids-sandbox/issues/155). |

Separate merged-main evidence: [real ledger updates](../bar-ledger-main-cfde6f2/README.md), [controlled bar selection and reload](../bar-main-cfde6f2/README.md), and [installed Wi-Fi interactions](../wifi-main-cfde6f2/README.md). Remaining product fixes and three walkthrough videos are still outstanding.
