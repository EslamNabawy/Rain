# Research Notes

## WebRTC Lessons

- Media packets are carried by WebRTC, not Firebase.
- Firebase only coordinates signaling, rooms, locks, presence, and candidates.
- PC-to-mobile failures must be separated into permission, signaling, ICE, TURN, and renderer failures.
- Closed-app calls need push/foreground service work; current scope treats closed app as offline.

## Firebase Spark Lessons

- Cloud Functions are not a reliable production dependency if the project must stay on free tier.
- RTDB rules must enforce critical invariants.
- Client-side quotas are best effort unless rules enforce structure.

Related: [[Backend Architecture]], [[Voice Calls]], [[Video Calls]].
