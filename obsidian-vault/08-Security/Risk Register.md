# Risk Register

| Risk | Severity | Owner Area | Mitigation |
| --- | --- | --- | --- |
| False busy/stale call locks | Critical | backend/runtime | canonical lease or stronger repair |
| PC-to-mobile call failure | Critical | WebRTC/signaling | classify signaling/media failures and test matrix |
| Update prompt unreliable | High | Remote Config/app | strict semver and root gate tests |
| Presence stale after app close | High | runtime/Firebase | session-owned presence and watcher errors |
| Missing local DB indexes | High | rain_core | Drift migration |
| File transfer I/O pressure | High | runtime/file | persistent sink and streaming chunks |
| Diagnostics raw errors | Medium | security/ops | sanitize error strings |
| Workflow drift | Medium | DevOps | reusable workflows |

Related: [[Technical Debt]], [[Launch Readiness]], [[Incident Response]].
