# Monitoring

## Current Monitoring

Rain currently relies on local diagnostics export rather than remote telemetry.

## Captured Data

- Dart/Flutter fatal errors.
- App events.
- Firebase/API metadata through debug adapter.
- Riverpod provider transitions.
- WebRTC lifecycle metadata.
- Failure taxonomy summaries.

## Missing Monitoring

- Remote crash aggregation.
- Release artifact smoke telemetry.
- Firebase quota dashboard integration.
- Alerting for permission-denied spikes.

## Constraint

No remote telemetry should be added without explicit privacy/product decision.

Related: [[Diagnostics And Logging]], [[Incident Response]].
