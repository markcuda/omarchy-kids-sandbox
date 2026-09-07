# Air first-child login

`setup-safety-stop.png` shows setup reporting a stop during its final safety check. `child-launcher-after-correction.png` shows the child launcher after the reviewed operational correction. Ben is an invented test account.

Separate session logs recorded successful password authentication followed by an immediate exit because private `/tmp` was not mounted noexec. At main `5571776`, `lib/posture.sh:113–114` generated a bare account in the fourth field of `namespace.conf`. Linux-PAM treats that list as exemptions; a leading `~` selects only the listed account for a private namespace.

A guarded, independently reviewed correction changed exactly the two generated selectors. A subsequent real password login reached this launcher. The child process had private noexec `/tmp` and `/dev/shm`; the fresh parent session retained the host mount namespace. Quickshell watching was verified in both sessions.

This proves the operational correction. The permanent source change remains under review and has not completed its ordered gates. These images do not prove the remaining Ask, expiry, Wi-Fi, or return-to-parent journeys.
