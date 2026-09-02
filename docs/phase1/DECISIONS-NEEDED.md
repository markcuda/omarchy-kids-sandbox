# Decisions the loop could not make alone

| Date | Topic | Where | Options |
| --- | --- | --- | --- |
| 2026-09-02 | Pause (fast user switch) cannot use SDDM on Omarchy 4.0.2: a second greeter fails with `HELPER_TTY_ERROR` on both the VM and the laptop | `docs/phase1/V1.md`, issue #2 | (1) start the parent's session on a spare VT through PAM without SDDM, as a new ticket with its own check; (2) ship Pause as lock-and-logout for v1; (3) wait for upstream multi-user. Note: the failed SDDM call also revoked the laptop's input devices until a udev re-trigger, so it is not a safe thing to ship even as a fallback |
