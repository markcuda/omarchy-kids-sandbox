# Weekend limits in the wizard

Sixteen original VM screenshots from the installed candidate for #170 / PR171 at 598a82f8bd6942e5444bbb51c3013dbba35ae4fa, September 6, 2026. Each theme starts with a fresh parent login and Quickshell watching enabled. Display: 1280×800; Foot window: 1256×750. Ben is an invented fixture. Apply was never selected and no account was created.

| Check | Catppuccin Latte | Tokyo Night |
| --- | --- | --- |
| Default Time choice | [View](latte-time-default.png) | [View](tokyo-time-default.png) |
| Default summary | [View](latte-ready-default.png) | [View](tokyo-ready-default.png) |
| Weekend settings changed | [View](latte-advanced-weekends-custom.png) | [View](tokyo-advanced-weekends-custom.png) |
| Custom summary | [View](latte-ready-weekends-custom.png) | [View](tokyo-ready-weekends-custom.png) |
| Back to Time | [View](latte-back-time-custom.png) | [View](tokyo-back-time-custom.png) |
| Summary after accepting Time default | [View](latte-ready-after-time-default.png) | [View](tokyo-ready-after-time-default.png) |
| Leave confirmation | [View](latte-leave.png) | [View](tokyo-leave.png) |
| Wizard closed | [View](latte-closed.png) | [View](tokyo-closed.png) |

Default screen time is 60 minutes on weekdays and weekends; bedtime is 19:30 weekdays and 20:00 weekends. Changing only weekends to 75 minutes and 21:00 updates both the Time choice and summary. Returning through Back, actually selecting the Time default, and continuing to Ready preserves those weekend values. Weekdays remain 60 minutes and 19:30. Root and independent screenshot review passed in both themes.

The test-box formatter, Mac suite (42 files, five platform skips), VM suite (42 files, two skips), and named scenario05 passed before the installed preview. Separate installed restoration readback passed afterward: all 181 package files intact, original themes/settings/timer restored, greeter only. Recorded wizard/watch processes were gone and Ben remained absent. Package SHA-256: e6b41045d1d19cf8ae90742423bfd0562c0cb0cf24c6c210e2aa8b2cacabab6b. Machine-state claims come from readback, not the screenshots.

Latte diagnostics were retained privately: the screensaver took focus and the guard blocked input until verified dismissal; QMP text entry dropped a colon, caught in a screenshot before submission and corrected with an explicit colon key. Tokyo used explicit colon input. Two earlier local gate starts failed on a sparse checkout before machine calls; the complete checkout passed. The Advanced app row still clips (#172), and desktop wording remains numeric (#174). This is candidate preview evidence, not a full release walkthrough. [Original checksums](SHA256SUMS).
