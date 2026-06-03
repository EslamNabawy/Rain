# Critical Path

## Blocking Chain

```mermaid
flowchart TD
  A["Split call runtime ownership"] --> B["Reliable call lease/state machine"]
  B --> C["Firebase rules emulator confidence"]
  C --> D["PC/mobile voice-video reliability"]
  D --> E["Release gates with artifact proof"]
  E --> F["Production readiness 90/100"]
```

## Non-Negotiable Fixes

- [[VoiceCallRuntime Refactor]]
- [[Lease Management]]
- [[Call State Machine]]
- [[Presence Management]]
- [[Emulator Coverage]]
- [[Release Gates]]

Related: [[Master Roadmap]], [[Production Readiness]], [[BLOCKERS]].
