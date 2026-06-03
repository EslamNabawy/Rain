# Rules Strategy

## Strategy

RTDB rules must enforce critical invariants because Spark/free-tier mode cannot depend on paid backend functions.

## Required Invariants

- Only account owner writes own user/presence.
- Blocked users cannot create relationship/call/request artifacts.
- Offline users cannot receive call rooms or offline request notifications unless rules allow that exact feature.
- Call locks must match room call id.
- Terminal cleanup must not delete newer locks.

## Weakness

Rules are currently long and hard to audit manually.

## Action

Every rules change must update [[Emulator Coverage]].

Related: [[Security Roadmap]], [[Firebase Architecture]].
