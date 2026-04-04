OpenCode Integration Delivery (Phase 5)

Summary
- This patch delivers Phase 2–4 artifacts for the OpenCode integration, plus handoffs and runbooks for Phase 5 rollout.
- Artifacts included:
  - Phase 2 unit decomposition docs and scaffolds
  - Phase 3 integration run artifacts and outputs
  - Phase 4 verification artifacts (phase4-runner-output.json) and verification plan
  - Flutter/mobile MVP scaffolding (where applicable)

Verification
- Local validation steps provided in plans/phase2-unit-decomposition.md, plans/phase3-integration.md, plans/phase4-verification.md
- Phase 4 runner artifact summary confirms all checks PASS

Rollout Plan
- Deploy to staging, run smoke tests, verify the PR against MVP specs
- If issues arise, revert to previous committed artifacts and re-run gates

Rollback
- Revert commit; re-run phase 2-4 runners; re-ship after fixes

Notes
- This is a delivery-only PR; no changes to L2/L3 interface after this point unless gating failures require fixes.
