# Contracts

## Call Contract

- One active/ringing/connecting call globally.
- Incoming call during active call returns busy.
- Active file transfer blocks call start/accept.
- Active call blocks file send/accept.
- Terminal room state must release pair and user locks.

## Presence Contract

- Online means fresh backend presence, not just local cached state.
- Closed/killed app means offline.
- Presence unknown blocks call/request start.

## Connection Request Contract

- Request notification is offline-only.
- Confirmation required before spending request quota.
- Online direct Connect must not consume request quota.

## Update Contract

- Required update blocks app.
- Optional update shows non-blocking banner.
- Invalid manifest must not crash app.

Related: [[Requirements]], [[Security Review]], [[Risk Register]].
