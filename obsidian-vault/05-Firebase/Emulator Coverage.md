# Emulator Coverage

## Required Matrix

| Area | Required Tests |
| --- | --- |
| users | create/update owner only |
| presence | owner write, stale session rejection |
| friendships | accepted friend symmetry |
| blocks | blocked peer cannot write |
| voice call locks | claim, stale repair, live busy |
| voice rooms | ringing, accepted, negotiating, connected, terminal |
| inboxes | corrupt removal, participant-only write |
| connection requests | offline-only, confirmation, quota, cooldown |
| updates | Remote Config parser tests |

## Current Gap

Rules contract tests exist, but call transition coverage must be expanded before production.

Related: [[Rules Strategy]], [[Signaling Reliability Epic]], [[Test Strategy]].
