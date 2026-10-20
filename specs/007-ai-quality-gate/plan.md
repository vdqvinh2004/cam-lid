# Implementation Plan: M6 AI Quality Gate

**Branch**: None | **Date**: 2026-10-04 | **Spec**: [spec.md](spec.md)
**Input**: specs/007-ai-quality-gate/spec.md
**Status**: Planned; required before user trials; preview implementation/QA now authorized; predecessor gates still apply.

## Summary
Integrated contract parity, performance, complete limitation audit, native UI and physical regression evidence. PASS report with no critical/high defects or failed mandatory limitation gate; otherwise M7 blocked.

## Technical Context
**Language/Version and Primary Dependencies**: Existing candidate CLI/simulator plus native computer-use; no new app backend.
**Storage**: Shared policy/configuration/history/journal definitions in [domain model](../../docs/planning/domain-model.md); evidence artifacts scoped by tasks.md.
**Testing**: Integrated contracts, performance/privacy/security, recovery and physical evidence review.
**Target Platform**: Proposed macOS 14+, Apple Silicon first; exact hardware/OS/backend rows require M1 evidence.
**Project Type**: Native macOS utility or its scoped feasibility/quality validation feature.
**Performance Goals**: Inherit product SC-005 where applicable; measurement performed M6.
**Constraints**: Preview implementation authorized; live actuation gated by M1; safety before live protection, no transcript collection,
30s lease deadline distinct from restoration, OS/joint failure remains residual.
**Scale/Scope**: Integrated contract parity, performance, complete limitation audit, native UI and physical regression evidence. No downstream feature absorbed into this task list.

## Constitution Check
[Constitution](../../.specify/memory/constitution.md) applies. Pre-research and post-design checks:
safety/recovery limits, evidence confidence, native accessibility, shared GUI/CLI policy and privacy
preserved by scoped contracts and dependencies. No exceptions. Document migration does not pass
hardware or runtime gates. Shared [architecture](../../docs/planning/architecture.md) governs seams.

## Project Structure
Feature docs: spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md, checklists/.
Relevant future source or validation paths (not created now):
- `Tests/Contracts/CLITests.swift`
- `docs/qa/performance-report.md`
- `docs/qa/ai-quality-report.md`

## Phase 0: Research Decisions
See [research.md](research.md). Inherited primary-source findings and product decisions remain
in [shared research](../../docs/planning/research-decisions.md). Future evidence choices tracked
as mandatory tasks; unverified backend/provider compatibility is not a resolved physical fact.

## Phase 1: Design and Contracts
[Model](data-model.md) defines relevant entities/evidence; [quickstart](quickstart.md) defines
validation sequence and expected results. Runtime contract owners are M2 (CLI/helper) and M3
(agent events); later milestones consume those contracts without copying implementation.

This milestone has no new runtime protocol; evidence/output expectations below and shared contracts govern validation.

## Dependencies and Exit Gate
Prerequisites: M2, M3, M4, M5. Each prerequisite must meet its documented gate; planned docs do not
satisfy that prerequisite. PASS report with no critical/high defects or failed mandatory limitation gate; otherwise M7 blocked. M3 and M4 may overlap after M2; M5 joins both; M6 PASS
must precede M7. Failed core feasibility does not become fulfilled idle-only fallback.

## Complexity Tracking
No new runtime architecture/dependency introduced by splitting specs. Conditional privileged/
independent recovery services require M1 need/evidence decision; no speculative service created.

## Added M4a dependency (2026-10-05)

[Apple HIG UI/UX milestone](../009-apple-hig-ux/spec.md) is required before this milestone final approval. Preparation may overlap; the accepted candidate must include M4a evidence and no unresolved critical/high UX finding. M4a does not replace M1 physical recovery or other existing gates.

## M4b QA refinement dependency (2026-10-05)

[010 plan](../010-qa-ux-sensors/plan.md) adds engineering acceptance SC-001–006 before final M5/M6 approval; SC-007 user outcome follows M6 in M7. Pending/invalid/conflict/failed automatic preference edits replace the old dirty-draft concept for update deferral. Existing certificates/feed/notarization, hardware/provider and quality gates remain unchanged. Historical component evidence does not validate these future edits.

### M4b preview handoff,2026-10-05

Feature010 now implements direct revision-aware settings, presets/Custom input, agent toggle badges, typed read-only lid telemetry and explicit preview blockers.213 Swift tests and five packaging tests; seven preview checks PASS. [Current evidence and remaining gates](../../docs/qa/qa-refinement-report.md). Bounded off-main preference/sensor work, full native/VoiceOver/performance and independent review remain open. No backend/signing/user predecessor is checked by this increment.
