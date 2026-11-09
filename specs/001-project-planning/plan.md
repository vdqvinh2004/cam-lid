# Implementation Plan: M0 Project Planning

**Branch**: None | **Date**: 2026-10-04 | **Spec**: [spec.md](spec.md)
**Input**: specs/001-project-planning/spec.md
**Status**: Complete: documentation only; preview implementation/QA now authorized; predecessor gates still apply.

## Summary
Research, governance, UX direction, milestone specifications and backlog. Documentation and milestone structure validated; no feasibility/runtime pass claimed.

## Technical Context
**Language/Version and Primary Dependencies**: Markdown and Spec Kit 1.0.7; no application toolchain required.
**Storage**: Shared policy/configuration/history/journal definitions in domain model; evidence artifacts scoped by tasks.md.
**Testing**: Document/link/metadata validation.
**Target Platform**: Proposed macOS 14+, Apple Silicon first; exact hardware/OS/backend rows require M1 evidence.
**Project Type**: Native macOS utility or its scoped feasibility/quality validation feature.
**Performance Goals**: Inherit product SC-005 where applicable; measurement performed M6.
**Constraints**: Preview implementation authorized; live actuation gated by M1; safety before live protection, no transcript collection,
30s lease deadline distinct from restoration, OS/joint failure remains residual.
**Scale/Scope**: Research, governance, UX direction, milestone specifications and backlog. No downstream feature absorbed into this task list.

## Constitution Check
[Constitution](../../.specify/memory/constitution.md) applies. Pre-research and post-design checks:
safety/recovery limits, evidence confidence, native accessibility, shared GUI/CLI policy and privacy
preserved by scoped contracts and dependencies. No exceptions. Document migration does not pass
hardware or runtime gates. Shared architecture governs seams.

## Project Structure
Feature docs: spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md, checklists/.
Relevant future source or validation paths (not created now):
- Shared planning artifacts in docs/planning/, project constitution and eight milestone folders.

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
Prerequisites: None. Each prerequisite must meet its documented gate; planned docs do not
satisfy that prerequisite. Documentation and milestone structure validated; no feasibility/runtime pass claimed. M3 and M4 may overlap after M2; M5 joins both; M6 PASS
must precede M7. Failed core feasibility does not become fulfilled idle-only fallback.

## Complexity Tracking
No new runtime architecture/dependency introduced by splitting specs. Conditional privileged/
independent recovery services require M1 need/evidence decision; no speculative service created.
