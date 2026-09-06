# Issue #137 implementation brief: tonight-only lights-out approval

## Goal

Make the Time’s Up approval honest and useful when the root state says
`reason=lights-out`, while preserving ordinary daily budget grants. The
extension applies only to the current logical day, whose boundary is 04:00.

## Contracts

The root runtime document remains the authority. It already publishes
`state`, `reason`, `remaining_seconds`, `logical_day`, `last_tick`,
and `grace_deadline`.

A time request gains two optional fields:

- `scope`: `budget`, `lights-out`, or `both`.
- `logical_day`: the root logical day observed by the Time’s Up surface.

Existing records with no `scope` remain `budget` requests. Existing budget
grant behavior and queue records remain compatible.

The producer chain is:

1. `share/time/timesup.qml` reads the validated root state. It supplies the
   observed day and a scope hint when opening `omarchy-kids-ask`.
2. `bin/omarchy-kids-ask` carries the fields through its modal, immediate
   GRANT request, and Ask-later outbox record.
3. `lib/ask.py` validates the field shapes and preserves them in JSON records.
4. `bin/omarchy-kids-authd` forwards the validated request to the root apply
   path.
5. `bin/omarchy-kids-ask apply_record` dispatches the root time action.

The consumer chain is:

- `bin/omarchy-kids-time` exposes a root-only
  `extend-lights-out <kid> <minutes> --day <logical_day>` action.
- `lib/time.sh` reads a root-owned per-day lights-out deadline.
- `bin/omarchy-kids-time-ledger` uses the effective deadline for the next
  grace decision.

The kid-provided scope is never authoritative. The root apply path re-reads
the current runtime state and profile, confirms the requested day is still
current for a new tonight request, and derives the effective action:

- budget expiry -> `budget`;
- lights-out expiry with positive budget remaining -> `lights-out`;
- lights-out expiry with budget also exhausted -> `both`;
- a new `lights-out` or `both` request outside `grace`/`finishing` -> stale
  request failure.

Legacy requests with absent `scope`, and ordinary `budget` requests, retain
their existing behavior and may be approved before a Time’s Up state exists.
Only the new tonight-specific scopes require the current lights-out state.

A request cannot turn a changed or already-resolved state into an approval.

## Tonight-only state

Store new tonight approvals per kid in a root-owned atomic record such as
`/var/lib/omarchy-kids/<kid>/usage/<logical-day>.tonight.json`. It contains
the absolute wall-clock lights-out deadline and any budget contribution from
that approval. The logical-day filename makes expiry at 04:00 automatic; the
ledger ignores records for older logical days. Existing integer
`<logical-day>.grant` files remain valid and readable for ordinary budget
grants.

At approval time, recompute the profile’s current scheduled deadline and use:

`new_deadline = max(current_schedule_deadline, existing_override, approval_now) + minutes * 60`

This makes the duration relative to the later of the current deadline and the
approval time. A schedule change before approval is therefore respected. A
second approval extends the latest stored deadline rather than losing the
first approval.

The read-modify-write operation needs one root-only lock shared by the time
ledger and time grant actions. Each record replacement remains atomic. A
`both` approval updates the single `.tonight.json` record under that lock, so
there is no two-file partial grant or duplicate retry. A failed replacement
leaves the prior record untouched and reports failure.

The ledger continues to count usage only for active, unlocked sessions.
Extending lights-out never adds usage or alters the ordinary `.grant` file.
The ledger adds the `.tonight.json` budget contribution only when calculating
the current day’s remaining budget.

## User-visible result

The modal should describe the actual cause:

- budget: “15 more minutes of screen time”;
- lights-out: “15 more minutes before lights-out”;
- both: “15 more minutes tonight”.

The root verifier should return an outcome token such as
`ok budget`, `ok lights-out`, or `ok both`, while retaining the existing
`ok*` compatibility accepted by the client. The modal maps the result to an
accurate completion message. It must never say that time is ready when the
budget is still exhausted.

Ask later remains an undecided request message. It must not claim that the
extension has already happened. A queued lights-out request whose logical day
is stale is rejected as expired rather than applied to the next day.

## Focused proof

Add tests for:

- lights-out grace with budget remaining: lights-out approval clears grace on
  the next ledger tick without changing the budget grant;
- ordinary budget grant while lights-out remains active: lights-out still
  controls the state;
- both causes active: root applies the combined action and the result text
  does not overpromise;
- inactive ticks before and after approval add no usage;
- schedule changed before approval: root uses the current schedule and current
  logical day;
- repeated approvals serialize and extend the latest deadline;
- a stale queued day is rejected;
- absent scope remains a budget request;
- malformed scope/day and kid-supplied scope disagreement are rejected or
  recomputed from root state;
- next logical day ignores the prior day’s override.

## Live gate

Use an invented kid with budget headroom and lights-out imminent. Confirm the
root state enters `grace` with `reason=lights-out`, approve through the
parent-password modal, and verify after the next ledger tick that the state
leaves lights-out grace and the ordinary budget grant remains unchanged.

Run a separate deterministic ledger test for 04:00 expiry; do not wait
overnight or alter live configuration.
