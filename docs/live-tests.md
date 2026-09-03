# The VM acceptance harness: `test/live/`

SPEC.md R-BUILD-3, the V1-V7 checks (§7), and the §8 acceptance list. Issue #31.

`test/live/` runs from the developer's own machine and drives the test laptop's VM over SSH and
QMP — the same recipe docs/vm.md, docs/laptop-runbook.md, and the reference drivers under
`scripts/` (`v1-two-sessions.sh`, `v6-limine.sh`) already use. It is not a unit test suite: it is
a set of scenario scripts, each one a slice of §8's acceptance list, that build the real package,
install it on the real VM, and drive real logins through real QMP keystrokes. Nothing in here runs
in CI (there is no VM there); `test/all`/CI only runs the pure parts, in
`test/shell.d/live-lib-test.sh`.

## Setup, on a fresh laptop

1. Follow `docs/laptop-runbook.md` end to end: firmware, the stock install, Tailscale, the
   `test/verify-phase1.sh` sanity pass.
2. Build the VM once with `scripts/vm-build.sh` (see `docs/vm.md`) — an encrypted 40G disk with a
   `cidata` drive answering the installer unattended, owner account `kid-vm`, password `omarchy`
   by default.
3. Run `scripts/vm-run.sh install` to install the stock ISO into that disk, then
   `scripts/vm-run.sh boot` once by hand and confirm you can `ssh -p 2222 kid-vm@127.0.0.1` from
   the laptop.
4. On your own machine, add the `air`/`vm` Host aliases docs/vm.md's "Driving it from the Mac"
   section shows (either to `~/.ssh/config` or a separate file — either way, point
   `LIVE_SSH_CFG` at it).
5. `cp test/live/config.env.example test/live/config.env` and fill it in: the ssh config path,
   the owner's password, and the persistent test kid's account/name/password. If the VM has no
   kid provisioned yet, provision one by hand first (`docs/provision.md`) or run
   `bash test/live/60-wizard-easy.sh` once and copy what it creates into `LIVE_KID1_*`.
6. `bash test/live/10-cold-boot-kid.sh` on its own first, to confirm the whole chain (build,
   install, boot, QMP, ssh) actually works before trusting `all`.

`config.env` is gitignored on purpose (it holds test-box passwords) — `config.env.example` is the
checked-in template; nothing under `test/live/out/` (screenshots, `report.md`) is committed
either.

## Running it

```text
bash test/live/all          # every scenario, in order, stops at the first FAIL
bash test/live/all -k       # keep going after a FAIL instead of stopping
bash test/live/30-portal-login-and-finish.sh   # any single scenario, on its own
```

Every scenario is idempotent: run it once, run it twice in a row, get the same result either way
(the exceptions are called out below). `test/live/all` writes `$LIVE_OUT_DIR/report.md` — a
Markdown table of scenario, PASS/FAIL, and the screenshots it took — plus the screenshots
themselves, all under `test/live/out/` by default.

## Safety rules

These are AGENTS.md's rules, restated for this specific harness:

- **Never reboot the laptop itself.** Every scenario's `boot_with`/`portal_reset` operates on the
  VM only, through `scripts/vm-run.sh`/`scripts/vm-qmp.sh` run *inside* an `air '...'` ssh call —
  never a bare `reboot`/`shutdown` on `air` itself. The VM is only ever stopped with
  `vm-run.sh stop` (ACPI powerdown), never a hard `quit` — docs/vm.md notes a quit right after a
  disk write has, once, left zero-length files.
- **Test users only.** `LIVE_KID1_*` and `LIVE_WIZARD_KID_*` name test fixtures on a test VM's
  disk, never a real child (AGENTS.md rule 9) — the defaults (`Cy`, `Ada`) are the repo's own
  placeholder names, not anyone's.
- **Nothing here writes to this machine's own `/etc`** (AGENTS.md rule 8): every real write
  happens on the VM, as root, only through `vmroot`'s explicit `sudo`, fed a password on stdin,
  never on argv or in a log line.
- **90-remove's real (non-dry-run) step is gated on `LIVE_DESTRUCTIVE=1`.** Its dry-run half
  always runs and never writes anything; the real half only ever removes the *wizard-made* kid
  (never `LIVE_KID1_ACCOUNT`) — see that scenario's own header comment for why
  `omarchy-kids-remove` itself is never run for real here.

