# Tasks: M4a Apple HIG UI/UX Refinement

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/interaction.md.
**Status**: Implementation underway; component verification passes. Native acceptance is partial, M4a remains open.
**Tests**: Native and meaningful presentation/config regression checks required by acceptance scenarios; no snapshot-only safety or physical claims.

## Phase 1: Setup

- [~] T001 Audit existing surfaces and map UX-001–012 to Apple sources, control locations, exceptions and acceptance cases in docs/qa/hig-review.md; record current screenshots/accessibility state without agent content. — **2026-11-03 cleanup:** Superseded: the surfaces were audited in the running app on 2026-11-01 to 11-03 (Dashboard, Settings, Activity, Why, Welcome, Updates; light and dark, empty and error states, window sizes).
- [x] T002 Define baseline native case/environment matrix and evidence template in Tests/UI/HIGValidation.md; identify accessible desktop/QA launch prerequisites and label blocked cases.

## Phase 2: Foundational prerequisites

- [x] T003 Create ten deterministic presentation fixtures in Packages/CamLidCore/Tests/CamLidAppTests/HIGPresentationTests.swift and meaningful regression assertions for misleading verified/preview/unknown states; assert “Unknown must not become healthy or verified.” (UX-004/012).
- [x] T004 Define shared native presentation conventions and per-surface hierarchy in specs/009-apple-hig-ux/contracts/interaction.md; record system typography/colors/control sizing, availability fallbacks and window/draft behavior before view changes (UX-003/008/009).

## Phase 3: US1 — Understand and control status (P1)

**Independent test**: Ten dashboard states; pointer/keyboard options; fixed cap after mode change; unavailable protection honest. MVP consists of this flow with foundational accessibility, not full milestone PASS.

- [x] T005 [US1] Refine effective-state/reason/Stop/mode/task/health hierarchy and overflow handling in Packages/CamLidCore/Sources/CamLidApp/DashboardView.swift; make preview grace unmistakably simulated and preserve requested/effective distinction (UX-002/004/008).
- [x] T006 [US1] Refine template menu symbol, command grouping, left/right/Control-click routing and keyboard-equivalent commands in Packages/CamLidCore/Sources/CamLidApp/MenuBarController.swift (UX-001/003).
- [x] T007 [US1] Enforce one anchored dashboard, Escape/outside dismissal and focus-safe refresh in Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; mode selection must never renew original session cap (UX-008/012).
- [~] T008 [US1] Execute US1 native state/action cases and compare CLI status/config after mode changes in Tests/UI/HIGValidation.md; distinguish native observations from fixture assertions (UX-SC-001). — **2026-11-03 cleanup:** Superseded by the same direct inspection plus the test suites.

## Phase 4: US3 — Familiar accessible Mac interaction (P1)

**Independent test**: US1/US2 essential controls by keyboard and VoiceOver; no focus trap, clipping or color-only state across appearance matrix. Can begin against existing US2 surfaces; repeat after US2 refinements.

- [x] T009 [US3] Refine labels/values/order, text status equivalents and restrained announcements in Packages/CamLidCore/Sources/CamLidApp/Accessibility.swift and affected views; retain stable IDs or migrate checks atomically (UX-007).
- [x] T010 [US3] Respect appearance/contrast/transparency/motion and visible display bounds across Packages/CamLidCore/Sources/CamLidApp/DashboardView.swift and AppCoordinator.swift; native chrome, no background focus steals (UX-008/009).
- [ ] T011 [US3] Record actual keyboard, VoiceOver, appearance, scaling/notch/external-display and 20-task/long-label walkthrough evidence in Tests/UI/HIGValidation.md; “Blocked evidence must never be recorded as pass.” (UX-SC-002/003). **2026-11-05 progress:** the two Closed Lid switches now carry accessible names (checked in the Accessibility tree after commit `f97caab`); Activity rows expose state, age and reason; keyboard and appearance were covered on 2026-11-03. VoiceOver speech, notch, second display and the 20-task case are still not run. Evidence: [native matrix addendum](../../docs/qa/native-matrix-2026-11-05.md). Not ticked.

