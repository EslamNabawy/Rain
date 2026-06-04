# Emulator Test Matrix

## Priority Scenarios

- Offline call creation denied before locks.
- Live call lock returns busy.
- Terminal call lock can be cleaned.
- Corrupt call room does not crash watcher.
- Connection request only allowed for offline/stale peer.
- Future-dated timestamps denied.
- Blocked peers denied.
- Tombstoned account cannot re-add `userSearch` or upsert profile data. Covered locally by `integration_account_deletion_emulator_test.dart`; cloud proof pending on the new commit.
- Account deletion cleanup preserves tombstone and denies post-delete restoration paths. Covered locally by `integration_account_deletion_emulator_test.dart`; cloud proof pending on the new commit.
- Online receiver connection request denial does not mutate quota.
- Newer live call locks are never repaired away.

Related: [[Emulator Coverage]], [[Rules Strategy]], [[Signaling Reliability Epic]], [[Scenario Coverage Matrix]], [[Assumption Register]].
