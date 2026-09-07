# QMP typing drops the colon

During the installed #170 candidate preview at 598a82f8bd6942e5444bbb51c3013dbba35ae4fa, sending `21:00` through the VM QMP text helper produced `2100`. The screenshot caught this before submission. Two Left presses followed by Shift+semicolon inserted the colon into the existing value. The corrected `21:00` was inspected before Enter.

| Failed text entry | Corrected field |
| --- | --- |
| [2100](latte-weekend-bedtime-entered.png) | [21:00](latte-weekend-bedtime-corrected.png) |

These are original Catppuccin Latte VM screenshots at 1280×800. This was a dry-run preview; Apply was never selected. Ben is an invented fixture. The fault is in the harness, separate from the wizard's weekend-limit labels.

The [helper](https://github.com/markcuda/omarchy-kids-sandbox/blob/069c584d2733a233ee3fd6f84c2a4cbcc8c2bb27/scripts/vm-qmp.sh#L23-L30) has no colon mapping and sends an unlisted character as a raw qcode. Its [response handling](https://github.com/markcuda/omarchy-kids-sandbox/blob/069c584d2733a233ee3fd6f84c2a4cbcc8c2bb27/scripts/vm-qmp.sh#L6) does not reject QMP error objects. This source matches the reviewed live helper SHA-256 e81011f402abd4b97af5db54f206593a2117e2010d7ad688daf1ea458977ece3. The captured frames prove the omitted colon and correction; no original QMP error payload was retained. [Original checksums](SHA256SUMS).
