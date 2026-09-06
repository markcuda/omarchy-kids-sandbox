Twenty-surface capture — September 6, 2026

These are the 20 original images from the complete ten-surface pass in Tokyo Night and Catppuccin Latte. The VM ran the installed 831d747 build with packaged/runtime inputs identical to public candidate bcd7cdee746c0fc45dc9c0238d0e4f8a25bec5a5 in PR #154. Only invented Cy/Dot test accounts appear. Temporary budget headroom explains the large minute values.

The candidate passed the test-box formatter, all 40 Mac test files, then the same 40 VM files. Mac reported five platform/fixture skips; VM reported two (bar status fixture and ash syntax). Authentication and SO_PEERCRED tests ran on the VM. See [gate summary](gate-summary.log).

The capture scenario exited zero after saving every expected image and verifying restoration. A subsequent [postflight](postflight.log) passed package integrity (181 files, zero altered), Wi-Fi bytes/metadata/QML, original themes and Cy time settings, active timer, collected temporary unit and greeter-only state. The active media recovery receipt and temporary live configuration were absent. All 20 images were archived and hashed before the four tracked originals were restored and the sixteen generated checkout files removed.

The operator and an independent reviewer inspected every image and verified archive identity. This completes screenshot coverage for this candidate; it does not declare a finished release or prove every action shown. Three walkthrough videos, merged-main gates and remaining product issues are still outstanding. The [capture log](capture.log) retains failed readiness probes and setup jq diagnostics; an error-free whole log is not claimed.

| Surface | Tokyo Night | Catppuccin Latte | Findings |
| --- | --- | --- | --- |
| Portal | ![Dark Portal](portal-tokyo-night.png) | ![Light Portal](portal-catppuccin-latte.png) | Parent label remains faint: [#112](https://github.com/markcuda/omarchy-kids-sandbox/issues/112). |
| Launcher | ![Dark Launcher](launcher-tokyo-night.png) | ![Light Launcher](launcher-catppuccin-latte.png) | Missing-app visibility remains: [#91](https://github.com/markcuda/omarchy-kids-sandbox/issues/91). |
| Exit | ![Dark Exit](exit-modal-tokyo-night.png) | ![Light Exit](exit-modal-catppuccin-latte.png) | Password label remains: [#118](https://github.com/markcuda/omarchy-kids-sandbox/issues/118). |
| Ask | ![Dark Ask](ask-tokyo-night.png) | ![Light Ask](ask-catppuccin-latte.png) | Password label and keyboard guidance remain: [#131](https://github.com/markcuda/omarchy-kids-sandbox/issues/131). |
| Time’s Up | ![Dark Time’s Up](times-up-tokyo-night.png) | ![Light Time’s Up](times-up-catppuccin-latte.png) | Countdown and Ask action fit. |
| Wi-Fi | ![Dark Wi-Fi](wifi-picker-tokyo-night.png) | ![Light Wi-Fi](wifi-picker-catppuccin-latte.png) | Empty state now has retry and matching keyboard guidance. |
| More apps | ![Dark More apps](plugins-shelf-tokyo-night.png) | ![Light More apps](plugins-shelf-catppuccin-latte.png) | Empty-state instructions remain: [#117](https://github.com/markcuda/omarchy-kids-sandbox/issues/117). |
| Setup wizard | ![Dark Setup wizard](wizard-tokyo-night.png) | ![Light Setup wizard](wizard-catppuccin-latte.png) | Opening screen; startup notices no longer cover it. |
| Parent panel | ![Dark Parent panel](panel-tokyo-night.png) | ![Light Parent panel](panel-catppuccin-latte.png) | Child summaries and two requests fit; no startup notices. |
| Parent bar | ![Dark Parent bar](bar-module-tokyo-night.png) | ![Light Parent bar](bar-module-catppuccin-latte.png) | Live rows and full actions fit. Missing request count: [#155](https://github.com/markcuda/omarchy-kids-sandbox/issues/155). |

Separate functional evidence: [repeated ledger updates](../bar-ledger-verified/ledger-updates-verified.md), [selection and reload](../bar-153-verified/bar-selection-verified.md), and [installed Wi-Fi interactions](../wifi-installed-verified/wifi-interactions.md). The latter records its original helper metadata failure and separate verified repair.
