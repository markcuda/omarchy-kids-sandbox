# Advanced editors open without the current value

Four original Catppuccin Latte screenshots from installed wizard candidate 598a82f8bd6942e5444bbb51c3013dbba35ae4fa, September 6, 2026. The Advanced checklist shows the current weekend values, but opening each editor gives a blank input. The parent must remember the value while editing. Ben is an invented fixture; this was a preview with no Apply.

| Setting | Selected current value | Editor |
| --- | --- | --- |
| Weekend minutes: 60 | [View](latte-weekend-minutes-selected.png) | [View](latte-weekend-minutes-editor.png) |
| Weekend bedtime: 20:00 | [View](latte-weekend-bedtime-selected.png) | [View](latte-weekend-bedtime-editor.png) |

Root and independent review verified these originals. The cause is in [Advanced numeric/time inputs](https://github.com/markcuda/omarchy-kids-sandbox/blob/598a82f8bd6942e5444bbb51c3013dbba35ae4fa/lib/wizard-advanced.sh#L249-L265), which do not pass current values to the [input renderer](https://github.com/markcuda/omarchy-kids-sandbox/blob/598a82f8bd6942e5444bbb51c3013dbba35ae4fa/lib/tui.sh#L399-L430). This concern is separate from #170's weekday/weekend labels. [Original checksums](SHA256SUMS).
