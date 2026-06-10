# Sound System

## Purpose

Play mature, restrained Rain-themed sounds for messages, calls, requests, and UI events.

## Business Value

Improves feedback without becoming annoying or interrupting user media.

## Technical Flow

- Sound events route through a central sound event router.
- Settings control sound behavior.
- Burst compression prevents repeated message spam.

## Edge Cases

- Multiple messages in a row.
- Ringtone after call terminal state.
- Phone music playing.
- Rapid state changes.

## Testing Requirements

- Burst handling.
- Ringtone lifecycle.
- User mute/settings behavior.
- No stale ringback after call failure.

Related: [[Voice Calls]], [[Video Calls]], [[Settings]].
