When the parent bar’s status file disappears while “Open Kids Mode” is selected, the menu shrinks to two rows but neither remains highlighted. The same Quickshell process and open menu were used throughout. This is a controlled missing-file scenario with invented VM accounts.

![Last row selected before removal](https://raw.githubusercontent.com/markcuda/omarchy-kids-sandbox/dogfood/welcome-evidence/docs/media/dogfood/bar-selection-before-status-removal-tokyo-night-vm.png)

![Selection disappears after removal](https://raw.githubusercontent.com/markcuda/omarchy-kids-sandbox/dogfood/welcome-evidence/docs/media/dogfood/bar-selection-lost-after-status-removal-tokyo-night-vm.png)

Cause: [reloadStatus’s missing/invalid-input branches](https://github.com/markcuda/omarchy-kids-sandbox/blob/4d380bcda869a7fde62f7d44f3c018b4f85603ac/share/bar/KidsModule.qml#L54) clear liveKids and return before [the cursor correction](https://github.com/markcuda/omarchy-kids-sandbox/blob/4d380bcda869a7fde62f7d44f3c018b4f85603ac/share/bar/KidsModule.qml#L81). The old cursor index is outside the new two-row menu. A parent using the keyboard loses the visible indication of what Enter would select.

Acceptance: keep the cursor on a valid visible row whenever status removes child actions, including missing, empty, and malformed status. Keep missing-data child controls hidden. Exercise the actual reader and key handlers with owned fixtures; inspect last-row → removal → visible selection → arrow movement → Escape in both installed themes without reopening the menu. Do not activate grant/end in this presentation test.

This was found in the named #140 reload scenario and is separate from #152’s status publication permissions. The original reload transitions worked; the cursor check did not pass.