## What each scenario checks

| Script | §8 item | What it does |
| --- | --- | --- |
| `10-cold-boot-kid.sh` | 2 (second half) | Boots with the test kid's disk password; expects straight into that kid's `omarchy-kids` session. |
| `20-cold-boot-owner.sh` | 2 (first half) | Boots with the owner's disk password; expects the owner's own desktop, no kid session (R-BOOT fail-safe). |
| `30-portal-login-and-finish.sh` | 3 | From the portal: navigate to the kid's tile, log in, triple-tap Super, Finish with the parent password, confirm the portal comes back. |
| `40-time-lights-out.sh` | 5 | Sets `lights_out` in the past, logs the kid in, confirms the Time's Up overlay auto-Finishes with no answer. |
| `50-ask-grant.sh` | 6 | `omarchy-kids-ask time 15` from the kid's session, approved on the spot with the parent password, confirms the ledger reflects the grant. |
| `60-wizard-easy.sh` | 1 | Drives the Easy wizard's fifteen screens over `ssh -tt` with an answers file, Applies for real, cold boots as the kid it provisions. |
| `90-remove.sh` | 8 | `omarchy-kids-remove --dry-run` (always); under `LIVE_DESTRUCTIVE=1`, a real `omarchy-kids-provision remove` of just the wizard kid. |

Not covered yet: §8 items 4 (browser walled garden / DoH), 7 (`omarchy update` + a kernel update),
and 9 (changing the parent's login password) — each needs its own scenario and its own care about
what state it leaves the VM in; left for a follow-on issue rather than guessed at here.

## How to add a scenario

1. Pick the next free `NN` (leave gaps between the existing numbers if you expect to insert one
   later — the loop in `test/live/all` just globs `[0-9][0-9]-*.sh` in sort order, no registry to
   update).
2. Start from an existing scenario closest in shape to what you're adding (`10-cold-boot-kid.sh`
   for a boot-and-check; `30-portal-login-and-finish.sh` for anything that logs a kid in first).
3. `source "$DIR/lib.sh"` at the top, same as every other scenario, and end with exactly one call
   to `scenario_result "<script-name-without-.sh>"` — that's what emits the `PASS`/`FAIL` line
   `test/live/all` parses into the report.
4. Use `ok "<label>"`/`fail "<label>"` for each assertion inside the scenario (same contract as
   `test/shell.d`'s own `check()` functions), and `check GOT WANT LABEL` when you're comparing two
   values directly.
5. Every wait should be one of the `assert_*` helpers (a polling loop with a deadline) rather than
   a fixed `sleep`, unless the thing you're waiting on genuinely isn't pollable yet (the ~35s
   before the disk prompt is the one case in `lib.sh` itself — there's no ssh and no QMP query
   that reports "the disk prompt is up").
6. If it needs a screenshot, call `shot "<name>"` and let its own `echo "<name>.png"` reach
   `test/live/all`'s report — don't redirect or re-echo it yourself.
7. If any pure logic in it (index math, string parsing, anything with no ssh call in it) is worth
   testing without the VM, add cases to `test/shell.d/live-lib-test.sh` rather than a new test
   file — that's the one place `test/all`/CI actually exercises this directory.
8. Run the new scenario on its own against the real VM before adding it to a PR, and run it twice
   in a row to confirm it's actually idempotent.

## Known gaps, read before trusting a run

- **`portal_login`'s navigation math is read from `share/sddm-theme/Main.qml`'s source, not yet
  confirmed live with more than two kid tiles.** `lib.sh`'s own comment on `portal_login` has the
  full reasoning (the Left/Right clamp, the "overshoot Left, then Right to the target index"
  trick) and the citation.
- **`portal_reset` uses `SwitchToGreeter`** (the same D-Bus call V1 verified — docs/phase1/V1.md),
  which puts a fresh greeter on screen without logging out whatever session is already running
  underneath. That's fine for what these scenarios check (they only look at the greeter and at
  the specific kid's session state), but it means a scenario that runs after a crashed prior run
  may find an extra, orphaned session still resident — `state` (called on most failures) will show
  it if so.
- **`50-ask-grant.sh`'s in-session command** (harvesting the launcher process's Wayland/D-Bus
  environment to run `omarchy-kids-ask` "as" the kid) is the same technique docs/ask.md's own
  "Verified live" section used — it hasn't been re-verified against this exact harness script yet.
