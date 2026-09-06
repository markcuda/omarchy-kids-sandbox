# Issue #137 implementation brief: tonight-only approval

## Goal

Add one explicit `tonight` action for the Time’s Up flow. The parent-facing
wording is “15 more minutes tonight”: it authorizes root to adjust tonight’s
lights-out limit and, when necessary, tonight’s remaining budget. Ordinary
budget requests keep their existing behavior and interfaces.

## Request contract and authority

Legacy time requests remain unchanged: absent `action` means the current daily
budget grant path. The new request adds:

- `action=tonight`;
- `logical_day=YYYY-MM-DD`;
- a stable `request_id` created before the immediate GRANT or Ask-later outbox
  write.

The producer path is `timesup.qml` → `omarchy-kids-ask` → `lib/ask.py` →
`omarchy-kids-authd` → `omarchy-kids-ask apply_record`. The QML surface reads
the root-published `logical_day` and `reason`, but those values are hints for
the request. The kid cannot choose the authority action.

For `action=tonight`, the root apply path takes the shared ledger/grant lock,
then recomputes the current logical day, profile schedule, current budget,
existing tonight record, and current wall clock. It does not trust stale
runtime JSON for the decision. The request is rejected as expired if its
logical day is no longer current. If today no longer needs a tonight
extension, it is rejected as stale rather than changing a future night.

The root accepts `action=tonight` only while the current lights-out limit is
binding. A budget-caused Time’s Up remains the legacy budget action. A schedule
edit that removes the current lights-out condition, or a prior approval that
has already resolved it, rejects a new tonight request. A positive but short
remaining budget is valid for tonight; it is topped up only enough to cover
the approved usable interval.

Legacy budget requests do not gain a new grace-state restriction. They may be
approved before Time’s Up exactly as they are today. Only `action=tonight`
requires the current logical day and tonight-specific validation.

## Logical-day schedule and storage

The logical day starts at 04:00. For a logical day labelled `D`, a configured
lights-out time at or after 04:00 maps to `D`’s calendar date; a configured
time before 04:00 maps to the following calendar date. The logical-day end is
`D+1 04:00`.

Store tonight approvals per kid in one root-owned atomic record:
`/var/lib/omarchy-kids/<kid>/usage/<D>.tonight.json`.
It contains the current effective deadline, the validated request data, and
an append-only approval entry for each `request_id`, including its outcome.
Existing integer `<D>.grant` files remain the source and format for ordinary
budget grants.

Under the shared root lock, compute the candidate deadline from the current
profile schedule and approval time:

`candidate = max(current_schedule_deadline, approval_now) + minutes * 60`

Use an existing tonight deadline only when it is still the currently binding
limit; otherwise the request is stale. Cap the candidate at the logical-day
end. A schedule edit before approval is therefore read at approval time. The
usable interval is `candidate - approval_now`. Calculate the raw budget balance
in seconds (allowed time minus usage, including a negative overrun), and add
`ceil(max(0, usable interval - raw balance) / 60)` budget minutes.
Thus a 15-minute request with 5 minutes remaining adds 10 minutes, while a
request capped by 04:00 adds only the amount needed for the shortened interval.

When lights-out is binding, a tonight approval handles a short, zero, or
negative budget balance through that top-up. Only expiry caused by budget
alone uses the legacy budget action. The deadline and any needed top-up live
in the one `.tonight.json` record. The ledger adds that
record’s contribution when calculating today’s remaining budget, but never
adds usage for an inactive or locked session.

Each entry binds `request_id` to the input kid, action, logical day, and requested
minutes, and stores the computed interval and outcome. Reusing an ID with
changed input fields is rejected; replay reads the stored result without
recomputing its interval. A record entry is committed atomically before the root
acknowledgement. A retry with the same unchanged request returns the stored
outcome without applying a second contribution; an `already-applied` result
describes the replay and does not promise that time is currently available.
A later fresh expiry may use a distinct ID. A failed write leaves the prior
record intact. The logical-day path and 04:00 cap make old approvals expire
without affecting the next day.

## Immediate, queued, and UI results

Immediate GRANT carries the same `request_id`, `action`, and logical day as
the outbox path. Queue collection preserves them. `apply_record` must apply a
new tonight record before deciding it approved. If the action is expired or
fails, it remains unapplied and `approve --apply` reports failure; it must not
mark the request approved anyway. This corrects the current unconditional
approval behavior in `bin/omarchy-kids-ask`.

The verifier returns a safe result token such as `ok tonight extended`,
`ok tonight capped`, or `ok tonight already-applied`. The client
prints that token, and `share/ask/shell.qml` collects stdout instead of using
only the exit code. A lost acknowledgement can therefore be retried and show
the stored result. Ask-later remains an undecided message until a root
approval succeeds. The modal treats `already-applied` as a recorded replay,
not as proof that the child currently has usable time.

The Time’s Up modal uses “Ask for 15 more minutes tonight.” Success text is
based on the root result and never claims time is ready when the root still
reports no usable budget. Failure and expiry remain visible to the parent
workflow.

## Focused proof

Add tests for:

- legacy budget approval before grace remains accepted and unchanged;
- lights-out with budget remaining extends only the tonight deadline;
- positive but short remaining budget receives only the top-up needed for the
  approved interval;
- binding lights-out with zero or negative budget balance receives enough
  top-up to cover both the overrun and the approved interval;
- budget-caused Time’s Up stays on the legacy budget action;
- inactive and locked ticks add zero usage;
- schedule edits before approval are recomputed from the profile;
- pre-04:00 schedule mapping and the 04:00 cap/expiry;
- stale logical-day requests are rejected;
- a new tonight request requires a currently binding lights-out condition;
- the same unchanged `request_id` after a committed write returns the prior
  outcome and does not grant twice, while changed-data reuse is rejected;
- failure after a commit but before acknowledgement is retry-safe;
- an `already-applied` replay does not claim current availability;
- malformed action/day/id fields and untrusted kid-supplied action are rejected;
- queued tonight apply leaves failed or expired records unapplied;
- the client displays the returned result token rather than discarding it.

## Live gate

With an invented kid who has budget headroom and lights-out imminent, verify
root state enters lights-out grace, approve “15 more minutes tonight” through
the parent-password modal, and confirm after the next ledger tick that the
lights-out condition clears without changing the ordinary `.grant` file.

Use deterministic ledger fixtures for budget exhaustion, schedule changes,
midnight/04:00 mapping, stale queued requests, commit-before-ack retry, and
next-day expiry. Do not wait overnight or alter live configuration.
