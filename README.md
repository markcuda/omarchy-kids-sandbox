# omarchy-kids-setup

Onboarding and host locks for [Omarchy Kids Mode](https://github.com/markcuda/omarchy-kids-mode).
A spoke of the Kids Mode hub.

**Status: prototype.** Dry-run by default.

## Model

One desktop Unix user. Two passwords:

- **Parent password** is the account password in `/etc/shadow`. Sudo, `omarchy-dns`, and the real `$HOME`.
- **Kid password** is a separate hash in `/etc/omarchy-kids/kid.passwd`. SDDM accepts it, then `omarchy-kids-dispatch` starts a bubblewrap session that binds `/var/lib/omarchy-kids/home` over `$HOME`. Parent files are not there. `export HOME=` does not get them back.

System bus inside the kid session is filtered (no NetworkManager, no systemd-resolved). Join Wi-Fi with `omarchy-kids-wifi SSID`. That helper runs on the host via pkexec and forces `ignore-auto-dns`. Family DNS stays on systemd-resolved. Stock Omarchy's passwordless `omarchy-dns` sudoers is overridden so Cloudflare/Google/DHCP need the parent password.

This is a mount namespace, not a second user and not Docker.

## Try it

```bash
./test/gaps.sh
./bin/omarchy-kids-wizard            # dry run
sudo ./bin/omarchy-kids-wizard --apply   # TEST machine only
```

## Rules

MIT, same as Omarchy. Never collects anything about a child. A way for a kid to get around this is a bug — report privately per the hub's SECURITY.md. Not affiliated with DHH, 37signals, or the Omarchy project.
