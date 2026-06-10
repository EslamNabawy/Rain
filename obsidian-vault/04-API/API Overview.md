# API Overview

Rain has no public HTTP API. Its remote API surface is Firebase Auth, Firebase Realtime Database, Firebase Remote Config, and optional Firebase Functions.

## API Categories

- Authentication API through Firebase Auth.
- Signaling API through RTDB adapter methods.
- Presence API through RTDB `presence`.
- Update API through Remote Config manifest.
- Connection request API through RTDB request paths.

Related: [[Contracts]], [[Endpoints]], [[Backend Architecture]].
