# Installed Wi-Fi check after merging main

Merged main `cfde6f2` passed the test-box formatter, all 40 Mac test files, and all 40 VM test files in order. This installed UI scenario then passed in Tokyo Night and Catppuccin Latte. The installed package's runtime files are identical to the merged source.

The picker used an owned fixture client with invented HomeNet/OpenNet networks. This checks the installed QML, input delivery and recovery; it does not prove real wireless association, NetworkManager policy, or authorization through the original Wi-Fi client.

Both themes passed empty-list retry by keyboard and pointer, readable scan and join errors, masked password input, Escape-back, empty password on reopening, protected retry, and open-network joining with zero password bytes. Holding scans and joins while pressing Enter twice more produced one operation each. The fixture received exactly one expected password line followed by EOF. Its [42 action records](fixture-actions.log) retain the extra light-theme setup join separately.

The picker PID stayed fixed within each theme: dark `456603`, light `479918`. After each final Escape, a separate process-absence check passed before any close helper, theme switch or cleanup. Root inspected all 25 original pictures; independent review inspected the interaction evidence.

The [controller and restoration log](capture-and-restoration.log) belongs to a run that exited zero. The [separate final readback](final-readback.log) also exited zero: 181 package files, zero altered files; original Wi-Fi bytes, ownership, mode and timestamp; original themes and time settings; Wi-Fi band/parent setting; active timer; collected test unit; greeter with no child session; and no active recovery receipts or temporary live config. No timestamp repair was needed. The log retains the theme setter's deferred-reload notice; the subsequent login and pictures establish the new theme.

Known issues remain: #148 clears the successful join message during automatic refresh, and #91 leaves a missing Tux Paint tile visible behind the modal. Completion pictures below show the refreshed list; successful completion is established by the action log, not a visible confirmation message.

| State | Tokyo Night | Catppuccin Latte |
| --- | --- | --- |
| Empty list | [Picture](wifi-main-dark-empty.png) | [Picture](wifi-main-light-empty.png) |
| Held scan | [Picture](wifi-main-dark-loading.png) | [Picture](wifi-main-light-loading.png) |
| Keyboard retry | [Picture](wifi-main-dark-keyboard-retry.png) | [Picture](wifi-main-light-keyboard-retry.png) |
| Scan error | [Picture](wifi-main-dark-error.png) | [Picture](wifi-main-light-error.png) |
| Network list | [Picture](wifi-main-dark-networks.png) | [Picture](wifi-main-light-networks.png) |
| Masked password | [Picture](wifi-main-dark-password.png) | [Picture](wifi-main-light-password.png) |
| Escape back | [Picture](wifi-main-dark-back.png) | [Picture](wifi-main-light-back.png) |
| Reopened empty password | [Picture](wifi-main-dark-reopen-empty.png) | [Picture](wifi-main-light-reopen-empty.png) |
| Join error | [Picture](wifi-main-dark-join-error.png) | [Picture](wifi-main-light-join-error.png) |
| Held join | [Picture](wifi-main-dark-joining.png) | [Picture](wifi-main-light-joining.png) |
| Protected join returned to list | [Picture](wifi-main-dark-protected-complete.png) | [Picture](wifi-main-light-protected-complete.png) |
| Open join returned to list | [Picture](wifi-main-dark-open-complete.png) | [Picture](wifi-main-light-open-complete.png) |

An [initial light-theme empty state](wifi-main-initial-empty.png) was also captured before the two full passes. [SHA256SUMS](SHA256SUMS) records the unchanged originals and evidence files.
