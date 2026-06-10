# Requirements

## Functional Requirements

- Users can register and sign in by username/password.
- Users can search, request, accept, reject, unfriend, and block.
- Accepted friends can connect over WebRTC data channels.
- Text messages are persisted locally and delivered over peer data channels.
- Files are offered, accepted, chunked, transferred, and saved/exported.
- Voice calls use a dedicated WebRTC media connection.
- Video calls use the same call runtime with camera tracks and video renderers.
- Firebase coordinates auth, presence, friendships, signaling, call rooms, call locks, and update policy.
- Drift stores local identity, friends, messages, queues, file transfers, and connection memory.
- App supports Android and Windows.

## Non-Functional Requirements

- Reliability over visual novelty.
- Secure signaling metadata and strict Firebase authorization.
- Clear user-facing errors for every blocked action.
- Low-power Android support, especially ARMv7.
- Spark/free-tier Firebase compatibility unless explicitly changed.
- Release artifacts must be easy to download individually.

## Hard Constraints

- Work should happen on `dev`.
- Do not edit `D:\old project\Rain`.
- Firebase Spark/free tier is a business constraint.
- No closed-app call guarantee yet.

Related: [[System Architecture]], [[Risk Register]], [[Launch Readiness]].
