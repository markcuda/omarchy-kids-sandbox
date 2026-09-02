# Dialing in a T2 MacBook (2019 Air, MacBookAir8,2)

T2 Macs run Omarchy — the [`omarchy-t2`](https://github.com/marashiai/omarchy-t2) companion
package proves the path — but four things need attention. Canonical reference:
[wiki.t2linux.org](https://wiki.t2linux.org).

| Thing | State | Fix |
| --- | --- | --- |
| Internal SSD | Works on modern kernels | — |
| Keyboard/trackpad | Work: the Omarchy ISO and install ship `linux-t2` (verified in `omarchy-iso/builder/build-iso.sh` and `install/omarchy-other.packages`, 2026-09-02) | Nothing to do |
| Wi-Fi / Bluetooth | Needs Broadcom firmware; the ISO drops `broadcom-wl` on purpose | Tether or use Ethernet for the install; afterwards run t2linux's `firmware.sh` on the laptop and choose Method 5 (downloads from Apple, no macOS needed) |
| Audio | Model-specific DSP | Optional; low priority for a test box |

Notes:

- [`omarchy-t2`](https://github.com/marashiai/omarchy-t2) targets the 2019 **16" Pro**
  (`MacBookPro16,1`) and refuses other models — read it as prior art, don't run its speaker DSP
  on an Air.
- Fan control: [`omarchy-t2-fan-control`](https://github.com/Endijs/omarchy-t2-fan-control) /
  `t2fanrd`.
- Record what the Air actually needed in this file as we go — that's a contribution the next
  T2 parent will thank us for.
