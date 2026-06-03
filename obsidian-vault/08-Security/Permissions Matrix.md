# Permissions Matrix

## RTDB High-Level Access

| Path | Read | Write |
| --- | --- | --- |
| `users/{username}` | authenticated users | owner only |
| `presence/{username}` | authenticated users | owner only |
| `friendRequests/{to}/{from}` | receiver | sender/receiver rules |
| `friendships/{username}/{friend}` | owner | participant rules |
| `blocks/{blocker}/{blocked}` | blocker | blocker |
| `rooms/{roomId}` | room participants | room participants by role |
| `voiceCalls/{callId}` | call participants | participant state-machine rules |
| `voiceCallInboxes/{username}/{callId}` | inbox owner | participant state-machine rules |
| `activeVoicePairs/{pairId}` | participants | caller claim and participant cleanup |
| `activeVoiceUsers/{username}` | lock user or participants | caller claim and participant cleanup |
| `connectionRequests` | owner-scoped | offline-only request rules |

## Sensitive Data Rules

Never log or expose:

- passwords
- tokens
- credentials
- secrets
- raw SDP
- raw ICE candidates
- ciphertext payloads
- nonces and MACs
- message text
- file bytes

Related: [[Security Review]], [[Contracts]].
