# Documentation Workflow

## Rule

Documentation changes are part of implementation, not cleanup.

## After Every Code Change

1. Identify impacted feature notes.
2. Update architecture notes if ownership, dependency, data flow, or state flow changed.
3. Update [[Project Memory]] when a lasting lesson or rule is discovered.
4. Update [[Open Bugs]] or [[Fixed Bugs]] when bug status changes.
5. Update [[Technical Debt]] when debt is added or reduced.
6. Add an ADR for significant architectural decisions.

## Automated Gate

`scripts/check_obsidian_vault.ps1` validates that required vault notes exist and that Obsidian wiki links resolve to real note titles.

The `Documentation Vault` GitHub workflow runs that check when the vault, documentation check script, or workflow changes.

## Minimum Documentation For A New Feature

- Feature note under `03-Features`.
- API/contract note if remote or protocol behavior changes.
- Database note if persistence changes.
- Security note if permissions or sensitive data changes.
- Test note if QA scope changes.

Related: [[AI Instructions]], [[Project Memory]], [[ADR-003]].
