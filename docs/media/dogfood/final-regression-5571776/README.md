# Parent budget panel on main `5571776`

These original VM screenshots show invented Ben in the parent panel. The selected value changed from 60 to 65 and back to 60 through the real controls, with parent authentication before the first write. The profile and installed readback confirmed both values.

- [Before](panel-before.png): effective 60-minute budget. A separate profile readback established that it was inherited from the age band.
- [Saved 65](panel-65.png): the new value is visible, beside the misleading “Change today’s daily budget” label and “nothing changes” footer. The code writes the recurring weekday `budget_min` setting, distinct from the one-off grant action.
- [Leave confirmation](panel-exit-confirmation.png): after saved edits, the panel says “Nothing has been changed yet.” This extends #191. It shows the confirmation, not a closed panel.

Returning the number to 60 through the panel left an explicit override. Separate cleanup with the installed configuration command removed that override; the profile then matched its original bytes, with effective value 60 and source `band`. The owned panel processes exited and the parent returned to the greeter.

This gallery covers only the parent-settings check. Original VM snapshot and UEFI restoration remain pending; it does not prove the whole final regression is complete. All child names are invented.
