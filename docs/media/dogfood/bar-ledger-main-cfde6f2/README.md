# Main: live parent-bar ledger updates

Verified main `cfde6f2c11b91fd84362202de17d62e200278402`, using the unchanged installed `831d747` runtime. All 40 test files previously passed on the Mac and VM after the test-box formatter. The private journal checker repair for [#158](https://github.com/markcuda/omarchy-kids-sandbox/issues/158) then passed its own formatter, Mac and VM regression suite before this real-ledger scenario.

The scenario kept the timer active, created one owned temporary child session per theme, invoked the actual ledger tick, and read the published status as the owner. It did not write fixture status JSON. Temporary budget headroom explains the large minute values. Each theme kept one Quickshell process across all three captures; the runner checked the process and child session around each update and checked bounded journal windows for status/FileView permission-denial messages.

| Theme | Minutes | UTC status publication times |
| --- | --- | --- |
| Tokyo Night | 511 → 510 → 509 | 14:46:35, 14:47:00, 14:48:05 |
| Catppuccin Latte | 509 → 508 → 507 | 14:51:16, 14:51:42, 14:52:49 |

All images are from September 6, 2026. Times come from status `generated_at`, not screenshot timestamps. The operator and an independent reviewer inspected all six originals: the child rows, four parent actions and first-row selection stayed readable. This proves repeated real-ledger publication and rendering in both themes. Opening used IPC; keyboard opening, granting time and activating End session were not tested here.

The named run exited zero. A separate readback verified 181 package files with zero altered files, original settings/themes and Wi-Fi metadata, an active timer, a collected temporary unit, greeter-only state, and absent recovery/config files. Two setup jq parse diagnostics remain in the private run log; this is not a claim that the whole log was error-free.

Tokyo Night: [511 minutes](bar-152-tokyo-night-0.png), [510](bar-152-tokyo-night-1.png), [509](bar-152-tokyo-night-2.png).

Catppuccin Latte: [509 minutes](bar-152-catppuccin-latte-0.png), [508](bar-152-catppuccin-latte-1.png), [507](bar-152-catppuccin-latte-2.png).

The earlier main attempt stopped when journal JSON supplied a byte-array message to a string-only checker. Its [failure evidence](../bar-ledger-journal/README.md) is retained. The repaired checker accepts valid byte arrays and rejects malformed records; no application change was needed for #158. Full media capture and video walkthroughs remain separate work.