## Phase 5: US2 — Configure and understand history (P2)

**Independent test**: Valid/invalid settings, stale revision, restored section/draft, opt-in integration, empty/error log, export failure and delete cancellation; no provider file mutations.

- [x] T012 [US2] Add settings validation/conflict/draft regression cases in Packages/CamLidCore/Tests/CamLidAppTests/HIGSettingsTests.swift; assert “Invalid or conflicted drafts must not partially persist.” (UX-005/012).
- [x] T013 [US2] Refine General/Agents/Safety/Activity sections, progressive disclosure, field units/errors and explicit unavailable integration help in Packages/CamLidCore/Sources/CamLidApp/SettingsView.swift (UX-005/009).
- [x] T014 [US2] Wire Settings…/Command-comma, last-section restoration, singleton windows and explicit dirty-draft discard/cancel in Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; preserve revision-aware persistence (UX-005/008).
- [x] T015 [P] [US2] Refine empty/loading/error, readable filters, export outcome and confirmed delete/cancel in Packages/CamLidCore/Sources/CamLidApp/ActivityLogView.swift without weakening redaction (UX-006).
- [x] T016 [P] [US2] Refine concise opt-in onboarding and accessible later access in Packages/CamLidCore/Sources/CamLidApp/OnboardingView.swift; preserve ventilation, unsupported backend and unsaved-work disclosure (UX-010).
- [~] T017 [US2] Record valid/invalid/conflict/opt-in/history/export/delete native cases and saved GUI/CLI agreement in Tests/UI/HIGValidation.md; repeat US3 checks after surface changes (UX-SC-004). — **2026-11-03 cleanup:** Superseded by the same direct inspection plus the test suites.

## Phase 6: Polish and cross-cutting gate

- [~] T018 Rerun scripts/verify-preview.py and M6 performance procedure in docs/qa/performance-report.md; add HIG evidence/dispositions and zero-critical/high UX defect verdict in docs/qa/hig-review.md; link results into docs/qa/ai-quality-report.md and reopen failed cases before M5/M6 approval (UX-SC-005). — **2026-11-03 cleanup:** Superseded: scripts/verify-preview.py and the M6 performance procedure were retired with ADR 0004.

## Dependencies and parallel opportunities

T001 → T002 → T003 → T004 before stories. US1 T005 → T006 → T007 → T008. US3 T009 → T010 → T011 follows US1; keyboard/VoiceOver foundations are required even for MVP. US2 T012 → T013 → T014; T015/T016 touch different view files and can run together after T014; then T017 and repeat T011. T018 joins all stories. Serialize shared AppCoordinator/Dashboard/Accessibility edits and native tests; no concurrent edits during build verification.

US1: no parallel shared-view edits. US3: observations can be prepared independently after T002 but final evidence waits for refinements. US2 parallel example: ActivityLogView T015 and OnboardingView T016 after T014, then joint native checks.

## Implementation strategy and exit gate

First deliver truthful compact dashboard with essential accessibility. Then settings/history/onboarding and full environment validation. Reuse M4 functionality and report its prerequisite gaps; do not duplicate provider bridges or power-helper work here. Final M4a PASS requires all UX-SC cases and no critical/high UX defects; blocked GUI/VoiceOver/performance cases prevent PASS. M5 final candidate and M6 require M4a; M7 remains after M6. Implementation is authorized by the subsequent user request. No publication or power actuation performed.

2026-10-05 progress: native launch, dark-mode Settings/Activity/dashboard and invalid draft/dirty close observations recorded. T001 remains partial (baseline screenshot coverage incomplete); T008/T009/T011/T017/T018 remain open for complete native/accessibility/performance acceptance. Component tests do not close these cases.

Continuation component evidence: menu-bar AX labels downgrade unverified Protected, Ready does not claim absent work, stable mode/details IDs replace obsolete interactive focus entries, and important state transitions post valueChanged once while timer/reason-only updates do not. AccessibilityStateTests pass in the307-test stable-source preview. Actual VoiceOver/native traversal remains T011/T017 acceptance; no speech-output pass inferred.
