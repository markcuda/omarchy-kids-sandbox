# Root-Owned Screen Time

## Goal

Make root the sole authority for screen-time accounting, warnings, grace, locking, and termination so killing or modifying a kid-side process cannot create more time or prevent enforcement.

## Today

The root timer adds one minute for each active session in `bin/omarchy-kids-time-ledger:43-119`. The kid daemon independently calculates remaining time and lights-out state at `bin/omarchy-kids-time:146-191`, starts warning QML at `bin/omarchy-kids-time:97-120`, and therefore decides when enforcement UI appears. `share/time/timesup.qml:43-77` owns the final countdown and invokes finish. `systemd/omarchy-kids-time.timer:5-9` ticks once a minute. Killing the kid daemon removes the decision path.

## Interface

`omarchy-kids-time-ledger tick` remains the root systemd entry point. It becomes a state-machine tick and accounts elapsed active seconds from a monotonic timestamp. Its root-owned state is `/run/omarchy-kids/time/<kid>.json`, `0750 root:omarchy-kids` directory and `0640 root:omarchy-kids` documents. State includes `state`, `reason`, `remaining_seconds`, `grace_deadline`, `last_tick`, `active_seconds_remainder`, and fired warning thresholds.

The states are `allowed`, `warning`, `grace`, and `finishing`. Root alone advances them. At zero budget or lights out, root requests a display-only notice, locks the session, records a 60-second grace deadline, and then invokes the self-resolved sibling `omarchy-kids-exit --finish --kid <account>`. A failed display request does not delay locking or finishing. A failed finish remains `finishing` and is retried on the next tick.

`omarchy-kids-time status` returns validated root state for the current kid or, for root, a named kid. `grant` remains root-only and clears grace only when the resulting budget or schedule permits use. Daily usage and grant ledgers remain integer-minute files; the runtime remainder carries sub-minute accuracy without rewriting historical data.

Kid-side `omarchy-kids-time daemon` becomes a compatibility display adapter. It may read status and ask the shell to show or hide a notice. It never calculates expiry, writes authority state, unlocks, grants, locks, or terminates.

Error modes fail closed at login and during enforcement. Missing or malformed runtime state is rebuilt from root-owned ledgers and profiles. Invalid profile time values block the kid session. `loginctl`, the timer, or finish failures are reported and retried; they never convert the state to `allowed`.

AGENTS.md rule 9 applies to every transition: environment variables and kid-writable files cannot select state paths, clocks, accounts, commands, or root checks. Installed commands resolve their own libraries and siblings, root is determined only by `is_root`, accounts come from root-owned profiles and `loginctl`, and every opened state file is owner, type, mode, and schema checked. Tests use copied build-time paths, never runtime overrides.

## Migration

Ship the state machine reading the current daily usage and grant files, then shorten the systemd timer interval to 30 seconds. The first tick initializes runtime state without adding fabricated time. Accumulated active seconds become whole usage minutes using the retained remainder.

Run the kid display adapter during one compatibility release while moving every decision to root. Then remove decision logic and the finish action from `share/time/timesup.qml`. Existing logged-in sessions may retain the old display until logout, but the root tick becomes authoritative immediately.

`omarchy-kids-assert` re-asserts the service, timer, interval, runtime directory ownership, and ledger ownership. It does not reset usage, grants, grace deadlines, or warning history.

## Requirements

- R-TIMEAUTH-1: Root accounts active time from elapsed seconds and preserves the current integer-minute usage and grant ledgers.
- R-TIMEAUTH-2: Root alone decides warning, grace, lock, and finish transitions for budget and lights-out limits.
- R-TIMEAUTH-3: Enforcement reaches finish after 60 seconds even when every kid-side time or QML process is absent.
- R-TIMEAUTH-4: Display failure and finish failure cannot change an enforcing kid to `allowed`; finish failure is retried.
- R-TIMEAUTH-5: A root grant clears enforcement only when the recomputed policy permits a session.
- R-TIMEAUTH-6: Kid-side time code is display-only and cannot write authoritative state or invoke finish.
- R-TIMEAUTH-7: Assert restores time infrastructure without changing usage, grants, or active enforcement state.

## Tests

`test/shell.d/time-test.sh` uses a fake monotonic clock to prove accumulation, threshold edges, lights out, grant recomputation, restart recovery, lock, deadline, and finish retry. It kills the display adapter before expiry and still observes the fixed finish argv. Service tests verify the 30-second timer.

`test/shell.d/trust-boundary-test.sh` rejects clock, state-path, account, binary, library, and root-check overrides and rejects any finish invocation in kid-side QML or display code.

`test/live/40-time-lights-out.sh` kills the kid display adapter, reaches a limit, proves root lock and termination, and captures `40-root-time-warning.png` and `40-root-time-locked.png`. `test/live/50-ask-grant.sh` grants time from the parent path, verifies root state and resumed access, and captures `50-root-time-granted.png`.

## Out of Scope

This work does not change budget policy, add remote reporting, redesign parent authentication, or make the shell authoritative for time.

## Tickets

1. **Add the root time state machine**
   - Files: `lib/time.sh`, `bin/omarchy-kids-time-ledger`, `test/shell.d/time-test.sh`
   - Acceptance: Deterministic ticks account elapsed active seconds and persist root-owned warning and enforcement state without changing ledger history.
   - Satisfies: R-TIMEAUTH-1, R-TIMEAUTH-2, R-TIMEAUTH-4
2. **Move lock and finish to root**
   - Files: `bin/omarchy-kids-time-ledger`, `bin/omarchy-kids-exit`, `test/shell.d/time-test.sh`, `test/shell.d/exit-test.sh`
   - Acceptance: Root locks at the boundary and finishes after 60 seconds even with the kid display process killed.
   - Satisfies: R-TIMEAUTH-2, R-TIMEAUTH-3, R-TIMEAUTH-4
3. **Reduce the kid path to display**
   - Files: `bin/omarchy-kids-time`, `share/time/timesup.qml`, `test/shell.d/time-test.sh`, `test/shell.d/trust-boundary-test.sh`
   - Acceptance: Kid-side code renders root state and contains no policy transition, state write, unlock, grant, or finish capability.
   - Satisfies: R-TIMEAUTH-6
4. **Re-assert and prove enforcement**
   - Files: `systemd/omarchy-kids-time.timer`, `lib/assert-locks.sh`, `test/shell.d/assert-test.sh`, `test/live/40-time-lights-out.sh`, `test/live/50-ask-grant.sh`
   - Acceptance: Assert restores the timer and modes without altering time state, and VM evidence proves enforcement and grant recovery.
   - Satisfies: R-TIMEAUTH-5, R-TIMEAUTH-7
