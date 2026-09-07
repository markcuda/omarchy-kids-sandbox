# Portal setup, candidate 41f4777

Original, unedited VM screenshots from September 7, 2026, under Catppuccin Latte, 1280×800. All children are invented fixtures. Installed source `41f47776313481db65e29166d59fbf2366db8753` fixes #187; package SHA-256 `b6d592020c445495fff8487745359ab90e4a8f65493d74d62631cd0109735fde`.

The actual parent setup created Ben (Fox, ages6–8, Simple defaults) and passed all five Apply steps. A separate readback confirmed the account, profile and portal entry. Ben then logged in using the configured test password; the launcher opened GCompris through Enter, its first-run screens reached the activity menu, Super+Q returned to the launcher, and the parent-authenticated Finish action returned to the portal. A fresh parent login and clean logout completed the round trip. Watching was verified in the actual parent, launcher and exit Quickshell processes.

| Image | What it shows |
| --- | --- |
| [setup-done.png](setup-done.png) | Successful Apply. The footer still falsely says nothing changes when leaving; creation already happened. |
| [launcher.png](launcher.png) | Ben's newly provisioned desktop; Tux Paint is marked not installed yet (existing #52). |
| [gcompris.png](gcompris.png) | GCompris activity menu after dismissing first-run prompts; no individual activity was played. |
| [exit.png](exit.png) | The actual Finish dialog before parent authentication. |
| [parent-return.png](parent-return.png) | Fresh parent desktop after the child's Finish and a separate parent login. Finish itself returns to the portal. |
| [greeter.png](greeter.png) | Clean final greeter, with Ben deliberately preserved until the scheduled snapshot restoration. |
| [open-child-selected.png](open-child-selected.png) | The offered Open Ben's desktop action was selected after successful setup. |
| [open-child-result.png](open-child-result.png) | That action only closed the wizard and left the parent desktop visible, extending #188. |
| [transient-manifest-errors.png](transient-manifest-errors.png) | Normal profile construction prints unresolved-field and rebuild errors before later succeeding. |

These pictures do not prove snapshot restoration. The original qcow2 snapshot and separate UEFI backup remain protected for the final restoration window. #189's incorrect disk-password claim and #188's misleading Done behavior remain unresolved by this narrowly scoped account fix. Source and live acceptance are recorded separately from merged-main gating.
