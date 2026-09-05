# Release media

`scripts/media-driver.sh` takes the release screenshots from the test VM at 1280x800. It defaults
to tokyo-night and catppuccin-latte, one dark and one light Omarchy theme. Each successful capture
replaces one `<surface>-<theme>.png`; a failed capture leaves the previous file intact.

| File pair | What it shows |
| --- | --- |
| `portal-<theme>.png` | The restarted SDDM portal; the test kid's configured name must be visible. |
| `launcher-<theme>.png` | The test kid's Level 1 launcher and clock; GCompris must be visible. |
| `exit-modal-<theme>.png` | The parent-password exit card; its `Finish for <name>` action must be visible. |
| `ask-<theme>.png` | The Ask a grown-up card; its title and fifteen-minute request must be visible. |
| `times-up-<theme>.png` | The root-triggered Time's Up card; QML readiness, title, and countdown must all pass. |
| `wifi-picker-<theme>.png` | The keyboard-driven Wi-Fi picker; its title and keyboard footer must be visible. |
| `plugins-shelf-<theme>.png` | The read-only More apps shelf; its title and instruction must be visible. |
| `wizard-<theme>.png` | The parent wizard; Welcome and Begin must be visible in the floating terminal. |
| `panel-<theme>.png` | The parent panel; Kids Mode and Add a kid must be visible in the floating terminal. |

The existing `exit-modal-over-app-<theme>.png` files are extra composition checks, not another
required surface. The three walkthrough videos in docs/GOAL.md item 3 are recorded separately;
this driver only takes stills.

For every surface, the driver polls disposable screenshots until macOS Vision finds the required
text. It then takes a separate release screenshot and checks the same text again before replacing
the committed image. A process alone is never treated as proof that its UI has rendered.

No `bar-module-<theme>.png` is shipped. Omarchy 4.0.2 cannot keep the kid and parent graphical
sessions live at the same time through SDDM. A parent-bar screenshot with a live kid would require
frozen or invented state, so the driver refuses that surface until a real concurrent-session path
exists.
