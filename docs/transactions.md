# Account and LUKS transactions

Issue 107 adds one authoritative record per managed account at
`/var/lib/omarchy-kids/transactions/<account>.json`. The directory is root-owned `0700`; records
are root-owned `0600` regular files. Each update writes a same-directory temporary file, fsyncs
it, renames it, and fsyncs the directory. Symlinks, wrong ownership or mode, unknown fields,
invalid types/ranges, duplicate identities, malformed UUIDs, and illegal state transitions fail
closed.

The version 1 record contains the schema, transaction UUID, account, direction, LUKS device UUID,
explicit slot, random owner UUID, LUKS state, password/LUKS modes, account lifecycle state, fixed
home destination, and the display/band/avatar data needed after a profile loss. Portal and
no-password records use `luks_mode=none` with null device and slot; they never invent LUKS
identity.

LUKS state advances only as `reserved -> adding -> added -> removing -> removed`. Account state
records creation before `useradd`, then password, fstab, mount, profile, namespace,
AccountsService, face, portal, launcher, and session completion. Removal records its intent,
unmount, fstab/namespace/AccountsService/face/launcher/session cleanup, account absence, the home
destination and move, and final profile cleanup. The profile and roster remain until the journal
allows their removal.

All reconciliation, slot allocation, token work, map derivation, account mutation, and deletion
run under the existing `luks-slots.lock` writer lock. The `machine set parent` map writer takes the
same lock and uses the same atomic rewrite and fsync protocol. Unresolved records reserve their
slots. `luks-slots` is now a derived boot compatibility map, never deletion authority.

## On-device ownership token

Every new disk-mode slot gets a LUKS2 custom JSON token containing only `type=omarchy-kids`, schema,
account, transaction UUID, random owner UUID, device UUID, slot, and the bound keyslot list. It
contains no password or key material. Before every `luksKillSlot`, including recovery or rollback,
the command re-reads the device UUID, active slot, token, and transaction under the common lock.
Any mismatch leaves the slot untouched.
The recorded device UUID is checked before slot occupancy is used for any recovery decision, so a
same-numbered slot on another device cannot advance a journal or receive a key.

An `adding` record with an empty slot resumes when both secrets are supplied again. An active
`adding` slot with the matching token advances to `added`; an active untagged or mismatching slot
is deliberately ambiguous and is never deleted or blindly adopted. `removing` plus an empty slot
finishes retirement. A recycled or mismatching active slot is never killed.

## Power loss and retries

Retry the same command. A passworded add may require the kid and parent secrets again because
secrets are never stored. Retry discovery includes unfinished generated suffixes, and an account
that appears after `creating` is accepted only when its passwd shell, home, and exact group set
match the journaled request. A fixed home destination is recorded before the move; both paths
existing is a conflict, and both paths missing is an unproven preservation failure. Account absence
is expected only after the removal journal records that intent. Diagnostics name ambiguous
ownership and preserve the profile and roster for repair. Removal refuses an incomplete add
lifecycle before touching its account or LUKS slot; finish or repair that add first. Portal-mode
full removal also blocks an owned transaction whose derived map line is missing.

Legacy maps are inspected but are not proof. A legacy entry is migrated automatically only if an
existing `omarchy-kids` device token exactly proves its account, slot, device, transaction, and
owner identity. Untagged legacy slots remain reserved and removal fails with instructions to
inspect/migrate them; slot number alone can never authorize deletion.
An old removal-intent file with no map is preserved as ambiguous disk evidence and is never
converted into a non-LUKS transaction.
A valid `luks_mode=none` journal does not cancel older disk evidence: if either a map entry or
removal-intent file still names that account, per-account and full removal both stop before
account, home, profile, or evidence cleanup.
