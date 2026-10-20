# Implementation Plan: M7 Supervised Real User Testing

**Branch**: None | **Date**: 2026-10-04 | **Spec**: [spec.md](spec.md)
**Input**: specs/008-user-testing/spec.md
**Status**: Planned; blocked on M6 PASS; preview implementation/QA now authorized; predecessor gates still apply.

## Summary
Anonymized trial protocol, participants including Orca workflow, findings and release recommendation. User metrics recorded; no unexplained safety/restore failure; any fix requires relevant M6 rerun before wider trial.

## Technical Context
**Language/Version and Primary Dependencies**: Signed M6-approved candidate and anonymized trial evidence; no new runtime architecture.
**Storage**: Shared policy/configuration/history/journal definitions in [domain model](../../docs/planning/domain-model.md); evidence artifacts scoped by tasks.md.
**Testing**: Supervised five-user protocol on prevalidated participant configurations.
**Target Platform**: Proposed macOS 14+, Apple Silicon first; exact hardware/OS/backend rows require M1 evidence.
**Project Type**: Native macOS utility or its scoped feasibility/quality validation feature.
**Performance Goals**: Inherit product SC-005 where applicable; measurement performed M6.
**Constraints**: Preview implementation authorized; live actuation gated by M1; safety before live protection, no transcript collection,
30s lease deadline distinct from restoration, OS/joint failure remains residual.
**Scale/Scope**: Anonymized trial protocol, participants including Orca workflow, findings and release recommendation. No downstream feature absorbed into this task list.

## Constitution Check
[Constitution](../../.specify/memory/constitution.md) applies. Pre-research and post-design checks:
safety/recovery limits, evidence confidence, native accessibility, shared GUI/CLI policy and privacy
preserved by scoped contracts and dependencies. No exceptions. Document migration does not pass
hardware or runtime gates. Shared [architecture](../../docs/planning/architecture.md) governs seams.

## Project Structure
Feature docs: spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md, checklists/.
Relevant future source or validation paths (not created now):
- `docs/qa/user-test-plan.md`
- `docs/qa/user-test-report.md`

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
Prerequisites: M6. Each prerequisite must meet its documented gate; planned docs do not
satisfy that prerequisite. User metrics recorded; no unexplained safety/restore failure; any fix requires relevant M6 rerun before wider trial. M3 and M4 may overlap after M2; M5 joins both; M6 PASS
must precede M7. Failed core feasibility does not become fulfilled idle-only fallback.

## Complexity Tracking
No new runtime architecture/dependency introduced by splitting specs. Conditional privileged/
independent recovery services require M1 need/evidence decision; no speculative service created.
