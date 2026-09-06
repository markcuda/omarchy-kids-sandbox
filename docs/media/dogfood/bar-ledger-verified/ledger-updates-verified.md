Live parent-bar ledger updates — #152

Public candidate: bcd7cdee746c0fc45dc9c0238d0e4f8a25bec5a5, draft PR #154. Its packaged/runtime inputs match the installed 831d747 build; the public regression test differs and passed fresh ordered gates. The VM formatter passed, followed by all 40 Mac test files and the same 40 VM files. See [gate summary](gate-summary.log).

The timer stayed active. The scenario created one owned temporary child session per theme, invoked the actual ledger tick, and read the resulting status as the owner. It never wrote fixture status JSON. Temporary budget headroom explains the large minute values. Each theme kept the same Quickshell process through all three captures; the runner checked that process and the child session around each update and checked bounded journal windows for status/FileView permission-denial messages.

| Theme | Quickshell PID | Captured minutes | UTC status publication times |
| --- | --- | --- | --- |
| Tokyo Night | 898131 | 549 → 548 → 547 | 12:32:36, 12:33:03, 12:33:45 |
| Catppuccin Latte | 923236 | 547 → 546 → 545 | 12:36:57, 12:37:33, 12:38:27 |

All frames are from September 6, 2026; the table times come from the status JSON’s generated_at field, not screenshot timestamps. The operator and an independent reviewer inspected all six original images. Live child rows, all four parent actions and the first-row selection remained visible; labels were complete. Image hashes matched the retained archive. This verifies repeated real ledger publication and rendering in both themes. It does not prove keyboard opening, a time grant, or the End session action: opening used IPC, and those actions were not activated.

The [runner log](runner.log) retains two jq parse diagnostics during setup. The run is not claimed to have an error-free whole log. Session 84826 exited zero; its cleanup verified original settings/themes, package integrity, active timer, collected temporary unit, absent child sessions and greeter-only state before archiving the verified receipt and clearing active recovery state. The earlier attempt passed only Tokyo Night and stopped during session shutdown; this rerun used a reviewed bounded wait after collecting the owned unit.

Tokyo Night: [549 minutes](bar-152-tokyo-night-0.png), [548](bar-152-tokyo-night-1.png), [547](bar-152-tokyo-night-2.png).

Catppuccin Latte: [547 minutes](bar-152-catppuccin-latte-0.png), [546](bar-152-catppuccin-latte-1.png), [545](bar-152-catppuccin-latte-2.png).

The candidate is still unmerged. Full media capture and merged-main gates remain separate requirements.
