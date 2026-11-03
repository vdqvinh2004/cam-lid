# Feature Specification: M6 AI Quality Gate

**Feature Branch**: None; numbered folder is feature identity, not Git branch.
**Created**: 2026-10-04
**Status**: Superseded 2026-11-03: the M6 gate sequence was replaced by owner-attended trials (specs 014 and 016) and a public pre-release ([ADR 0004](../../docs/adr/0004-distribution-through-github-releases.md)). History below is kept.
**Input**: CamLid milestone M6: Integrated contract parity, performance, complete limitation audit, native UI and physical regression evidence. One scoped feature folder per user instruction.
**Prerequisites**: M2, M3, M4, M5. [Roadmap](../../docs/planning/roadmap.md).
**Scope**: Integrated contract parity, performance, complete limitation audit, native UI and physical regression evidence.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Audit integrated quality (Priority: P1)

User or reviewer obtains verified milestone outcome: CLI/GUI contracts, safety/security/privacy/recovery, performance, native computer-use and physical evidence audited; zero critical/high defects.

**Why this priority**: Required to deliver ai quality gate and protect downstream gates.
**Independent Test**: CLI/GUI contracts, safety/security/privacy/recovery, performance, native computer-use and physical evidence audited; zero critical/high defects.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** CLI/GUI contracts, safety/security/privacy/recovery, performance, native computer-use and physical evidence audited; zero critical/high defects.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### Edge Cases
Every L01–L20; impossible OS/joint recovery remains explicit residual, never solved. Failed prerequisites, unsupported versions, absent evidence and accidental
simulation-as-hardware claims must remain visible. [Limitations](../../docs/planning/limitations.md).

## Requirements *(mandatory)*

### Functional Requirements
Stable FR identifiers refer to shared product requirements, not a second set of product defaults.
Scope statements below narrow delivery ownership; complete invariants/values remain authoritative
in [product specification](../../docs/planning/product-spec.md).

- **FR-017**: Deliver scoped behavior for [product FR-017](../../docs/planning/product-spec.md#functional-requirements): Expose shared-policy inspection/configuration/simulation and enrolled command CLI. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-020**: Deliver scoped behavior for [product FR-020](../../docs/planning/product-spec.md#functional-requirements): Require AI contract/recovery/security/performance/native UI and physical evidence before user trials. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-022**: Deliver scoped behavior for [product FR-022](../../docs/planning/product-spec.md#functional-requirements): Separate lease deadlines from restoration and helper/OS failure guarantees. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-023**: Deliver scoped behavior for [product FR-023](../../docs/planning/product-spec.md#functional-requirements): Prefer compatible OS expiration; persistent backend needs independent single-helper-failure recovery and valid ownership. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-024**: Deliver scoped behavior for [product FR-024](../../docs/planning/product-spec.md#functional-requirements): Revalidate changed OS/model/backend/helper protocol before closed-lid arming. Full numeric invariants remain in product source; delivery limited to stated milestone scope.

### Key Entities
Relevant evidence/state follows [data-model.md](data-model.md); shared runtime definitions
remain in [domain model](../../docs/planning/domain-model.md).

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **SC-004**: Milestone evidence MUST establish [product SC-004](../../docs/planning/product-spec.md#measurable-outcomes) within its scope; downstream/integrated checks remain explicitly deferred.
- **SC-005**: Milestone evidence MUST establish [product SC-005](../../docs/planning/product-spec.md#measurable-outcomes) within its scope; downstream/integrated checks remain explicitly deferred.
- **SC-006**: Milestone evidence MUST establish [product SC-006](../../docs/planning/product-spec.md#measurable-outcomes) within its scope; downstream/integrated checks remain explicitly deferred.
- **SC-008**: Milestone evidence MUST establish [product SC-008](../../docs/planning/product-spec.md#measurable-outcomes) within its scope; downstream/integrated checks remain explicitly deferred.

**Milestone exit gate**: PASS report with no critical/high defects or failed mandatory limitation gate; otherwise M7 blocked.

## Assumptions
Current operation edits planning documents only. Independent AI review, deterministic CLI scenarios, native computer-use and supervised physical evidence; simulated/hardware results distinct.
Tests required where scoped validation changes safety, detection, native UX or release behavior.
M1–M7 tasks remain unexecuted; physical feasibility and future deliverables are not established by
this spec. M0 completed documentation work does not establish runtime support.

## Added M4a dependency (2026-10-05)

[Apple HIG UI/UX milestone](../009-apple-hig-ux/spec.md) is required before this milestone final approval. Preparation may overlap; the accepted candidate must include M4a evidence and no unresolved critical/high UX finding. M4a does not replace M1 physical recovery or other existing gates.
