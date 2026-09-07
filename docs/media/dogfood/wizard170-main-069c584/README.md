# Weekend limits verified on merged main

Sixteen original screenshots from merged main 069c584d2733a233ee3fd6f84c2a4cbcc8c2bb27, tree-identical to accepted candidate 598a82f, on September 6, 2026. The installed package remained SHA-256 e6b41045d1d19cf8ae90742423bfd0562c0cb0cf24c6c210e2aa8b2cacabab6b. Each theme started with a fresh parent login and Quickshell watching enabled. Display 1280×800, Foot 1256×750. Ben is an invented fixture; Apply was never selected.

| Check | Catppuccin Latte | Tokyo Night |
| --- | --- | --- |
| Default Time choice | [View](latte-time-default.png) | [View](tokyo-time-default.png) |
| Default Ready summary | [View](latte-ready-default.png) | [View](tokyo-ready-default.png) |
| Weekend minutes entered | [View](latte-weekend-minutes-entered.png) | [View](tokyo-weekend-minutes-entered.png) |
| Weekend bedtime entered | [View](latte-weekend-bedtime-entered.png) | [View](tokyo-weekend-bedtime-entered.png) |
| Custom Ready summary | [View](latte-ready-custom.png) | [View](tokyo-ready-custom.png) |
| Time after Back | [View](latte-time-retained.png) | [View](tokyo-time-retained.png) |
| Ready after selecting Time again | [View](latte-ready-retained.png) | [View](tokyo-ready-retained.png) |
| Wizard closed | [View](latte-closed.png) | [View](tokyo-closed.png) |

Both runs showed defaults of 60 weekday/weekend minutes, with bedtime 19:30 weekdays and 20:00 weekends. Changing weekends to 75 minutes and 21:00 left weekdays unchanged. After Back through Password, Desktop, Wi-Fi and Apps, the driver actually selected Time’s displayed default row and continued to Ready. Both screens retained the custom weekend values. Root inspected every screen; an independent session reviewed these eight keyframes per theme.

The merged-main formatter, Mac 42-file suite with five platform skips, VM 42-file suite with two skips, and scenario 05 passed before this installed repeat. Separate restoration readback passed afterward: 181 package files intact, original themes/settings/timer, greeter only, Ben absent, and recorded wizard/watch processes gone. Machine-state claims come from readback; screenshots show the visible route. 77 original frames are retained privately. No new input failure occurred; bedtime used the already verified explicit colon key sequence because harness issue 178 remains open. Known app clipping #172 and numeric desktop wording #174 remain separate. This is preview acceptance evidence; the three full release walkthroughs remain open.

[Original image checksums](SHA256SUMS).
