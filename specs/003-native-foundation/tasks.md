# Tasks: M2 Native Foundation and Safety

**Input**: spec.md, plan.md, research.md, data-model.md, relevant contracts.
**Status**: Preview integration implemented and under fresh verification; M2 gate remains pending M1/backend/helper/hardware. Checked tasks describe completed scoped components, not milestone approval.
**Format**: Local T### IDs; [US#] refers to this milestone spec; [P] independent files after prerequisites.

## Phase 1: Setup prerequisites

- [x] T001 Create native app/CLI/local-core targets in CamLid.xcodeproj and Packages/CamLidCore/Package.swift; pin toolchain/build commands in README.md (FR-001, FR-017). xcodeproj generated from project.yml (CamLid app + camlid tool, local package); app launches, no crash, clean quit.

## Phase 2: Foundational prerequisites

- [x] T002 Define validated entities in Packages/CamLidCore/Sources/CamLidCore/Models.swift: batteryPercent 0–100 optional, cpuPercent 0–100 optional, session/run IDs nonempty ≤128 chars, strings ≤256 chars (FR-007, FR-009, FR-011).
- [x] T003 Implement serialized shared policy with all mode/safety/deadline transitions in Packages/CamLidCore/Sources/CamLidCore/PolicyEngine.swift (FR-002, FR-004, FR-008, FR-010, FR-012).
- [x] T004 Implement atomic configuration validation/schema migration in Packages/CamLidCore/Sources/CamLidCore/Configuration.swift: completion 0–30 default 2, wait 0–30 default 5, floor 10–50 default 20, cap 5–480 default 120, charging-only true, CPU-stop false (FR-004, FR-008, FR-009, FR-012, FR-015).
- [x] T005 Implement authenticated same-user app/CLI IPC and bounded payloads in CamLidCLI/Client.swift and CamLidApp/ControlService.swift; 64 KiB event bound, fixed allowlisted commands (FR-017).
- [x] T006 [P] Implement isolated fake clock/sensors/power simulator in CamLidCLI/Simulator.swift; reject real-power effect access (FR-017, SC-002).
- [x] T007 Add deterministic policy hazards including grace races, clock jumps, lid-open completion, cap not resetting, explicit re-arm in Packages/CamLidCore/Tests/CamLidCoreTests/PolicyTests.swift (SC-002).
- [x] T008 Create deterministic acceptance fixture matrix in Tests/Contracts/Fixtures/ covering all policy hazards without host mutation (FR-020, SC-002).

## Phase 3: User Story 1 — Enforce health and bounded safety

**Independent Test**: Injected battery/thermal/CPU/AC/stale/capacity cases override all modes and latch safety stop.

- [ ] T009 [US1] Implement battery/AC/thermal/lid/display telemetry and freshness in Packages/CamLidCore/Sources/CamLidCore/HealthMonitor.swift; unknown is not healthy, disconnected is not asleep (FR-009, FR-010, FR-014).
- [x] T010 [US1] Implement normalized CPU measurement/advisory with 90% sustained 120s and optional stop in Packages/CamLidCore/Sources/CamLidCore/CPUObserver.swift (FR-011).
- [x] T011 [US1] Enforce serious thermal 30s, critical immediate, 5s sampling, 15s stale telemetry stop, battery/AC cutoff and latched re-arm in Packages/CamLidCore/Sources/CamLidCore/SafetyPolicy.swift (FR-009, FR-010, FR-012).
- [ ] T012 [US1] If helper required, enforce independent safety/cap/watchdog and monitor-loss expiry in CamLidHelper/SafetyMonitor.swift (FR-009, FR-010, FR-013).
- [x] T013 [US1] Add boundary/stale/missing battery and thermal/CPU/AC fixture tests in Packages/CamLidCore/Tests/CamLidCoreTests/SafetyTests.swift; prove safety overrides all modes (SC-002).
- [ ] T014 [US1] Test >20 task rejection, event flood, control starvation and stale health in Packages/CamLidCore/Tests/CamLidCoreTests/SafetyTests.swift and ControlFloodTests.swift; preserve enrolled work, no unsafe journal writes on storage failure (FR-025).

## Phase 4: User Story 2 — Preserve work and restore power

**Independent Test**: Wrapper run continues on verified hardware; completion/grace/restoration/manual Sleep and executor failures satisfy failure-class targets.

