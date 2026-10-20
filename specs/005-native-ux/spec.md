# Feature Specification: M4 Native UX and Activity History

**Feature Branch**: None; numbered folder is feature identity, not Git branch.
**Created**: 2026-10-04
**Status**: Planned; can overlap M3 after M2 PASS
**Input**: CamLid milestone M4: Dashboard/options/settings/onboarding, native accessibility, local logs and redacted export. One scoped feature folder per user instruction.
**Prerequisites**: M2. [Roadmap](../../docs/planning/roadmap.md).
**Scope**: Dashboard/options/settings/onboarding, native accessibility, local logs and redacted export.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Control from native menu bar (Priority: P1)

User or reviewer obtains verified milestone outcome: Left/right clicks, keyboard/VoiceOver, settings, unsupported/stale/grace/recovery and long-label states pass native walkthrough.

**Why this priority**: Required to deliver native ux and activity history and protect downstream gates.
**Independent Test**: Left/right clicks, keyboard/VoiceOver, settings, unsupported/stale/grace/recovery and long-label states pass native walkthrough.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** Left/right clicks, keyboard/VoiceOver, settings, unsupported/stale/grace/recovery and long-label states pass native walkthrough.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### User Story 2 - Understand session decisions (Priority: P2)

User or reviewer obtains verified milestone outcome: Session/reason filters, bounded rotation, redacted export/delete omit secrets/transcripts and preserve cleanup outcomes.

**Why this priority**: Required to deliver native ux and activity history and protect downstream gates.
**Independent Test**: Session/reason filters, bounded rotation, redacted export/delete omit secrets/transcripts and preserve cleanup outcomes.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** Session/reason filters, bounded rotation, redacted export/delete omit secrets/transcripts and preserve cleanup outcomes.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### Edge Cases
L11–L13, L18–L20; hidden/unknown/recovery statuses remain explicit. Failed prerequisites, unsupported versions, absent evidence and accidental
simulation-as-hardware claims must remain visible. [Limitations](../../docs/planning/limitations.md).

## Requirements *(mandatory)*

### Functional Requirements
Stable FR identifiers refer to shared product requirements, not a second set of product defaults.
Scope statements below narrow delivery ownership; complete invariants/values remain authoritative
in [product specification](../../docs/planning/product-spec.md).

- **FR-001**: Deliver scoped behavior for [product FR-001](../../docs/planning/product-spec.md#functional-requirements): Provide native menu bar lifecycle and dashboard/options/settings interactions. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-002**: Deliver scoped behavior for [product FR-002](../../docs/planning/product-spec.md#functional-requirements): Keep requested mode separate from effective protection; safety overrides every mode. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-013**: Deliver scoped behavior for [product FR-013](../../docs/planning/product-spec.md#functional-requirements): Release owned resources and verify restoration with failure-class timing. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-014**: Deliver scoped behavior for [product FR-014](../../docs/planning/product-spec.md#functional-requirements): Expose effective reason, health/freshness, agent confidence, deadlines and cleanup outcome. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-015**: Deliver scoped behavior for [product FR-015](../../docs/planning/product-spec.md#functional-requirements): Validate preferences and preserve opt-in provider configuration with preview/removal. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-016**: Deliver scoped behavior for [product FR-016](../../docs/planning/product-spec.md#functional-requirements): Keep bounded private transition history with redacted export/filter/delete. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-018**: Deliver scoped behavior for [product FR-018](../../docs/planning/product-spec.md#functional-requirements): Preserve native keyboard/VoiceOver, focus, appearance and reduced-motion behavior. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-021**: Deliver scoped behavior for [product FR-021](../../docs/planning/product-spec.md#functional-requirements): Refuse unsupported/uncertain closed-lid behavior; disclose safety and unsaved-work limits. Full numeric invariants remain in product source; delivery limited to stated milestone scope.

### Key Entities
Relevant evidence/state follows [data-model.md](data-model.md); shared runtime definitions
remain in [domain model](../../docs/planning/domain-model.md).

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **SC-004**: Milestone evidence MUST establish [product SC-004](../../docs/planning/product-spec.md#measurable-outcomes) within its scope; downstream/integrated checks remain explicitly deferred.

**Milestone exit gate**: Native control/history accessibility and privacy pass; status never claims restoration from expired lease alone.

## Assumptions
Current operation edits planning documents only. State fixtures permit UI testing independently of live agents; integrated agent rows required before M6.
Tests required where scoped validation changes safety, detection, native UX or release behavior.
M1–M7 tasks remain unexecuted; physical feasibility and future deliverables are not established by
this spec. M0 completed documentation work does not establish runtime support.
