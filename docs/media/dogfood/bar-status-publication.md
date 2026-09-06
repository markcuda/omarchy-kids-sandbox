The installed parent bar lost Cy’s live rows while its menu remained open. The first screenshot shows “Give 15 more” and “End session”; the next shows only the two general actions. These are invented VM accounts.

![Before the refresh](https://raw.githubusercontent.com/markcuda/omarchy-kids-sandbox/dogfood/welcome-evidence/docs/media/dogfood/bar-status-before-refresh-tokyo-night-vm.png)

![Rows disappeared](https://raw.githubusercontent.com/markcuda/omarchy-kids-sandbox/dogfood/welcome-evidence/docs/media/dogfood/bar-status-unreadable-tokyo-night-vm.png)

The VM journal confirms FileView reads of `/run/omarchy-kids/status.json` failed with “Permission denied” at 06:09:38 and 06:09:48 EDT on September 6. The latter coincides with the failed final capture. The [ledger publication at lines 146–148](https://github.com/markcuda/omarchy-kids-sandbox/blob/f36210219e9b5ecc0e52644f137c554dbaa2977b/bin/omarchy-kids-time-ledger#L146) renames the replacement inode before applying its final mode and parent group. That ordering creates an unreadable interval. [The bar reader](https://github.com/markcuda/omarchy-kids-sandbox/blob/4d380bcda869a7fde62f7d44f3c018b4f85603ac/share/bar/KidsModule.qml#L46) clears child rows when status cannot be read. The source ordering and actual permission failures strongly support this mechanism; inode metadata was not sampled during the failure. Concurrent writers are not established by this evidence.

Acceptance: prepare complete JSON and final parent-readable permissions before atomically publishing the replacement. On preparation failure preserve the last valid status. Use owned command/fixture tests that inspect permissions at the actual publication boundary and reject a regression to publish-before-permissions. Verify repeated installed updates in both themes with the same Quickshell process and no vanished live rows or FileView permission failures.

This is separate from #140’s missing reload handler and #151’s truncated action labels. The media pass accepted 19 images and rejected this dark bar frame; it did not pass overall. Settings, themes, active timer, and greeter were restored.
