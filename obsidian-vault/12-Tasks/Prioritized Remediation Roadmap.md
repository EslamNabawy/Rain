# Prioritized Remediation Roadmap

## P0 - Stop Runtime Breakage

1. Split call start into explicit phases.
2. Add candidate write/read health checks.
3. Add Firebase watch `onError` handling.
4. Add stale call lock emulator tests.
5. Fix update version parsing and required-update root gate tests.

## P1 - Scale Local Data

1. Add Drift indexes and migration.
2. Add conversation pagination.
3. Rework file transfer chunk I/O.

## P2 - Reduce Maintenance Risk

1. Split `VoiceCallRuntime`.
2. Split large UI files.
3. Consolidate CI workflows.
4. Tighten analyzer settings.

## P3 - Production QA

1. Android and Windows call matrix.
2. TURN relay smoke.
3. ARMv7 performance smoke.
4. Release artifact smoke install.

Related: [[Technical Debt]], [[Launch Readiness]], [[Backlog]].
