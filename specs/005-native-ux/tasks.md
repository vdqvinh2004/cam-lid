# Tasks: M4 Native UX and Activity History

**Input**: spec.md, plan.md, research.md, data-model.md, relevant contracts.
**Status**: Hosted native preview views and persisted private history exist; T003 integration workflow and T006 native interaction/accessibility verification remain open. No M4 gate claimed.
**Format**: Local T### IDs; [US#] refers to this milestone spec; [P] independent files after prerequisites.

## Phase 1: Setup prerequisites

Use prerequisite milestone evidence (M2); no separate setup task is added for already-owned work.

## Phase 2: Foundational prerequisites

Shared constitution, product requirements and limitation register apply; dependent milestone gates must pass before scoped work.

## Phase 3: User Story 1 — Control from native menu bar

**Independent Test**: Left/right clicks, keyboard/VoiceOver, settings, unsupported/stale/grace/recovery and long-label states pass native walkthrough.

- [x] T001 [US1] Implement AppKit left/right routing and keyboard Options/Esc behavior in CamLidApp/MenuBarController.swift (FR-001, FR-018).
- [x] T002 [US1] Implement compact state/reason/tasks/health/countdowns/Stop panel in CamLidApp/DashboardView.swift following design-system/camlid/MASTER.md; unknown telemetry explicit (FR-002, FR-014).
- [ ] T003 [US1] Implement single native General/Agents/Safety/Advanced settings in CamLidApp/SettingsView.swift with bounds/errors/integration diff/removal (FR-015).
- [x] T004 [US1] Implement opt-in/permissions/ventilation/rollback onboarding in CamLidApp/OnboardingView.swift (FR-021).
- [x] T005 [US1] Implement status/options accessibility IDs/labels, native focus, dark/light/contrast/reduced-motion support in CamLidApp/Accessibility.swift (FR-018).
- [ ] T006 [US1] Verify unsupported/stale/grace/safety/recovery/long-label/notch states and left/right/settings with native walkthrough in Tests/UI/MenuBarValidation.md (FR-001, FR-014, FR-018).

## Phase 4: User Story 2 — Understand session decisions

**Independent Test**: Session/reason filters, bounded rotation, redacted export/delete omit secrets/transcripts and preserve cleanup outcomes.

- [x] T007 [US2] Implement transition history in Packages/CamLidCore/Sources/CamLidCore/ActivityStore.swift: total retention 14 days or 20 MiB whichever first, no raw transcript; integrate owned CLI history commands after store exists (FR-016).
- [x] T008 [US2] Implement searchable session/reason timeline and redacted export/delete in CamLidApp/ActivityLogView.swift (FR-016).
- [x] T009 [US2] Test log privacy/rotation/redaction/end reasons/cleanup outcome in Packages/CamLidCore/Tests/CamLidCoreTests/ActivityStoreTests.swift (FR-013, FR-016, SC-004).

## Dependencies & Execution Order

Prerequisites: M2. Tasks in setup/foundation precede story work. Tasks inside each story stay ordered unless [P] explicitly marks separate files.
M2 safety story completes before live power tests in M2 power story; policy/simulator can run before physical arming.
M3 adapters [P] depend on shared evidence normalizer. M4 may overlap M3 on simulated policy; M5 needs both.
M6 consumes integrated M2–M5; only M6 PASS enables M7. No future gate is complete from document checks.

## Parallel Opportunities

Only tasks explicitly marked [P] may run concurrently after prerequisites; serialize shared power/journal mutations.
Independent story validation follows spec.md; multi-story milestone joins its stories at exit gate.

## Implementation Strategy

Native control/history accessibility and privacy pass; status never claims restoration from expired lease alone.
Current authorization permits scoped preview implementation and QA; external publication remains unauthorized.

## Runtime refinement evidence (2026-10-05)

T003 partial: native settings validation/provider opt-in exists; actual hook/plugin diff/install/removal remains M3-dependent. Launch-at-login and update UI explicitly unavailable in unsigned preview. T006 remains open because app AX/capture is unavailable in the current desktop state.

- [x] T010 Host durable history/live telemetry in AppCoordinator; reset closed-window drafts on reopen, preserve visible drafts, reject stale config revisions, avoid timer-driven window activation, persist config/revision together, show storage/export failures.
