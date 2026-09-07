# Air setup: stale authd parent identity

The real Air setup stopped at Step 2 after the owner entered the valid parent password. The screen says “That wasn't it. Try again.” A separate `sudo -k -S -v` check accepted the same credential, so this was not a password or libcrypt failure.

The active authd service override passed `--parent kid-test`, while the authenticated owner had a different account name. `bin/omarchy-kids-authd:233` rejects bootstrap authentication when a configured parent does not equal the kernel-authenticated caller. The override is operational stale state; no product source change is included here.

Acceptance is a fresh owner setup reaching Step 3 after the stale override is corrected, while an incorrect owner password still fails closed. The screenshot is evidence for the reported failure only; it does not claim the correction or a complete setup run.
