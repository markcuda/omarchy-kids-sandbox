# Issue 107 gate-runner handoff

Not executed from the drafting sandbox. Only the authorized gate runner may use `test/live/` or
`scripts/vm-*`, one scenario at a time, from its clone containing `test/live/config.env`.

1. Fresh disk-mode LUKS VM: provision passworded `kid-ada`; verify the transaction and exported
   token; cold boot with the kid secret and then the parent secret; remove and prove only the
   token-owned kid slot disappears.
2. Crash snapshots at each durable boundary: before transaction create, after transaction create,
   reserved fsync, adding, add, token, added, map rewrite, useradd, removing, unmount, userdel,
   home move, kill, and removed.
   Restore before each case, rerun normally, and require completion or the documented explicit
   active-without-token ambiguity with no kill.
3. Concurrency on one VM, with barriers inside the held lock: two adds, add/remove, two removes,
   reserved-slot allocation, reconcile while a writer waits, derived-map contention, and
   `omarchy-kids-conf machine set parent` waiting on that same interval. Verify no duplicate
   account/map/policy, lost parent/kid mapping, unrecorded managed live key, or stale transaction
   that can kill a later occupant.
4. Portal mode: add/remove passworded and no-password profiles; prove zero cryptsetup, UKI, Limine,
   and Kids Mode boot-drop-in mutation.
5. Legacy migration: a matching-token legacy entry migrates; an untagged or mismatching entry
   fails closed with the profile, account, home, slot, and map preserved.
