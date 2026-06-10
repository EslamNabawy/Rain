# System Ownership Map

Last updated: 2026-06-04

## Purpose

Map major systems to expected source locations. Phase 2 will verify and refine these entries.

## Initial Ownership

| System | Expected Location | Related Notes |
| --- | --- | --- |
| Flutter app | `apps/rain` | [[Frontend Architecture]], [[Feature Map]] |
| WebRTC transport | `packages/peer_core` | [[Signaling Architecture]], [[CallMediaCoordinator]] |
| Signaling/session logic | `packages/protocol_brain` | [[Lease Management]], [[Call State Machine]] |
| Core storage/domain | `packages/rain_core` | [[Database Architecture]], [[Database Schema]] |
| Firebase rules/config | `backend/firebase` | [[Firebase Architecture]], [[Rules Strategy]] |
| Documentation system | `obsidian-vault` | [[Project Home]], [[Project Memory]], [[AI Memory Index]] |
| Scenario intelligence model | `obsidian-vault` | [[Scenario Intelligence Agent]], [[System Model]], [[State Graph]], [[Business Rule Graph]], [[Failure Graph]], [[Assumption Register]] |

Related: [[Knowledge Graph Index]], [[Repository Map]], [[Current Architecture]].
