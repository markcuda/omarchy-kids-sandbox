# Real media captures, September 6

Fourteen screenshots from one VM run, viewed by the driving session. The run failed acceptance: wizard, panel, and bar captures did not pass. These are evidence of the current experience, including open defects. No app launch, request approval, or Wi-Fi join is claimed.

| Surface | Tokyo Night | Catppuccin Latte | Findings from this capture |
| --- | --- | --- | --- |
| Portal | ![Portal, dark](media-observed-portal-tokyo-night.png) | ![Portal, light](media-observed-portal-catppuccin-latte.png) | [#112](https://github.com/markcuda/omarchy-kids-sandbox/issues/112), [#128](https://github.com/markcuda/omarchy-kids-sandbox/issues/128) |
| Launcher | ![Launcher, dark](media-observed-launcher-tokyo-night.png) | ![Launcher, light](media-observed-launcher-catppuccin-latte.png) | [#91](https://github.com/markcuda/omarchy-kids-sandbox/issues/91) |
| Exit card | ![Exit card, dark](media-observed-exit-modal-tokyo-night.png) | ![Exit card, light](media-observed-exit-modal-catppuccin-latte.png) | [#118](https://github.com/markcuda/omarchy-kids-sandbox/issues/118) |
| Ask a grown-up | ![Ask a grown-up, dark](media-observed-ask-tokyo-night.png) | ![Ask a grown-up, light](media-observed-ask-catppuccin-latte.png) | [#131](https://github.com/markcuda/omarchy-kids-sandbox/issues/131) |
| Time’s Up | ![Time’s Up, dark](media-observed-times-up-tokyo-night.png) | ![Time’s Up, light](media-observed-times-up-catppuccin-latte.png) | [#137](https://github.com/markcuda/omarchy-kids-sandbox/issues/137) |
| Wi-Fi | ![Wi-Fi, dark](media-observed-wifi-picker-tokyo-night.png) | ![Wi-Fi, light](media-observed-wifi-picker-catppuccin-latte.png) | [#136](https://github.com/markcuda/omarchy-kids-sandbox/issues/136) |
| More apps | ![More apps, dark](media-observed-plugins-shelf-tokyo-night.png) | ![More apps, light](media-observed-plugins-shelf-catppuccin-latte.png) | [#117](https://github.com/markcuda/omarchy-kids-sandbox/issues/117) |

The failed parent surfaces have their own evidence: [missing wizard/panel](https://github.com/markcuda/omarchy-kids-sandbox/issues/139), [stale bar](https://github.com/markcuda/omarchy-kids-sandbox/issues/140). [Progress](../../../PROGRESS.md) records the remaining gates and cleanup checks.

## #143 Air Wi-Fi picker evidence

Ten inspected Air frames use the exact #143 source `eaa8cd1`, with only three client paths
replaced by an owned fixture backend. The real Air preview used Quickshell 0.3.1 with source
watching enabled. These frames document the empty and error states, retry through loading, list
refresh, password and busy states, Escape back, and the light-theme list. They do not claim a
real Wi-Fi join or password validation; duplicate Enter produced one fixture join. The preview
closed, its process was absent, and Tokyo Night was restored. The settled light-theme password
frame is held pending replacement after a focus race; formatter, Mac, VM, and named installed-live
gates remain pending.

| State | Tokyo Night | Catppuccin Latte | Evidence |
| --- | --- | --- | --- |
| Empty | ![Wi-Fi empty, dark](wifi-143-empty-tokyo-night-air.png) | ![Wi-Fi empty, light](wifi-143-empty-catppuccin-latte-air.png) | No networks found; retry guidance |
| Error | ![Wi-Fi error, dark](wifi-143-error-tokyo-night-air.png) | ![Wi-Fi error, light](wifi-143-error-catppuccin-latte-air.png) | Error state with retry |
| Loading / watched list | ![Wi-Fi loading, dark](wifi-143-loading-pointer-tokyo-night-air.png) ![Wi-Fi watched list, dark](wifi-143-watched-networks-tokyo-night-air.png) | — | Pointer retry loads; source-watch refreshes the list |
| Password / busy | ![Wi-Fi password, dark](wifi-143-password-tokyo-night-air.png) ![Wi-Fi busy, dark](wifi-143-busy-tokyo-night-air.png) | — | Masked input and joining state |
| Back | ![Wi-Fi back, dark](wifi-143-back-tokyo-night-air.png) | — | Escape returns and closes |
| Networks | — | ![Wi-Fi networks, light](wifi-143-networks-catppuccin-latte-air.png) | Light-theme list and join guidance |
