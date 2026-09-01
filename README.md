# omarchy-kids-setup

The **onboarding wizard and parent/child provisioning** for [Omarchy Kids Mode](https://github.com/markcuda/omarchy-kids-mode).
A spoke of the Kids Mode hub — see [SPOKES.md](https://github.com/markcuda/omarchy-kids-mode/blob/main/SPOKES.md).

**Status: skeleton.** The wizard walks; the provisioning is dry-run by default and marked where
verification is still pending (see the hub's CORE.md build plan, Phase 1).

## What's here

| File | What it does |
| --- | --- |
| `bin/omarchy-kids-wizard` | The five-screen parent setup: who is this for → age → preset → time limits → PIN → apply → safety check |
| `bin/omarchy-kids-check` | Green/red "is it safe?" self-test a parent can read |
| `lib/provision.sh` | The actual changes: kid account, web safety, boot hardening. `DRY_RUN=1` by default |
| `test/verify-phase1.sh` | Collects the facts for the hub's five Phase-1 unknowns; writes a pasteable report |
| `scripts/bringup.sh` | One-time on the test laptop: hostname, sshd, control key |
| `docs/laptop-runbook.md` | Flash → firmware → install → bring-up, step by step |
| `docs/t2-macbook.md` | Dialing in a T2 MacBook (2019 Air tested here) |

## Try it

```bash
git clone https://github.com/markcuda/omarchy-kids-setup && cd omarchy-kids-setup
./bin/omarchy-kids-wizard            # dry run — shows the plan, changes nothing
sudo DRY_RUN=0 ./bin/omarchy-kids-wizard --apply   # on a TEST machine only
```

## Rules

MIT, same as Omarchy. Never collects anything about a child. A way for a kid to get around this
is a bug — report privately per the hub's [SECURITY.md](https://github.com/markcuda/omarchy-kids-mode/blob/main/SECURITY.md).
Not affiliated with DHH, 37signals, or the Omarchy project.
