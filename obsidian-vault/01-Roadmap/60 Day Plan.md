# 60 Day Plan

Last updated: 2026-06-03

## Goal

Make the app scale locally, handle large transfer pressure, reduce UI rebuild/performance risk, and strengthen contract tests after the first 30 days stabilize call and rules foundations.

Related: [[Master Roadmap]], [[Parallel Work Streams]], [[Database Scalability Epic]], [[File Transfer Optimization Epic]], [[CI-CD Modernization Epic]].

## Day 31-45: Database And File Transfer Scale

| Item | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| TASK-008: [[Index Strategy]] migration | P1 | [[Database Architecture]], [[Migration Plan]] | 3 days | Critical local queries have index coverage. | Migration tests pass from current schema. |
| TASK-009: [[Pagination Strategy]] | P1 | TASK-008 | 4 days | Conversation loading is bounded and page-based. | Widget/provider tests prove paginated load and no full-list rebuild. |
| TASK-010: [[Streaming Architecture]] receive sink | P1 | [[File Transfer]] | 4 days | Incoming chunks stream to temp file. | Large-file tests pass and temp cleanup is verified. |
| TASK-011: [[Backpressure Strategy]] send gate | P1 | TASK-010 | 3 days | Buffered amount stays within budget. | Slow receiver tests prove pause/resume behavior. |

## Day 46-60: UI Performance, Contracts, Workflow Ownership

| Item | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| TASK-018: Adapter contract tests | P1 | [[Emulator Coverage]], [[Test Strategy]] | 5 days | Signaling adapters pass success/failure/corruption/cancel cases. | Fake and emulator-backed tests are part of a documented gate. |
| TASK-019: Single call surface renderer | P1 | TASK-003, [[Voice Calls]], [[Video Calls]] | 4 days | Only one call surface renders at a time. | Widget tests prove no duplicate bars or unsafe overlays. |
| TASK-020: Provider boundary cleanup | P2 | TASK-009, TASK-019 | 4 days | Chat/call/friends rebuilds are scoped. | Rebuild isolation tests pass. |
| TASK-016: Workflow ownership cleanup | P2 | TASK-015, [[CI-CD Roadmap]] | 2 days | Fast artifacts and hard release gates are distinct. | Workflow map and artifact rules are documented. |

## 60 Day Exit Criteria

- Local data can scale beyond test accounts.
- Large file transfer path has bounded-memory behavior.
- Adapter contracts prove Firebase and fake behavior parity.
- Call UI rendering has one source of truth.
- Release workflow ownership is understandable.

## 60 Day Definition Of Done

- [[Coverage Dashboard]] reflects new tests.
- [[Technical Debt Register]] removes or downgrades closed scale debt.
- [[Risk Register]] updates residual file/database/UI risks.
- `.\scripts\check_obsidian_vault.ps1` passes.
