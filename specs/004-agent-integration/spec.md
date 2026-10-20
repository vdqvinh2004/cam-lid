# Feature Specification: M3 Agents and Orca Integration

**Owner correction — 2026-10-13: integration scope SUPERSEDED by [third-person observation](../../docs/planning/third-person-agent-observation-2026-10-13.md).** Folder identity and older clauses retained for history; no hook/MCP/bridge/provider-event ingestion, agent wrapper or agent configuration changes may satisfy current product requirements. M3 must validate compliant external observation and truthful uncertainty instead. Owner clarification2026-10-14 explicitly permits read-only Orca CLI/runtime metadata, including disclosed local transient mixed JSON processing; latest owner amendment removes separate consent and AX permission UI, keeps Notifications, and retains disclosure/source-off in Agents; source defaults enabled with explicit false preserved, metadata only retained, no content logs/history/export/AI/server transmission. This does not revive producer ingress/hooks/bridge/config writes/jobs. [Restoration verification](../../docs/qa/orca-metadata-restoration-2026-10-14.md) remains open. Old installed-integration/20stream acceptance is not a prerequisite for the revised architecture. Historical integration files remain but CLI/app reject producer ingress. Current software verification passed486eachDebugRelease/build; isolated live QA sees OrcaWorking1 and Codex2/OpenCode4 process presence, standalone statesUnknown. No semantic Working/Idle or power qualification claimed. [Latest verification](../../docs/qa/no-ax-terminal-observation-2026-10-14.md).

**Feature Branch**: None; numbered folder is feature identity, not Git branch.
**Created**: 2026-10-04
**Status**: Planned; blocked on M2 PASS
**Input**: CamLid milestone M3: Claude Code, Codex CLI, OpenCode, Orca local status adapter, process-only fallback and integration install/remove. One scoped feature folder per user instruction.
**Prerequisites**: M2. [Roadmap](../../docs/planning/roadmap.md).
**Scope**: Claude Code, Codex CLI, OpenCode, Orca local status adapter, process-only fallback and integration install/remove.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Track supported local agent work (Priority: P1)

User or reviewer obtains verified milestone outcome: 20 runs/provider plus working/network/approval/idle/completion/crash/child/reconnect/race cases; two Orca tasks aggregate without premature completion.

**Why this priority**: Required to deliver agents and orca integration and protect downstream gates.
**Independent Test**: 20 runs/provider plus working/network/approval/idle/completion/crash/child/reconnect/race cases; two Orca tasks aggregate without premature completion.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** 20 runs/provider plus working/network/approval/idle/completion/crash/child/reconnect/race cases; two Orca tasks aggregate without premature completion.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### Edge Cases
L14–L16, L18; desktop attach remains unverified; remote/untracked detached work disclosed. Failed prerequisites, unsupported versions, absent evidence and accidental
simulation-as-hardware claims must remain visible. [Limitations](../../docs/planning/limitations.md).

## Requirements *(mandatory)*

### Functional Requirements
Stable FR identifiers refer to shared product requirements, not a second set of product defaults.
Scope statements below narrow delivery ownership; complete invariants/values remain authoritative
in [product specification](../../docs/planning/product-spec.md).

- **FR-006**: Deliver scoped behavior for [product FR-006](../../docs/planning/product-spec.md#functional-requirements): Version and label exact/inferred support for Claude Code, Codex CLI, OpenCode and local Orca. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-007**: Deliver scoped behavior for [product FR-007](../../docs/planning/product-spec.md#functional-requirements): Track run identity, activity states, concurrent enrolled tasks and evidence-backed children. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-008**: Deliver scoped behavior for [product FR-008](../../docs/planning/product-spec.md#functional-requirements): Bound waiting/unknown retention; process discovery alone cannot arm Auto. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-015**: Deliver scoped behavior for [product FR-015](../../docs/planning/product-spec.md#functional-requirements): Validate preferences and preserve opt-in provider configuration with preview/removal. Full numeric invariants remain in product source; delivery limited to stated milestone scope.

### Key Entities
Relevant evidence/state follows [data-model.md](data-model.md); shared runtime definitions
remain in [domain model](../../docs/planning/domain-model.md).

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **SC-003**: Milestone evidence MUST establish [product SC-003](../../docs/planning/product-spec.md#measurable-outcomes) within its scope; downstream/integrated checks remain explicitly deferred.

**Milestone exit gate**: Exact/inferred tiers honest, opt-in configuration preserved, installed-version lifecycle and concurrency cases pass.

## Assumptions
Current operation edits planning documents only. Version-pinned provider/Orca event fixtures and installed-agent runs.
Tests required where scoped validation changes safety, detection, native UX or release behavior.
M1–M7 tasks remain unexecuted; physical feasibility and future deliverables are not established by
this spec. M0 completed documentation work does not establish runtime support.
