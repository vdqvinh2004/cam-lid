# Implementation Plan: M1 Power and Detection Feasibility

**Branch**: None | **Date**: 2026-10-04 | **Spec**: [spec.md](spec.md)
**Input**: specs/002-power-feasibility/spec.md
**Status**: Planned; next active milestone; preview implementation/QA now authorized; predecessor gates still apply.

## Summary
Continuity-first owner revision (2026-10-11): independent AI workload progress while the physical lid is closed is primary. Panel sleep is deferred; observations remain truthful, brightness is optional/manual and no display-awake assertion is introduced. Synchronize product/M1/hardware protocol and isolate lab admission changes/fake regressions; retain every thermal/AC/battery/lid/topology/freshness, Stop/deadline/authentication and restoration guard. New source invalidates prior review/artifact pins; native gate remains false and actual trials require exact later approval.

Power backend candidates, initial agent lifecycle probes, exact support matrix and recovery topology. Backend/support matrix selected only after mandatory tests pass; persistent candidate demonstrates single-helper crash/hang recovery; otherwise STOP.

## Technical Context
**Language/Version and Primary Dependencies**: Reversible scoped test harness and existing macOS tools; exact SDK/backend chosen only after evidence.
**Storage**: Shared policy/configuration/history/journal definitions in domain model; evidence artifacts scoped by tasks.md.
**Testing**: Supervised hardware runs plus isolated fault fixtures.
**Target Platform**: Proposed macOS 14+, Apple Silicon first; exact hardware/OS/backend rows require M1 evidence.
**Project Type**: Native macOS utility or its scoped feasibility/quality validation feature.
**Performance Goals**: Inherit product SC-005 where applicable; measurement performed M6.
**Constraints**: Preview implementation authorized; live actuation gated by M1; safety before live protection, no transcript collection,
30s lease deadline distinct from restoration, OS/joint failure remains residual.
**Scale/Scope**: Power backend candidates, initial agent lifecycle probes, exact support matrix and recovery topology. No downstream feature absorbed into this task list.

## Constitution Check
[Constitution](../../.specify/memory/constitution.md) applies. Pre-research and post-design checks:
safety/recovery limits, evidence confidence, native accessibility, shared GUI/CLI policy and privacy
preserved by scoped contracts and dependencies. No exceptions. Document migration does not pass
hardware or runtime gates. Shared architecture governs seams.

## Project Structure
Feature docs: spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md, checklists/.
Relevant future source or validation paths (not created now):
- `docs/qa/feasibility-report.md`
- `docs/qa/agent-compatibility.md`
- `Tests/Hardware/PowerFeasibility.md`
- `docs/qa/backend-comparison.md`
- `Tests/Hardware/RecoveryFailureMatrix.md`
- `docs/qa/recovery-design.md`
- `docs/planning/limitations.md`
- `specs/002-power-feasibility/research.md`

## Phase 0: Research Decisions
See [research.md](research.md). Inherited primary-source findings and product decisions remain
in shared research. Future evidence choices tracked
as mandatory tasks; unverified backend/provider compatibility is not a resolved physical fact.

## Phase 1: Design and Contracts
[Model](data-model.md) defines relevant entities/evidence; [quickstart](quickstart.md) defines
validation sequence and expected results. Runtime contract owners are M2 (CLI/helper) and M3
(agent events); later milestones consume those contracts without copying implementation.

This milestone has no new runtime protocol; evidence/output expectations below and shared contracts govern validation.

## Dependencies and Exit Gate
Prerequisites: M0. Each prerequisite must meet its documented gate; planned docs do not
satisfy that prerequisite. Backend/support matrix selected only after mandatory tests pass; persistent candidate demonstrates single-helper crash/hang recovery; otherwise STOP. M3 and M4 may overlap after M2; M5 joins both; M6 PASS
must precede M7. Failed core feasibility does not become fulfilled idle-only fallback.

## Complexity Tracking
No new runtime architecture/dependency introduced by splitting specs. Conditional privileged/
independent recovery services require M1 need/evidence decision; no speculative service created.
