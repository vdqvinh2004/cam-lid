# Feature Specification: M7 Supervised Real User Testing

**Feature Branch**: None; numbered folder is feature identity, not Git branch.
**Created**: 2026-10-04
**Status**: Superseded 2026-11-03: user testing happens through GitHub issues on the pre-release ([ADR 0004](../../docs/adr/0004-distribution-through-github-releases.md)). History below is kept.
**Input**: CamLid milestone M7: Anonymized trial protocol, participants including Orca workflow, findings and release recommendation. One scoped feature folder per user instruction.
**Prerequisites**: M6. Roadmap.
**Scope**: Anonymized trial protocol, participants including Orca workflow, findings and release recommendation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Validate real coding workflows (Priority: P1)

User or reviewer obtains verified milestone outcome: Five consenting users; at least 4/5 identify reason/change mode unaided within 60s; all complete supported-agent/Orca session; faults triaged.

**Why this priority**: Required to deliver supervised real user testing and protect downstream gates.
**Independent Test**: Five consenting users; at least 4/5 identify reason/change mode unaided within 60s; all complete supported-agent/Orca session; faults triaged.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** Five consenting users; at least 4/5 identify reason/change mode unaided within 60s; all complete supported-agent/Orca session; faults triaged.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### Edge Cases
Every participant support row, L13/L15/L20 comprehension; stop trial on safety/recovery failure. Failed prerequisites, unsupported versions, absent evidence and accidental
simulation-as-hardware claims must remain visible. Limitations.

## Requirements *(mandatory)*

### Functional Requirements
Stable FR identifiers refer to shared product requirements, not a second set of product defaults.
Scope statements below narrow delivery ownership; complete invariants/values remain authoritative
in product specification.

- **FR-021**: Deliver scoped behavior for product FR-021: Refuse unsupported/uncertain closed-lid behavior; disclose safety and unsaved-work limits. Full numeric invariants remain in product source; delivery limited to stated milestone scope.

### Key Entities
Relevant evidence/state follows [data-model.md](data-model.md); shared runtime definitions
remain in domain model.

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **SC-006**: Milestone evidence MUST establish product SC-006 within its scope; downstream/integrated checks remain explicitly deferred.
- **SC-007**: Milestone evidence MUST establish product SC-007 within its scope; downstream/integrated checks remain explicitly deferred.

**Milestone exit gate**: User metrics recorded; no unexplained safety/restore failure; any fix requires relevant M6 rerun before wider trial.

## Assumptions
Current operation edits planning documents only. Per-device physical eligibility and emergency Stop/rollback check before supervised ventilated-desk session.
Tests required where scoped validation changes safety, detection, native UX or release behavior.
M1–M7 tasks remain unexecuted; physical feasibility and future deliverables are not established by
this spec. M0 completed documentation work does not establish runtime support.