- [ ] T015 [US2] Implement chosen bounded idle/closed-lid backend in CamLidHelper/PowerBackend.swift if helper required; otherwise Packages/CamLidCore/Sources/CamLidCore/PowerBackend.swift; display sleep by default; optional owned display hold only for the explicit lid-open preference (M8 amendment 2026-10-08); closed-lid internal display sleep remains required (FR-003, FR-021).
- [ ] T016 [US2] If privileged backend selected, implement signed client validation/lease/watchdog in CamLidHelper/Service.swift; renew every 10s, lease deadline ≤30s; healthy-executor verified restore target ≤35s, separate helper-failure timing (FR-013, FR-022).
- [ ] T017 [US2] If global backend selected, implement atomic owned journal/read-back/conflict refusal in CamLidHelper/RecoveryJournal.swift; reject pre-existing overrides and cross-user conflicts (FR-013, FR-021).
- [ ] T018 [US2] If persistent backend selected, implement chosen independent recovery and authenticated owned-state rescue in CamLidHelper/RecoveryService.swift; same-process timer insufficient for hang, no OS-hang guarantee (FR-022, FR-023, FR-026).
- [ ] T019 [US2] Test journal corruption/full disk/read-only storage/crash points/conflicts/stalled writer and OS-build/protocol invalidation in Packages/CamLidCore/Tests/CamLidCoreTests/RecoveryTests.swift (FR-023, FR-024, FR-025).
- [x] T020 [US2] Implement restoration-before-sleep, lid-open release, observed/requested/blocked outcomes in Packages/CamLidCore/Sources/CamLidCore/PowerController.swift (FR-004, FR-005).
- [x] T021 [US2] Implement enrolled command wrapper and inherited exit status in CamLidCLI/RunCommand.swift without treating detached processes as complete (FR-007, FR-017).
- [ ] T022 [US2] Verify normal end, timer, Stop/Quit, app/helper death, restart/reboot, manual Sleep and external assertion blockers in Tests/Hardware/RecoveryValidation.md (FR-005, FR-013, SC-001).

## Phase 5: User Story 3 — Inspect and recover through CLI

**Independent Test**: CLI config/status use app policy; owned-only rescue reaches restricted helper without app; unknown ownership rejected.

- [ ] T023 [US3] Implement status/agents/config validate/get/set/dry-run/start/stop/doctor/event/log export commands in CamLidCLI/main.swift per specs/003-native-foundation/contracts/cli.md; history commands report unavailable until M4 store integration, never synthetic success (FR-017).
- [ ] T024 [US3] Implement dry-run/default owned-only recovery and explicit apply direct to restricted helper in CamLidCLI/RecoveryCommand.swift; verify denied authorization/app unavailable/conflict/unknown outcomes in Tests/Contracts/RecoveryCLITests.swift (FR-022, FR-026).
- [x] T025 [US3] Document CLI installation and future exact build/test commands in README.md and specs/003-native-foundation/quickstart.md (FR-017).

## Dependencies & Execution Order

Prerequisites: M1. Tasks in setup/foundation precede story work. Tasks inside each story stay ordered unless [P] explicitly marks separate files.
M2 safety story completes before live power tests in M2 power story; policy/simulator can run before physical arming.
M3 adapters [P] depend on shared evidence normalizer. M4 may overlap M3 on simulated policy; M5 needs both.
M6 consumes integrated M2–M5; only M6 PASS enables M7. No future gate is complete from document checks.

## Parallel Opportunities

Only tasks explicitly marked [P] may run concurrently after prerequisites; serialize shared power/journal mutations.
Independent story validation follows spec.md; multi-story milestone joins its stories at exit gate.

## Implementation Strategy

Safety, journal, recovery and CLI foundation verified; no unsafe live protection; full native dashboard parity deferred to M6.
Current authorization permits scoped preview implementation and QA; external publication remains unauthorized.

## Runtime refinement evidence (2026-10-05)

- T009 partial: battery/thermal/normalized CPU/built-in display are live and read-only; lid stays unknown pending qualified collector/physical evidence.
- T014 partial: bounded same-user framing/event enrollment and incomplete-peer/handler/export saturation regressions exist; integrated flood, health starvation and durable storage-fault acceptance still required. The 2026-10-09 [backend readiness reassessment](../../docs/qa/backend-readiness.md) adds real CLI/coordinator transport refusal checks for active Auto/Timed Preview, protected child non-launch, blocked sleep, and preserved session/deadline/revision. These guard regressions do not close T014 or qualify a backend.
- T019 partial: in-memory journal corruption/crash-point tests exist; durable helper journal/full-disk/stalled-writer evidence is conditional on M1.
- T023 partial: actual app config/status/events/history and CLI binary tests exist; protection start deliberately denied until backend verified.
- T024 partial: dry-run/restorable/unresolved semantics tested; restricted helper transport and physical confirming restoration await M1/M5.
- [x] T026 Implement native normalized CPU sampling, continuous elapsed time, built-in display identification and critical thermal notification delivery; add CPU/display regressions.
- [x] T027 Connect real unprivileged app/CLI transport and persisted config/revision; authenticate kernel peer UID, bound framing/waits, test isolated endpoint ownership and actual CLI binary.
- [X] T028 Isolate control handlers from incomplete frames, occupied event handlers and slow export replies in LocalControlTransport.swift; bound connections/response reservations, preserve priority reply headroom, preempt only safe readers/read-only responses, and pin shutdown/restart semantics in ControlFloodTests.swift. Component scope only; does not close T014's integrated monitor/storage/helper load gate.
