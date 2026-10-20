# Feature Specification: M1 Power and Detection Feasibility

**Feature Branch**: None; numbered folder is feature identity, not Git branch.
**Created**: 2026-10-04
**Status**: In progress; continuity-first scope synchronized 2026-10-11; no physical support row qualified
**Input**: CamLid milestone M1: Power backend candidates, initial agent lifecycle probes, exact support matrix and recovery topology. One scoped feature folder per user instruction.
**Prerequisites**: M0. [Roadmap](../../docs/planning/roadmap.md).
**Scope**: Power backend candidates, initial agent lifecycle probes, exact support matrix and recovery topology.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Prove closed-lid capability and recovery (Priority: P1)

User or reviewer obtains verified milestone outcome: enrolled work continues during three 30-minute runs per supported row with confirmed physical lid closure and independent progress evidence. Normal/manual Sleep and recovery remain mandatory; panel state is reported without claiming verified panel sleep.

**Why this priority**: Required to deliver power and detection feasibility and protect downstream gates.
**Independent Test**: Three 30-minute runs per supported row verify independent work wholly inside confirmed closed-lid intervals, with declared cadence and clock uncertainty; normal/manual Sleep and recovery faults recorded.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** three 30-minute runs demonstrate independent closed-lid work progress and verified restoration/normal Sleep without a screen-off claim.
2. **Given** fresh valid safety/lid/topology and independent closed-lid work progress, **When** panel reports Awake or Unknown, **Then** record that value without rejecting continuity solely because of panel state; initial attended preparation remains open-lid/awake.
3. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### Edge Cases
L01–L12 and L17; every L01–L20 receives verified/conditional/residual/blocked disposition. Failed prerequisites, unsupported versions, absent evidence and accidental
simulation-as-hardware claims must remain visible. [Limitations](../../docs/planning/limitations.md).

## Requirements *(mandatory)*

### Functional Requirements
Stable FR identifiers refer to shared product requirements, not a second set of product defaults.
Scope statements below narrow delivery ownership; complete invariants/values remain authoritative
in [product specification](../../docs/planning/product-spec.md).

- **FR-003**: Document and test feasibility for [product FR-003](../../docs/planning/product-spec.md#functional-requirements): Establish independent enrolled-work progress with the physical lid closed on verified combinations; panel-sleep proof deferred, not passed. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-005**: Document and test feasibility for [product FR-005](../../docs/planning/product-spec.md#functional-requirements): Restore owned state before closed-lid sleep request; distinguish requested, observed and blocked sleep. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-006**: Document and test feasibility for [product FR-006](../../docs/planning/product-spec.md#functional-requirements): Version and label exact/inferred support for Claude Code, Codex CLI, OpenCode and local Orca. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-007**: Document and test feasibility for [product FR-007](../../docs/planning/product-spec.md#functional-requirements): Track run identity, activity states, concurrent enrolled tasks and evidence-backed children. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-013**: Document and test feasibility for [product FR-013](../../docs/planning/product-spec.md#functional-requirements): Release owned resources and verify restoration with failure-class timing. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-021**: Document and test feasibility for [product FR-021](../../docs/planning/product-spec.md#functional-requirements): Refuse unsupported/uncertain closed-lid behavior; disclose safety and unsaved-work limits. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-022**: Document and test feasibility for [product FR-022](../../docs/planning/product-spec.md#functional-requirements): Separate lease deadlines from restoration and helper/OS failure guarantees. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-023**: Document and test feasibility for [product FR-023](../../docs/planning/product-spec.md#functional-requirements): Prefer compatible OS expiration; persistent backend needs independent single-helper-failure recovery and valid ownership. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-024**: Document and test feasibility for [product FR-024](../../docs/planning/product-spec.md#functional-requirements): Revalidate changed OS/model/backend/helper protocol before closed-lid arming. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-025**: Document and test feasibility for [product FR-025](../../docs/planning/product-spec.md#functional-requirements): Handle storage/journal/load faults, reject excess enrollment and preserve control/safety servicing. Full numeric invariants remain in product source; delivery limited to stated milestone scope.

### Key Entities
Relevant evidence/state follows [data-model.md](data-model.md); shared runtime definitions
remain in [domain model](../../docs/planning/domain-model.md).

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **SC-001**: Complete three supervised 30-minute runs per candidate support row with independent progress markers wholly inside confirmed closed-lid intervals, documented cadence/clock uncertainty and no unexplained gaps; separately verify restoration and completion sleep. Internal-panel sleep qualification is deferred, not passed.
- **SC-003**: Record one version-pinned lifecycle capability probe for each Claude Code/Codex CLI/OpenCode and Orca host. This is precursor evidence; 20-run exact support verification belongs to M3.
- **SC-008**: Disposition all L01–L20 with evidence/conditional/residual/blocked status; failed mandatory recovery rejects backend before implementation commitment.

**Milestone exit gate**: Backend/support matrix selected only after mandatory tests pass; persistent candidate demonstrates single-helper crash/hang recovery; otherwise STOP.

## Assumptions
Current user authorization covers requirement synchronization and code/fake-test changes, not native power actions, physical lid transitions or real provider spend. The current phase makes no screen-off claim; optional brightness reduction neither proves continuity nor adds automatic dimming. Existing exact-action/attended prerequisites and all non-panel safety/recovery gates remain mandatory. Archived outcomes are unchanged.

Current operation updates the existing M1 feature; no extra feature folder or branch is required. Supervised reversible hardware matrix plus isolated fault simulation; no kernel freezing/overheating.
Tests required where scoped validation changes safety, detection, native UX or release behavior.
M1–M7 tasks remain unexecuted; physical feasibility and future deliverables are not established by
this spec. M0 completed documentation work does not establish runtime support.
