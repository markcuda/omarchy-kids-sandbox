# Wizard summary on merged main

Twelve original VM screenshots from the installed repeat of #167 / PR169 at b553913d06eca8be617b511a0b3a8853ecb34382, September 6, 2026. Each theme starts with a fresh parent login and Quickshell watching enabled. Display: 1280×800; Foot window: 1256×750. Ben is an invented fixture; no account was created and Apply was never selected.

| Check | Catppuccin Latte | Tokyo Night |
| --- | --- | --- |
| Current default summary | [View](latte-ready-default.png) | [View](tokyo-ready-default.png) |
| Changed desktop summary | [View](latte-ready-custom.png) | [View](tokyo-ready-custom.png) |
| Back reaches password | [View](latte-summary-back.png) | [View](tokyo-summary-back.png) |
| Custom value persists | [View](latte-ready-after-back.png) | [View](tokyo-ready-after-back.png) |
| Leave confirmation | [View](latte-leave.png) | [View](tokyo-leave.png) |
| Wizard closed | [View](latte-closed.png) | [View](tokyo-closed.png) |

The current summary keeps its formatted rows visible while choosing Apply or Change. Changing the desktop layout refreshes the card; Back and re-entry retain the custom value. Both themes passed independent screenshot review.

Merged-main formatter, Mac suite (42 files, five platform skips), VM suite (42 files, two skips), and the installed scenario passed. One Mac provision test needed a serial retry after exit 141; its cause remains unverified. The separate restoration readback passed: all 181 package files intact, original themes/settings/timer restored, greeter only, owned wizard/watch processes gone, and Ben absent. The screenshots are visual evidence; those machine-state claims come from the separate readback.

The Latte screensaver briefly took focus before input; the guard stopped the wizard key, and the verified screensaver was dismissed before continuing. Known separate issues remain: weekend labels (#170), the Advanced app row (#172), and numeric desktop wording (#174). This is a scoped wizard preview, not a full release walkthrough. [Original checksums](SHA256SUMS).
