# Feature Specification: M2 Native Foundation and Safety

> **Deployment note (2026-10-30):** helper deployment follows [spec 014](../014-persistent-helper/spec.md) and [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md) (root LaunchDaemon installed once with administrator authentication). Admission and one-use wording below describes the earlier, now experimental Strict model.

**Feature Branch**: None; numbered folder is feature identity, not Git branch.
**Created**: 2026-10-04
**Status**: Planned; blocked on M1 PASS
**Input**: CamLid milestone M2: Native targets, shared policy/entities/configuration, telemetry, conditional power/recovery helper, CLI/simulator. One scoped feature folder per user instruction.
**Prerequisites**: M1. Roadmap.
**Scope**: Native targets, shared policy/entities/configuration, telemetry, conditional power/recovery helper, CLI/simulator.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enforce health and bounded safety (Priority: P1)

User or reviewer obtains verified milestone outcome: Injected battery/thermal/CPU/AC/stale/capacity cases override all modes and latch safety stop.

**Why this priority**: Required to deliver native foundation and safety and protect downstream gates.
**Independent Test**: Injected battery/thermal/CPU/AC/stale/capacity cases override all modes and latch safety stop.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** Injected battery/thermal/CPU/AC/stale/capacity cases override all modes and latch safety stop.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### User Story 2 - Preserve work and restore power (Priority: P2)

User or reviewer obtains verified milestone outcome: Wrapper run continues on verified hardware; completion/grace/restoration/manual Sleep and executor failures satisfy failure-class targets.

**Why this priority**: Required to deliver native foundation and safety and protect downstream gates.
**Independent Test**: Wrapper run continues on verified hardware; completion/grace/restoration/manual Sleep and executor failures satisfy failure-class targets.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** Wrapper run continues on verified hardware; completion/grace/restoration/manual Sleep and executor failures satisfy failure-class targets.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### User Story 3 - Inspect and recover through CLI (Priority: P3)

User or reviewer obtains verified milestone outcome: CLI config/status use app policy; owned-only rescue reaches restricted helper without app; unknown ownership rejected.

**Why this priority**: Required to deliver native foundation and safety and protect downstream gates.
**Independent Test**: CLI config/status use app policy; owned-only rescue reaches restricted helper without app; unknown ownership rejected.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** CLI config/status use app policy; owned-only rescue reaches restricted helper without app; unknown ownership rejected.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### Edge Cases
L02–L09, L11–L14, L16–L19; OS/joint failures remain residual. Failed prerequisites, unsupported versions, absent evidence and accidental
simulation-as-hardware claims must remain visible. Limitations.

## Requirements *(mandatory)*

### Functional Requirements
Stable FR identifiers refer to shared product requirements, not a second set of product defaults.
Scope statements below narrow delivery ownership; complete invariants/values remain authoritative
in product specification.

- **FR-001**: Deliver scoped behavior for product FR-001: Provide native menu bar lifecycle and dashboard/options/settings interactions. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-002**: Deliver scoped behavior for product FR-002: Keep requested mode separate from effective protection; safety overrides every mode. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-003**: Deliver scoped behavior for product FR-003: Establish task continuity with lid closed and internal display asleep on verified combinations. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-004**: Deliver scoped behavior for product FR-004: Apply configurable completion grace and cancel it on fresh work. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-005**: Deliver scoped behavior for product FR-005: Restore owned state before closed-lid sleep request; distinguish requested, observed and blocked sleep. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-007**: Deliver scoped behavior for product FR-007: Track run identity, activity states, concurrent enrolled tasks and evidence-backed children. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-008**: Deliver scoped behavior for product FR-008: Bound waiting/unknown retention; process discovery alone cannot arm Auto. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-009**: Deliver scoped behavior for product FR-009: Enforce battery floor/AC policy and bounded stop on missing safety data. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-010**: Deliver scoped behavior for product FR-010: Apply thermal-pressure stop policy and explicit re-arm after safety stop. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-011**: Deliver scoped behavior for product FR-011: Use normalized CPU advisory with optional stop; never infer task completion or thermal safety from CPU. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-012**: Deliver scoped behavior for product FR-012: Enforce nonresetting runtime cap for every protection session. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-013**: Deliver scoped behavior for product FR-013: Release owned resources and verify restoration with failure-class timing. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-014**: Deliver scoped behavior for product FR-014: Expose effective reason, health/freshness, agent confidence, deadlines and cleanup outcome. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-015**: Deliver scoped behavior for product FR-015: Validate preferences and preserve opt-in provider configuration with preview/removal. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-017**: Deliver scoped behavior for product FR-017: Expose shared-policy inspection/configuration/simulation and enrolled command CLI. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-020**: Deliver scoped behavior for product FR-020: Require AI contract/recovery/security/performance/native UI and physical evidence before user trials. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-021**: Deliver scoped behavior for product FR-021: Refuse unsupported/uncertain closed-lid behavior; disclose safety and unsaved-work limits. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-022**: Deliver scoped behavior for product FR-022: Separate lease deadlines from restoration and helper/OS failure guarantees. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-023**: Deliver scoped behavior for product FR-023: Prefer compatible OS expiration; persistent backend needs independent single-helper-failure recovery and valid ownership. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-024**: Deliver scoped behavior for product FR-024: Revalidate changed OS/model/backend/helper protocol before closed-lid arming. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-025**: Deliver scoped behavior for product FR-025: Handle storage/journal/load faults, reject excess enrollment and preserve control/safety servicing. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-026**: Deliver scoped behavior for product FR-026: Allow authenticated owned-only recovery when app policy is unavailable; never guess unknown original state. Full numeric invariants remain in product source; delivery limited to stated milestone scope.

### Key Entities
Relevant evidence/state follows [data-model.md](data-model.md); shared runtime definitions
remain in domain model.

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **SC-001**: Milestone evidence MUST establish product SC-001 within its scope; downstream/integrated checks remain explicitly deferred.
- **SC-002**: Milestone evidence MUST establish product SC-002 within its scope; downstream/integrated checks remain explicitly deferred.

**Milestone exit gate**: Safety, journal, recovery and CLI foundation verified; no unsafe live protection; full native dashboard parity deferred to M6.

## Assumptions
Current operation edits planning documents only. Shared policy/contract simulator and supervised physical backend tests; safety complete before any live protected demo.
Tests required where scoped validation changes safety, detection, native UX or release behavior.
M1–M7 tasks remain unexecuted; physical feasibility and future deliverables are not established by
this spec. M0 completed documentation work does not establish runtime support.
