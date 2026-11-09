# Implementation Plan: M2 Native Foundation and Safety

**Branch**: None | **Date**: 2026-10-04 | **Spec**: [spec.md](spec.md)
**Input**: specs/003-native-foundation/spec.md
**Status**: Planned; blocked on M1 PASS; preview implementation/QA now authorized; predecessor gates still apply.

## Summary
Native targets, shared policy/entities/configuration, telemetry, conditional power/recovery helper, CLI/simulator. Safety, journal, recovery and CLI foundation verified; no unsafe live protection; full native dashboard parity deferred to M6.

## Technical Context
**Language/Version and Primary Dependencies**: Swift 6 proposed, pinned Xcode after M1; SwiftUI/AppKit/Foundation/IOKit/ServiceManagement; conditional helper.
**Storage**: Shared policy/configuration/history/journal definitions in domain model; evidence artifacts scoped by tasks.md.
**Testing**: Swift Testing/XCTest shared policy/CLI/recovery cases and supervised hardware.
**Target Platform**: Proposed macOS 14+, Apple Silicon first; exact hardware/OS/backend rows require M1 evidence.
**Project Type**: Native macOS utility or its scoped feasibility/quality validation feature.
**Performance Goals**: Inherit product SC-005 where applicable; measurement performed M6.
**Constraints**: Preview implementation authorized; live actuation gated by M1; safety before live protection, no transcript collection,
30s lease deadline distinct from restoration, OS/joint failure remains residual.
**Scale/Scope**: Native targets, shared policy/entities/configuration, telemetry, conditional power/recovery helper, CLI/simulator. No downstream feature absorbed into this task list.

## Constitution Check
[Constitution](../../.specify/memory/constitution.md) applies. Pre-research and post-design checks:
safety/recovery limits, evidence confidence, native accessibility, shared GUI/CLI policy and privacy
preserved by scoped contracts and dependencies. No exceptions. Document migration does not pass
hardware or runtime gates. Shared architecture governs seams.

## Project Structure
Feature docs: spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md, checklists/.
Relevant future source or validation paths (not created now):
- `CamLid.xcodeproj`
- `Packages/CamLidCore/Package.swift`
- `README.md`
- `Packages/CamLidCore/Sources/CamLidCore/Models.swift`
- `Packages/CamLidCore/Sources/CamLidCore/PolicyEngine.swift`
- `Packages/CamLidCore/Sources/CamLidCore/Configuration.swift`
- `CamLidCLI/Client.swift`
- `CamLidApp/ControlService.swift`
- `CamLidCLI/Simulator.swift`
- `Packages/CamLidCore/Tests/CamLidCoreTests/PolicyTests.swift`
- `Tests/Contracts/Fixtures/`
- `Packages/CamLidCore/Sources/CamLidCore/HealthMonitor.swift`
- `Packages/CamLidCore/Sources/CamLidCore/CPUObserver.swift`
- `Packages/CamLidCore/Sources/CamLidCore/SafetyPolicy.swift`
- `CamLidHelper/SafetyMonitor.swift`
- `Packages/CamLidCore/Tests/CamLidCoreTests/SafetyTests.swift`
- `Packages/CamLidCore/Tests/CamLidCoreTests/CapacityTests.swift`
- `CamLidHelper/PowerBackend.swift`
- `Packages/CamLidCore/Sources/CamLidCore/PowerBackend.swift`
- `CamLidHelper/Service.swift`
- `CamLidHelper/RecoveryJournal.swift`
- `CamLidHelper/RecoveryService.swift`
- `Packages/CamLidCore/Tests/CamLidCoreTests/RecoveryTests.swift`
- `Packages/CamLidCore/Sources/CamLidCore/PowerController.swift`
- `CamLidCLI/RunCommand.swift`
- `Tests/Hardware/RecoveryValidation.md`
- `CamLidCLI/main.swift`
- `specs/003-native-foundation/contracts/cli.md`
- `CamLidCLI/RecoveryCommand.swift`
- `Tests/Contracts/RecoveryCLITests.swift`
- `specs/003-native-foundation/quickstart.md`

## Phase 0: Research Decisions
See [research.md](research.md). Inherited primary-source findings and product decisions remain
in shared research. Future evidence choices tracked
as mandatory tasks; unverified backend/provider compatibility is not a resolved physical fact.

## Phase 1: Design and Contracts
[Model](data-model.md) defines relevant entities/evidence; [quickstart](quickstart.md) defines
validation sequence and expected results. Runtime contract owners are M2 (CLI/helper) and M3
(agent events); later milestones consume those contracts without copying implementation.

- [cli.md](contracts/cli.md)
- [power-helper.md](contracts/power-helper.md)

## Dependencies and Exit Gate
Prerequisites: M1. Each prerequisite must meet its documented gate; planned docs do not
satisfy that prerequisite. Safety, journal, recovery and CLI foundation verified; no unsafe live protection; full native dashboard parity deferred to M6. M3 and M4 may overlap after M2; M5 joins both; M6 PASS
must precede M7. Failed core feasibility does not become fulfilled idle-only fallback.

## Complexity Tracking
No new runtime architecture/dependency introduced by splitting specs. Conditional privileged/
independent recovery services require M1 need/evidence decision; no speculative service created.
