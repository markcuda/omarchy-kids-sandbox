# Release media

`scripts/media-driver.sh` takes the release screenshots from the test VM at 1280x800. It defaults
to tokyo-night and catppuccin-latte, one dark and one light Omarchy theme. Each successful capture
replaces one `<surface>-<theme>.png`; a failed capture leaves the previous file intact.

| File pair | What it shows |
| --- | --- |
| `portal-<theme>.png` | The restarted SDDM portal with the configured kid and parent tiles. |
| `launcher-<theme>.png` | The test kid's Level 1 launcher and clock. |
| `exit-modal-<theme>.png` | The parent-password exit card over the kid desktop. |
| `ask-<theme>.png` | The Ask a grown-up card for fifteen more minutes. |
| `times-up-<theme>.png` | The root-triggered Time's Up card after its QML readiness check and the captured PNG both confirm the countdown. |
| `wifi-picker-<theme>.png` | The keyboard-driven Wi-Fi picker in helper mode. |
| `plugins-shelf-<theme>.png` | The read-only More apps shelf for the test kid's band. |
| `wizard-<theme>.png` | The parent wizard's Welcome screen in a floating terminal. |
| `panel-<theme>.png` | The parent panel's Home screen in a floating terminal. |

The existing `exit-modal-over-app-<theme>.png` files are extra composition checks, not another
required surface. The three walkthrough videos in docs/GOAL.md item 3 are recorded separately;
this driver only takes stills.

No `bar-module-<theme>.png` is shipped. Omarchy 4.0.2 cannot keep the kid and parent graphical
sessions live at the same time through SDDM. A parent-bar screenshot with a live kid would require
frozen or invented state, so the driver refuses that surface until a real concurrent-session path
exists.
