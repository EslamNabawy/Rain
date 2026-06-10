# UI State Map

## Major UI State Domains

- Auth/root gate state.
- Update gate state.
- Runtime startup state.
- Selected chat peer.
- Friend presence state.
- Peer connection view state.
- Active call state.
- Call surface presentation state.
- File transfer view state.
- Connection request state.
- Sound/settings state.

## Key Rule

UI should render state and forward intent. Runtime controllers decide side effects.

## Known Risk

Call UI state and call runtime state have historically drifted. Future work should keep one UI-facing call suite model derived from runtime truth, not duplicated state.

Related: [[Frontend Architecture]], [[Voice Calls]], [[Video Calls]].
