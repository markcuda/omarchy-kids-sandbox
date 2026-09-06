# Installed wizard age default — #166

Source `4fba8f43444249f5ca2e7e68c6106b2012b729e2`, based on main `441ab32`. These are original VM screenshots of the installed wizard, Gum 2.0.0, with real keyboard input and no answers file. Ben is an invented, absent fixture account. The preview was left without Apply.

Both themes show Ages 6–8 selected before any arrow input. Enter advances, Escape returns to the default, and Up explicitly selects Ages 3–5. That younger path reaches No browser and 45 minutes / 19:00. The plan originally said 30 minutes; that was corrected against SPEC.md:125 and the unchanged band data. These frames prove selection and navigation, not provisioning or the full wizard.

The source passed the test-box formatter, the 41-file Mac suite (five skips), the same VM suite (two skips), and scenario 05, including real VM authentication and peer-credential checks. The package was built, verified, and installed on the VM. Root and an independent session inspected the screenshots. Separate restoration readback passed: 181 package files, zero altered; exact installed source hashes and metadata; recorded child settings and themes; active accounting timer; greeter-only state; no temporary live config. Root separately verified the owned preview processes and Ben account/profile were absent.

| Theme | Observed state | Original screenshot |
| --- | --- | --- |
| Catppuccin Latte | Untouched default: Ages 6–8 | [PNG](wizard166-latte-age-untouched.png) |
| Catppuccin Latte | Enter accepts the default | [PNG](wizard166-latte-mode-default.png) |
| Catppuccin Latte | Escape returns to Ages 6–8 | [PNG](wizard166-latte-age-back.png) |
| Catppuccin Latte | Up selects Ages 3–5 | [PNG](wizard166-latte-age-up.png) |
| Catppuccin Latte | Younger path: No browser | [PNG](wizard166-latte-web-young.png) |
| Catppuccin Latte | Younger path: 45 minutes / 19:00 | [PNG](wizard166-latte-time-young.png) |
| Catppuccin Latte | Leave confirmation | [PNG](wizard166-latte-leave-confirm.png) |
| Tokyo Night | Untouched default: Ages 6–8 | [PNG](wizard166-tokyo-fresh-age-untouched.png) |
| Tokyo Night | Enter accepts the default | [PNG](wizard166-tokyo-fresh-mode-default.png) |
| Tokyo Night | Escape returns to Ages 6–8 | [PNG](wizard166-tokyo-fresh-age-back.png) |
| Tokyo Night | Up selects Ages 3–5 | [PNG](wizard166-tokyo-fresh-age-up.png) |
| Tokyo Night | Younger path: No browser | [PNG](wizard166-tokyo-fresh-web-young.png) |
| Tokyo Night | Younger path: 45 minutes / 19:00 | [PNG](wizard166-tokyo-fresh-time-young.png) |
| Tokyo Night | Leave confirmation | [PNG](wizard166-tokyo-fresh-leave-confirm.png) |

Tokyo Night was tested after a fresh parent graphical login. An earlier same-session theme switch reproduced the already-filed stale Gum environment issue #111; those frames are excluded from this selection gallery. The VM Quickshell watcher was re-enabled after login through the reviewed temporary session launcher and its running process was checked. No Air installation, upgrade, reboot, or boot-file changes occurred.

All 30 original screenshots, including navigation, stale-color diagnostics, two initially misnamed Time frames, and the final greeter, are retained privately with hashes and process-identity records. The two Time frames resulted from an invalid single QMP key name `ctrl-c`; the verified `ctrl c` key chord produced the actual Leave confirmation shown here. A legacy Hyprland focus command and a screensaver focus guard also failed safely before wizard input. The portal helper emitted a transient parsing diagnostic before successful session verification. The whole operator log is not claimed error-free.
