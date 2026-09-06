# Real laptop setup preview, September 6

The installed CLI was opened with `--dry-run` in an owned foot terminal. Keyboard input advanced through Welcome, a dummy parent password, the invented name Test, and Face. Escape returned to Name. Ctrl+C and the visible Leave setup confirmation closed the preview; its terminal and transient unit were verified gone. No Apply or account creation was performed. This is CLI preview evidence, not a desktop-entry or completed setup walkthrough.

- [Face picker](face-names-only.png): all twelve animal names are listed, but none of the portraits are visible. A parent and child cannot compare the faces they are choosing. Appendix A4 specifies twelve avatars.
- [Back to Name](name-cleared-after-back.png): the name field is empty after Escape from Face, which had displayed “Pick Test’s face.” The parent must enter the name again.

The installed `wizard-screens.sh` matches current main. Its Face implementation creates text-only labels; its Name screen does not provide the saved name to the input renderer. The installed `tui.sh` is older than main; current main also creates the input without a saved value. These findings concern the choice content and retained input, not terminal styling. Root and an independent session inspected both images.
