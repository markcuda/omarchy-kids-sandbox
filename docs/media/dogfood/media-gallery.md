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

Eleven inspected Air frames use the exact #143 source `eaa8cd1`, with only three client paths
replaced by an owned fixture backend. The real Air preview used Quickshell 0.3.1 with source
watching enabled. These frames document the empty and error states, retry through loading, list
refresh, password and busy states, Escape back, and the light-theme list and password. They do not claim a
real Wi-Fi join or password validation; duplicate Enter produced one fixture join. The preview
closed, its process was absent, and Tokyo Night was restored. Formatter, Mac, VM, and named
installed-live gates remain pending.

| State | Tokyo Night | Catppuccin Latte | Evidence |
| --- | --- | --- | --- |
| Empty | ![Wi-Fi empty, dark](wifi-143-empty-tokyo-night-air.png) | ![Wi-Fi empty, light](wifi-143-empty-catppuccin-latte-air.png) | No networks found; retry guidance |
| Error | ![Wi-Fi error, dark](wifi-143-error-tokyo-night-air.png) | ![Wi-Fi error, light](wifi-143-error-catppuccin-latte-air.png) | Error state with retry |
| Loading / watched list | ![Wi-Fi loading, dark](wifi-143-loading-pointer-tokyo-night-air.png) ![Wi-Fi watched list, dark](wifi-143-watched-networks-tokyo-night-air.png) | — | Pointer retry loads; source-watch refreshes the list |
| Password / busy | ![Wi-Fi password, dark](wifi-143-password-tokyo-night-air.png) ![Wi-Fi busy, dark](wifi-143-busy-tokyo-night-air.png) | ![Wi-Fi password, light](wifi-143-password-catppuccin-latte-air.png) | Masked input and joining state |
| Back | ![Wi-Fi back, dark](wifi-143-back-tokyo-night-air.png) | — | Escape returns and closes |
| Networks | — | ![Wi-Fi networks, light](wifi-143-networks-catppuccin-latte-air.png) | Light-theme list and join guidance |

## #136 merged-main Wi-Fi receipts

The merged-main source `f28a461` completed its post-merge gate. These two VM frames show settled
empty scans in Tokyo Night and Catppuccin Latte with no fabricated network; no Wi-Fi join was
attempted. The original themes and client bytes were restored after the run.

| Tokyo Night | Catppuccin Latte |
| --- | --- |
| ![Merged-main empty scan, dark](wifi-main-tokyo-night-vm.png) | ![Merged-main empty scan, light](wifi-main-catppuccin-latte-vm.png) |

## #145 Air password-delivery preflight

Exact source `451ffa7` ran in one watched Air Quickshell process with an owned fixture backend.
Protected joins delivered the expected harmless password line and EOF on the first attempt,
after a deliberate failure and retry, and in Catppuccin Latte. Busy duplicate Enter produced
one invocation. Corrected open fixtures accepted no password flag or input in both themes.
The earlier open fixture that incorrectly required child read/EOF behavior failed; its
mislabeled success image is excluded. Backend checks establish delivery and invocation counts;
these six images show the corresponding UI states. No real network join or real credential
was used. The process closed and Tokyo Night was restored. Ordered full gates and named
installed-live acceptance remain pending for [#145](https://github.com/markcuda/omarchy-kids-sandbox/issues/145)
and media integration `bcf8b42`.

| State | Tokyo Night | Catppuccin Latte | Evidence |
| --- | --- | --- | --- |
| Protected input and result | ![Intentional backend failure after password delivery](wifi-145-first-delivery-error-tokyo-night-air.png) ![List restored after verified protected retry](wifi-145-retry-success-tokyo-night-air.png) | ![Masked fixture password](wifi-145-protected-catppuccin-latte-air.png) ![List restored after verified protected join](wifi-145-protected-success-catppuccin-latte-air.png) | First delivery, intentional failure, retry, and light protected delivery checked by the backend |
| Open result | ![List after verified open fixture result, dark](wifi-145-open-verified-tokyo-night-air.png) | ![List after verified open fixture result, light](wifi-145-open-verified-catppuccin-latte-air.png) | Corrected fixture checked no password flag or input; both returned success |

## #148 Air joined-feedback preflight

Exact source `8294246` ran in watched Air process `1230897` with an owned fixture backend.
These seven inspected frames show network-specific success surviving list refresh, scan errors
replacing success, and manual retry clearing the message. No real Wi-Fi join or real credential
was used. The preview closed, its process was absent, and Tokyo Night was restored.
[#148](https://github.com/markcuda/omarchy-kids-sandbox/issues/148) is separate from media
candidate `bcf8b42`; its ordered full gates and named installed-live acceptance remain pending.

| State | Tokyo Night | Catppuccin Latte |
| --- | --- | --- |
| Protected result | ![Joined HomeNet after refresh, dark](wifi-148-protected-joined-tokyo-night-air.png) | ![Joined HomeNet after refresh, light](wifi-148-protected-joined-catppuccin-latte-air.png) |
| Open result | ![Joined OpenNet after refresh, dark](wifi-148-open-joined-tokyo-night-air.png) | ![Joined OpenNet after refresh, light](wifi-148-open-joined-catppuccin-latte-air.png) |
| Failed scan | ![Scan error replaces success, dark](wifi-148-refresh-error-tokyo-night-air.png) | ![Scan error replaces success, light](wifi-148-refresh-error-catppuccin-latte-air.png) |
| Manual retry | Not captured | ![Manual retry clears success, light](wifi-148-retry-cleared-catppuccin-latte-air.png) |
