# Implementation Plan: M3 Agents and Orca Integration

**Branch**: None | **Date**: 2026-10-04 | **Spec**: [spec.md](spec.md)
**Input**: specs/004-agent-integration/spec.md
**Status**: Planned; blocked on M2 PASS; preview implementation/QA now authorized; predecessor gates still apply.

## Summary
Claude Code, Codex CLI, OpenCode, Orca local status adapter, process-only fallback and integration install/remove. Exact/inferred tiers honest, opt-in configuration preserved, installed-version lifecycle and concurrency cases pass.

## Technical Context
**Language/Version and Primary Dependencies**: Versioned provider hooks/events and Orca JSON CLI; adapters in shared Swift core.
**Storage**: Shared policy/configuration/history/journal definitions in [domain model](../../docs/planning/domain-model.md); evidence artifacts scoped by tasks.md.
**Testing**: Adapter fixtures and installed-version 20-run/provider matrix.
**Target Platform**: Proposed macOS 14+, Apple Silicon first; exact hardware/OS/backend rows require M1 evidence.
**Project Type**: Native macOS utility or its scoped feasibility/quality validation feature.
**Performance Goals**: Inherit product SC-005 where applicable; measurement performed M6.
**Constraints**: Preview implementation authorized; live actuation gated by M1; safety before live protection, no transcript collection,
30s lease deadline distinct from restoration, OS/joint failure remains residual.
**Scale/Scope**: Claude Code, Codex CLI, OpenCode, Orca local status adapter, process-only fallback and integration install/remove. No downstream feature absorbed into this task list.

## Constitution Check
[Constitution](../../.specify/memory/constitution.md) applies. Pre-research and post-design checks:
safety/recovery limits, evidence confidence, native accessibility, shared GUI/CLI policy and privacy
preserved by scoped contracts and dependencies. No exceptions. Document migration does not pass
hardware or runtime gates. Shared [architecture](../../docs/planning/architecture.md) governs seams.

## Project Structure
Feature docs: spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md, checklists/.
Relevant future source or validation paths (not created now):
- `Packages/CamLidCore/Sources/CamLidCore/AgentEvidence.swift`
- `Packages/CamLidCore/Sources/CamLidCore/Adapters/OrcaHostResolver.swift`
- `Packages/CamLidCore/Sources/CamLidCore/Adapters/ClaudeAdapter.swift`
- `Packages/CamLidCore/Sources/CamLidCore/Adapters/CodexAdapter.swift`
- `Packages/CamLidCore/Sources/CamLidCore/Adapters/OpenCodeAdapter.swift`
- `Packages/CamLidCore/Sources/CamLidCore/ProcessDiscovery.swift`
- `Packages/CamLidCore/Sources/CamLidCore/IntegrationInstaller.swift`
- `Packages/CamLidCore/Tests/CamLidCoreTests/AgentTests.swift`
- `docs/qa/agent-compatibility.md`

## Phase 0: Research Decisions
See [research.md](research.md). Inherited primary-source findings and product decisions remain
in [shared research](../../docs/planning/research-decisions.md). Future evidence choices tracked
as mandatory tasks; unverified backend/provider compatibility is not a resolved physical fact.

## Phase 1: Design and Contracts
[Model](data-model.md) defines relevant entities/evidence; [quickstart](quickstart.md) defines
validation sequence and expected results. Runtime contract owners are M2 (CLI/helper) and M3
(agent events); later milestones consume those contracts without copying implementation.

- [agent-events.md](contracts/agent-events.md)

## Dependencies and Exit Gate
Prerequisites: M2. Each prerequisite must meet its documented gate; planned docs do not
satisfy that prerequisite. Exact/inferred tiers honest, opt-in configuration preserved, installed-version lifecycle and concurrency cases pass. M3 and M4 may overlap after M2; M5 joins both; M6 PASS
must precede M7. Failed core feasibility does not become fulfilled idle-only fallback.

## Complexity Tracking
No new runtime architecture/dependency introduced by splitting specs. Conditional privileged/
independent recovery services require M1 need/evidence decision; no speculative service created.
