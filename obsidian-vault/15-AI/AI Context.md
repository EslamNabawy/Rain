# AI Context

Read this before making changes.

## Project

Rain is a Flutter Android/Windows private peer-to-peer messenger. It uses Firebase for auth, presence, friendship, signaling, call locks, connection requests, and update policy. It uses WebRTC for chat data channels, file transfer, voice media, and video media. It uses Drift for local persistence.

## Critical User Constraints

- Work in `C:\Users\eslam\OneDrive\Desktop\GoodStuff\Rain`.
- Do not touch `D:\old project\Rain`.
- Work should stay on `dev` unless explicitly told otherwise.
- Firebase Spark/free tier is a hard constraint unless explicitly changed.
- Commit every implementation change when requested by the user.
- Build only when requested or at final release gate.

## Current Highest Risks

- Call reliability.
- Stale Firebase call locks.
- Presence freshness.
- Update validation.
- Local DB scaling.
- File transfer performance.

Related: [[Project Memory]], [[AI Instructions]], [[Technical Debt]].
