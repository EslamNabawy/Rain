# Coding Standards

## Priorities

1. Correctness
2. Reliability
3. Security
4. Maintainability
5. Operational simplicity
6. Performance
7. Developer experience

## Dart/Flutter Standards

- Use Riverpod for app state.
- Keep side effects in runtime/controllers, not widgets.
- Keep raw WebRTC operations in `peer_core`.
- Keep signaling policy in `protocol_brain`.
- Keep local persistence in `rain_core`.
- Prefer typed decisions and reason codes over stringly errors.
- Do not log secrets, SDP, ICE candidate strings, passwords, message text, or file bytes.

## Required Improvements

- Enable strict analyzer options.
- Make Melos analyze use fatal infos and warnings.
- Split files larger than 1,000 lines unless generated.

Related: [[Project Conventions]], [[Technical Debt]].
