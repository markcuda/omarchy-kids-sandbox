# Review 4 — Codex (gpt-5.6-luna, high), the maintainer's eye again

Headless `codex exec -s read-only` over main @ 129aec7 on 2026-09-03, prompted as an Omarchy
maintainer deciding whether to bless the repo. Verbatim below; triage and tickets follow in
issues #59-#63.

I would not bless this checkout yet.

1. high — `bin/omarchy-kids-session:16-24,98-129`; `bin/omarchy-kids-session-start:18-26,63-73` — Kid-controlled environment variables select profiles, levels, configs, QML, and policy paths. Fix: remove live path overrides and retain only build-time substitutions in test copies.

2. high — `bin/omarchy-kids-session-start:80-126,143-176`; `share/launcher/shell.qml:89-105,167-182` — A kid-writable JSON file supplies `tile.exec`, which is executed through `sh -c`; desktop lookup also reaches kid-controlled entries. Fix: map validated tile IDs to fixed absolute argv arrays and eliminate shell evaluation.

3. high — `bin/omarchy-kids-session-start:198,225`; `bin/omarchy-kids-ask:116`; `bin/omarchy-kids-time:101,116`; `bin/omarchy-kids-wifi:75,179` — Kid-controlled `PATH` can replace `quickshell`. Fix: invoke `/usr/bin/quickshell` or a build-time absolute path.

4. high — `bin/omarchy-kids-session:168-178` — The noexec check trusts `$HOME`, so a kid can check a different mount while their real home remains executable. Fix: derive the home from `getent passwd "$(id -un)"` and verify that exact mount.

5. high — `bin/omarchy-kids-session:181-194` — Missing `/tmp` noexec is only a warning, and `/dev/shm` is never checked, enabling executable downloads outside home. Fix: fail closed and verify both private mounts are `nosuid,nodev,noexec`.

6. high — `bin/omarchy-kids-session:197-209` — Login preflight checks only `tty2`; an unmasked `tty3`–`tty6` remains a shell login path. Fix: require every `getty@tty2..tty6.service` to be masked.

7. high — `lib/assert-locks.sh:73-87` — `groups_ok` checks required groups but permits extra groups such as `wheel` or `docker`. Fix: compare supplementary groups against an exact allowlist and remove or fail on extras.

8. high — `bin/omarchy-kids-session-start:227-235`; `share/menu/omarchy-kids-trimmed.jsonc:4-13` — Level 2 starts the full Omarchy shell while the allowlist is inert and the menu schema is explicitly unverified, so app restrictions are bypassable. Fix: wire a verified root-owned menu filter or keep Level 2 out of the unrestricted shell.

9. high — `bin/omarchy-kids-web:15,78-84,267-289` — `OMARCHY_KIDS_SHARE` selects Chromium’s launch-flags file, allowing removed switches such as extension loading to be reintroduced. Fix: use the packaged flags path and accept only a hardcoded flag allowlist.

10. high — `bin/omarchy-kids-session-start:248-253`; `bin/omarchy-kids-time:146-191`; `bin/omarchy-kids-time-ledger:103-119` — Screen-time enforcement runs in the kid’s process and the root ledger never terminates the session; the kid can kill the daemon or overlay. Fix: enforce budget and lights-out termination from the root timer.

11. medium — `bin/omarchy-kids-ask:466-483,492-564` — `list`, `approve`, and `decline` lack entry-point root checks; any kid can read sibling requests, and authorization fails only later at filesystem writes. Fix: require `is_root` at the start of every root-only subcommand.

12. medium — `test/shell.d/trust-boundary-test.sh:42-67` — The trust test declares runtime path variables safe even though production code uses them for security decisions, so it does not catch the actual redirect attacks. Fix: use build-time substitutions and add hostile-environment regression cases.

13. medium — `bin/omarchy-kids-provision:127-143,194-200` — Provisioning writes a guessed, explicitly unverified Omarchy migration format when the upstream helper is unavailable. Fix: require or verify `omarchy-provision-user`; do not write guessed state.

14. medium — `share/hyprland/L3.lua:21-61` — The Level 3 removal of terminal and passwordless-sudo behavior is explicitly based on unverified bindings. Fix: verify Omarchy 4.0.2 bindings and assert the resulting restrictions before shipping.

15. low — `bin/omarchy-kids-parent-auth:22-24` — It duplicates the package’s root check instead of using the mandated shared helper. Fix: centralize the check in `lib/kids.sh` or a shared root helper.

16. low — `PKGBUILD:22-32` — Dependency rationale is too long for a package recipe and mixes audit prose with packaging logic. Fix: keep short dependency comments and move the explanation to `docs/packaging.md`.

Three fixes first: remove runtime path/environment trust; replace the launcher’s raw command execution; move screen-time enforcement into the root timer.