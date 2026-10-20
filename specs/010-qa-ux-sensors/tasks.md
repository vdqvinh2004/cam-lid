# Tasks: M4b QA-driven UX and truthful telemetry

**Input**: spec.md, plan.md, research.md, data-model.md, contracts/, quickstart.md.
**Status**: Preview implementation in progress. Checked tasks have component/evidence completion; acceptance and blocked hardware work remain unchecked. Tests explicitly required by feature acceptance/SC-005 and preserved project QA requirements.
**Format**: T### [P] [US#] description with exact path. Paths without a prefix in a multi-file task inherit its stated source directory. Proposed new files are intentional.

## Phase 1: Setup

- [X] T001 Capture QA baseline, source/OS versions, severity and reproduction for every user finding in docs/qa/qa-refinement-report.md (FR-001–017); no gate claims from code inspection.
- [X] T002 [P] Inspect installed LidRun native dashboard/options/settings through bounded CUA navigation and document exact visible evidence or unresolved surface in specs/010-qa-ux-sensors/lidrun-comparison.md; no power/provider/license changes.
- [X] T003 [P] Record source/model/build/reference/permission feasibility inventory for numerical temperature and lid candidate in docs/qa/sensor-support-matrix.md; vendor mocks are not qualification (FR-009–011).

## Phase 2: Foundation

Authority seams before UI stories; no new power backend.

- [X] T004 Audit existing ConfigPatch/revision persistence, snapshot timestamps and status serializers; record reusable seams and field-conflict contract in specs/010-qa-ux-sensors/contracts/status.md (FR-007,011,016).
- [X] T005 Add isolated QA state/fixture support for storage failures and all five story states in Packages/CamLidCore/Tests/CamLidAppTests/QARefinementSupport.swift; never enable production fixture injection (FR-017).

## Phase 3: US1 — dashboard (P1, MVP)

Independent test:30 visible open/dismiss cycles and native options without host power.

- [ ] T006 [US1] Pin dismissal/open/right-menu lifecycle and refresh-does-not-reopen behavior in Packages/CamLidCore/Tests/CamLidAppTests/DashboardLifecycleTests.swift (FR-001–003).
- [X] T007 [US1] Remove Options button/callback from Packages/CamLidCore/Sources/CamLidApp/DashboardView.swift and AppCoordinator.swift; retain status/mode/Stop/details and preview truth (FR-001,003).
- [ ] T008 [US1] Fix transient close delegate/focus/event lifecycle in Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; scoped monitors only if proven necessary, clean on close/quit, ignore owned inside menus (FR-002).
- [X] T009 [US1] Serialize dashboard versus right/Control-click options and keyboard menu navigation in Packages/CamLidCore/Sources/CamLidApp/MenuBarController.swift; no activation on timer refresh (FR-001–003).
- [ ] T010 [US1] Run real outside/Escape/app-switch/status-toggle/nested-control30-cycle matrix in Tests/UI/QARefinementValidation.md; prove visible dismissal≤250 ms, not hidden AX presence (SC-001).

## Phase 4: US2 — direct preferences (P1)

Independent test: preset/custom persists and agrees with CLI through failure/concurrency/restart.

- [X] T011 [US2] Add meaningful atomic patch/concurrency/write-failure/rapid-edit regressions in Packages/CamLidCore/Tests/CamLidAppTests/SettingsAutosaveTests.swift (FR-006–008).
- [X] T012 [P] [US2] Add preset/custom/locale/composition/invalid/restart cases in Packages/CamLidCore/Tests/CamLidAppTests/NumericChoiceTests.swift; integer bounds0…30/0…30/10…50/5…480 from data-model.md (FR-005–006).
- [X] T013 [US2] Route typed field patches through current revision-aware authority in Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift and existing Configuration.swift; preserve untouched keys, same-field conflict deliberate (FR-007,016).
- [X] T014 [US2] Replace whole-draft Save with serialized/coalesced field edit states in Packages/CamLidCore/Sources/CamLidApp/SettingsEditor.swift;400 ms non-composing debounce, stale-response protection, bounded conflict retry, no optimistic Applied (FR-006–007).
- [X] T015 [US2] Implement canonical presets/Custom-only fields and remove visible section label/Save Changes in Packages/CamLidCore/Sources/CamLidApp/SettingsView.swift; preserve AX group/unit/errors and loaded custom values (FR-004–005).
- [X] T016 [US2] Replace Close/Quit dirty guards with valid-write settlement≤2 s and explicit failed/invalid disposition in Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; update UpdateController.swift unresolved-edit deferral and tests (FR-008).
- [X] T017 [US2] Record redacted applied/conflict/failure transitions once through existing history in Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; test preference edits never renew cap/grace/wait or arm power (FR-016).
- [ ] T018 [US2] Validate all presets/custom, simultaneous CLI edits, storage failure, restart and native close/update states in Tests/UI/QARefinementValidation.md; healthy readback≤1 s (SC-002).

## Phase 5: US3 — real sensor readings (P1)

Independent test: fresh typed lid and qualified named temperature; unsupported explicit. Temperature source qualification precedes integration.

- [X] T019 [US3] Add missing/type/stale/per-source age/null/desktop/wake lid regressions in Packages/CamLidCore/Tests/CamLidAppTests/LidStateReaderTests.swift (FR-010–011).
- [X] T020 [P] [US3] Complete read-only numerical-temperature candidate/reference/security/licensing feasibility in docs/qa/sensor-support-matrix.md; record manifest and source-resolution/max(2°C,resolution) reference tolerance or unsupported verdict (FR-009).
- [ ] T021 [US3] Implement bounded read-only Boolean IOPMrootDomain lid candidate in Packages/CamLidCore/Sources/CamLidApp/LidStateReader.swift and LiveSensors.swift; fresh≤5 s, awake observation≤2 s, unknown fallback, no leaks (FR-010).
- [ ] T022 [US3] Integrate only qualified read-only temperature source in Packages/CamLidCore/Sources/CamLidApp/TemperatureReader.swift with decode/error tests;2 s sampling, stale>10 s,200 ms read budget off main thread; unsupported paths remain explicit (FR-009).
- [X] T023 [US3] Extend SensorReadings/HealthSnapshot per-source availability/freshness in Packages/CamLidCore/Sources/CamLidCore/HealthMonitor.swift and Models.swift, compatibility tests for absent/null (FR-009–011).
- [X] T024 [US3] Project named temperature+independent pressure+lid into ActivityStore.swift, DashboardView.swift, AppCoordinator.swift and shared CLI status; bounded availability-transition logs, no raw reason codes (FR-009–011).
- [X] T025 [US3] Regress critical-pressure cache bypass/safety precedence/deadlines alongside temperature loss in Packages/CamLidCore/Tests/CamLidCoreTests/QAHealthSafetyTests.swift; temperature/CPU never healthy proof (FR-016).
- [ ] T026 [US3] Run supervised physical lid transitions and same-sensor temperature/reference validation per exact model/OS row in docs/qa/sensor-support-matrix.md; blocked rows remain unqualified, no forced heating (SC-003).
- [ ] T027 [US3] Verify GUI/CLI values/unit/source/freshness and unsupported/stale state presentation in Tests/UI/QARefinementValidation.md (FR-011, SC-003).

## Phase 6: US5 — protection readiness (P1)

Independent test: all readiness fixtures refuse real actuation; physical success remains M1/M2 prerequisite.

- [X] T028 [US5] Add capability/ownership/recovery/preview/lease truth regressions in Packages/CamLidCore/Tests/CamLidAppTests/ProtectionReadinessTests.swift and Packages/CamLidCore/Tests/CamLidCoreTests/ProtectionReadinessProjectionTests.swift (FR-014–015).
- [X] T029 [US5] Project qualified support row/helper/trust/recovery/conflict blockers through Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift and shared status; do not infer ownership from matching global value (FR-014).
- [X] T030 [US5] Present blocker-specific protection row/details and explicit intent versus Protected in Packages/CamLidCore/Sources/CamLidApp/SettingsView.swift and DashboardView.swift (FR-014).
- [X] T031 [US5] Audit existing M1 T003–T008 and M2 live-backend evidence in docs/qa/qa-refinement-report.md; require L01–L20/manual Sleep/independent recovery/support-row verdict before any live integration (FR-015).
- [ ] T032 [US5] After M1/M2 PASS only, validate integrated capability/arming/continuity/internal-display/restoration/completion-sleep using Tests/Hardware/PowerFeasibility.md and RecoveryFailureMatrix.md; record SC-006 evidence or blocked status, never add alternate power bypass.

## Phase 7: US4 — agent badges (P2)

Independent test: four providers enrollment/readiness/evidence accurately projected without new paid runs.

- [X] T033 [US4] Add enrollment/work-readiness/parallel-Orca/stale/disabled-active tests in Packages/CamLidCore/Tests/CamLidAppTests/AgentBadgeTests.swift (FR-012–013).
- [X] T034 [US4] Create bounded provider projection in Packages/CamLidCore/Sources/CamLidApp/AgentBadgeView.swift: detectionEnabled separate from Active/Waiting/Inactive/Unknown and readiness; preserve adapter identity/freshness (FR-012).
- [X] T035 [US4] Replace checkbox rows with native accessible toggle-button badges in Packages/CamLidCore/Sources/CamLidApp/SettingsView.swift and Accessibility.swift;32 pt minimum target,8 pt spacing, keyboard/state text (FR-012).
- [X] T036 [US4] Apply badge enrollment through revision-safe patch flow in Packages/CamLidCore/Sources/CamLidApp/SettingsEditor.swift and AppCoordinator.swift; preserve conservative disabled-source unknown handling, no hook/provider writes/prompts (FR-013,016).
- [ ] T037 [US4] Run mouse/keyboard and four-provider disconnected/working/waiting/idle/stale/parallel native matrix in Tests/UI/QARefinementValidation.md (SC-004).

## Phase 8: Polish, AI QA and supervised users

No final acceptance until mandatory supported-row and release predecessors pass.

- [X] T038 Assert additive schema/backward compatibility and GUI/CLI config/status parity in Packages/CamLidCore/Tests/CamLidAppTests/QAStatusContractTests.swift; fixture cannot fake production sensors/power (FR-016–017).
- [ ] T039 Measure idle10 min/RSS/dashboard30 opens/dismissal/autosave; audit log rotation/redaction and temp/lid read overhead in docs/qa/performance-report.md and qa-refinement-report.md (SC-001–003,005).
- [ ] T040 Complete light/dark/contrast/transparency/motion/text/scale/notch/long-label20-task/keyboard matrix in Tests/UI/QARefinementValidation.md; unavailable device rows blocked (SC-005).
- [X] T041 Replay existing40 saved Codex/OpenCode profiles plus Orca parallel fixtures and compare dispositions in docs/qa/agent-compatibility.md; no new paid requests, no full M3 claim (SC-004).
- [X] T042 Run settled-source canonical scripts/verify-preview.py and packaging regressions; record source hash/report in docs/qa/qa-refinement-report.md; repeat only after changes/failures (FR-017).
- [ ] T043 Perform independent AI source/spec/contract/evidence review against L01–L20 in docs/qa/ai-quality-report.md; fix and rerun affected checks until zero critical/high; M6 full gate remains separate (SC-005).
- [ ] T044 After M6 PASS/signing/per-device qualification, run five supervised M7 users and record uncoached≥4/5 refinement-flow success plus zero safety/restoration failures in docs/qa/user-test-report.md (SC-007).
- [X] T045 Update specs/010-qa-ux-sensors/tasks.md, docs/planning/roadmap.md and M4a/M5/M6 evidence handoff with final disposition; unsupported temperature/core backend remains open, no retroactive checked gates (FR-017).

## Dependencies & Execution Order

T001–T005 precede story edits. US1 T006–T010 is preview MVP. US2 T011–T018 independent of physical power, before badge autosave integration. US3 T019–T027 can deliver real lid/unsupported temperature first, but T022 requires T020 qualified source and T024 projection requires T023 snapshot and both relevant platform readers. T021/T022 platform readers can be developed before or alongside T023 in separate files; T024 integration waits for both. US5 T028–T030 readiness independent of sensor qualification; T031 audit precedes T032, which remains blocked on external M1/M2. US4 T033–T037 depends on US2 authority/persistence. Cross-cutting T038–T043 after implemented desired stories; T044 user trial only after T043 and full M6/M5/device gates. T045 handoff after final disposition, including blocked outcomes.

No planned task is already done merely because this document exists. Shared AppCoordinator.swift/SettingsView.swift edits serialize. Backend/helper implementation remains owned by specs002/003; T031–T032 integrate evidence, not duplicated backend tasks. No prerequisite permits implementing power override before M1.

## Parallel Opportunities

- Setup T002 native comparison and T003 sensor inventory use different documents; coordinate one GUI controller, no concurrent desktop actions.
- US1 lifecycle tests can be prepared independently of pure DashboardView Options removal after contract audit; integration follows sequentially.
- US2 T012 numeric validation tests can proceed alongside T011 autosave tests, separate files. Main editor/coordinator/UI mutations serialize.
- US3 T020 feasibility can proceed alongside T019 lid tests; qualified platform readers/model tests use separate files, projection joins them.
- US5 readiness tests and read-only M1 evidence audit can be prepared in separate files; live test awaits gates.
- US4 evidence projection tests can be prepared alongside badge component layout; native join waits for persistence and projection.
- Final privacy/performance review can analyze settled sources while evidence review reads documents; do not measure during concurrent builds/provider jobs.

## Implementation Strategy

First ship a reviewable preview increment of US1; then direct preferences, real lid plus temperature qualification, readiness and agent badges. Do not deploy/publish from these tasks implicitly. Run each story's independent acceptance before integration. Full milestone requires all supported-row outcomes and final AI/native gate; blocked core power support cannot be renamed completed UX. Tests for state/safety/concurrency regressions should demonstrate failure before relevant implementation; static label removal needs no mirrored test. Existing original M4a/M5/M6 tasks remain historical/owned and are not checked by this planning.

## Requirement coverage

| Requirement | Tasks |
| --- | --- |
| FR-001 | T006–T010 |
| FR-002 | T006,T008,T010 |
| FR-003 | T007–T010,T040 |
| FR-004 | T015,T018,T040 |
| FR-005 | T012,T015,T018 |
| FR-006 | T011–T015,T018 |
| FR-007 | T004,T011,T013,T014,T018 |
| FR-008 | T011,T016,T018 |
| FR-009 | T003,T020,T022–T027 |
| FR-010 | T003,T019,T021,T023–T027 |
| FR-011 | T019,T023–T027,T038 |
| FR-012 | T033–T037 |
| FR-013 | T033,T036,T037,T041 |
| FR-014 | T028–T030 |
| FR-015 | T028,T031,T032 |
| FR-016 | T013,T017,T026,T036,T038,T039 |
| FR-017 | T005,T038–T045 |
| SC-001 | T010,T039 |
| SC-002 | T011–T018,T039 |
| SC-003 | T020–T027,T039 |
| SC-004 | T033–T037,T041 |
| SC-005 | T038–T043 |
| SC-006 | T031,T032,T043 |
| SC-007 | T044 |

## 2026-10-05 implementation disposition

Preview increment: atomic per-field config, presets/Custom, On/Off agent badges with independent work/readiness, strict read-only lid candidate, independent pressure/unsupported temperature, and dashboard Options removal/visible-only dismissal lifecycle. See [QA record](../../docs/qa/qa-refinement-report.md) and [sensor inventory](../../docs/qa/sensor-support-matrix.md). Canonical evidence:213 Swift tests (126 Core/42 CLI/45 App), five packaging tests, all seven checks PASS; source unchanged during final verification.

Checked T002 is the permitted unresolved-native-surface result; it is not verified LidRun native layout. Checked T020 is an unsupported-source feasibility verdict, not qualified numerical temperature. T019 covers missing/type/stale/future and legacy null; desktop classification remains unknown, physical rows stay T026. T038 integration test lives in AppTests, where the live authority is owned, avoiding GUI/Sparkle coupling in the CLI test target.

Partial: T005 isolates storage/preferences/control and evidence examples but not every story fixture. T006 has hidden-popover lifecycle cleanup regression only, no full event routing proof. T008 dismissal monitors implemented; native focus/menu/visible cleanup acceptance pending. T014 field autosave/debounce/IME/conflict/readback implemented; asynchronous pending/timeout contract remains open. T016 close/quit flush and unapplied-only disposition implemented; ≤2 s bounded write settlement unproved. T017 config apply/write-failure history and cap/wait regressions present; once-per-conflict logs and complete grace/deadline regression remain open. T021 Boolean reader implemented with1 s app tick and5 s source freshness; off-main bounded IOKit latency/universal model qualification unproved. T023 optional typed lid metadata and legacy decoding implemented; full typed temperature metadata awaits qualification. T024 GUI/status pressure/temperature/lid present; availability-transition history/source detail still pending. T028 preview intent/mode/power-refusal tested; helper ownership/recovery fixtures await real readiness projection. T029/T030 only truthful Preview/blocker projection, not full future helper/support-row readiness. T031 predecessor audit records missing M1/M2 evidence, full per-task hardware artifact audit pending.

Native T010/T018/T027/T037/T040 remain partial or open; no30-cycle latency, actual VoiceOver or full appearance/device acceptance claim. T039 idle10 min/performance remains unmeasured. T043 independent AI review not performed in this increment. Blocked: T022 no qualified numerical source; T026 supervised physical sensor rows; T032 M1/M2 live backend/recovery predecessors; T044 M5/M6/per-device+consenting users. None of these are silently accepted or checked.

Final native rerun confirms invalid-feedback text and discard-close fix on the settled build; applied CLI7/revision3 survives. QA app remains running in the menubar with isolated preferences. Complete native matrix remains unchecked. No before/after extension hooks registered (`.specify/extensions.yml` absent).

## Continued implementation — 2026-10-05

T005 now covers all five isolated stories without production sensor/power injection. T014 implements serialized/coalesced async edit states, Applying150 ms, stale-input protection and bounded rebasing. T016 valid preference settlement is bounded to2 s with unapplied-only Close/Quit choices; update safety includes hidden pending writes. T017 applied/conflict/failure once-per-attempt plus cap/grace/wait anchors have meaningful tests; actual runtime history is bounded/off-main. T023 typed temperature/lid metadata validate and decode legacy absent/null safely; unsupported production temperature is deliberate. T024 source-specific values/details and availability-transition logs are connected. T028–T030 pure readiness gates/precedence plus production unknown ownership/helper/journal/support blockers distinguish requested intent from verified protection. T031 complete per-task M1/M2 predecessor audit is linked in qa-refinement-report.

T006/T008 remain partial: deterministic event classification and monitor cleanup pass, but full native visible dismissal/focus proof remains T010. T021 off-main single-worker cache/late-read/stale/critical bypass regressions pass; physical transition timing and exact-row qualification remain unproved. T022 is still blocked on a qualified named temperature source; implemented unsupported/metadata paths do not clear it. T039/T043 current measurements and independent rereview are underway; no new canonical aggregate or full M6 verdict is inferred. All visible appearance/VoiceOver, physical, signing and user gates retain unchecked status.

### Final continuation evidence (2026-10-05)

T042 remains complete: settled canonical310 Swift (182 Core/42 CLI/86 App),5 packaging tests,7 PASS checks, unchanged source hashes. T043 source review performed and detected issues remediated/rereviewed, but remains open because the backend/durable-journal High release gate is unresolved; full M6 separate. T039 ten-minute hidden307-test QA sample completed (0.9033% one-core CPU,56.640625MiB peak RSS); full latency/polling/flood/source-current matrix open. T018/T037 partial native310-source badge autosave/CLI agreement and ordinary quit/restart observed in a private QA app; actual IME/VoiceOver/uncertain-write/native full matrix open. T026 passive2h lid data has241 Closed samples; no transition/display-off/recovery qualification. All evidence scope is in docs/qa/qa-refinement-report.md, performance-report.md and independent-review-2026-10-05.md.

## Approved UI simplicity increment (UX01-18)

- [X] T046 Synchronize spec.md, plan.md, data-model.md and contracts/interaction.md with approved visual simplification; unchanged safety/status/unknown/persistence semantics (FR-018–024).
- [X] T047 Add meaningful metric availability, badge evidence, event/filter and Off-history regressions in Packages/CamLidCore/Tests/CamLidAppTests/UISimplicityTests.swift (UX01,08,09,16,17).
- [X] T048 Simplify SettingsView.swift/AgentBadgeView.swift with badge grid, single state, collapsed integration detail, quiet success/native close, minimal labels/capability/privacy (UX01–06,13,14).
- [X] T049 Add native SettingsToolbar.swift, pane sizing/title/selection and Command-W in AppCoordinator.swift/MenuBarController.swift; retain close guard (UX05,15).
- [X] T050 Add typed metric badges, compact adaptive dashboard, explicit contextual Start/Stop, single capability notice and neutral Off in DashboardView.swift/AppCoordinator.swift; preserve deadlines and background behavior (UX07–12).
- [X] T051 Correct no-session event-state projection and readable expandable Activity events/filters/export/secondary confirmed deletion in AppCoordinator.swift/ActivityLogView.swift (UX16–18).
- [X] T052 Run settled canonical verifier, affected regression/build checks and scoped source/contract review; record evidence under docs/qa/preview-evidence/ui-simplicity and ui-simplicity-report.md.
- [ ] T053 Exercise native updated preview: four panes, badge persistence, metric layout/Details, explicit Start/Stop, native close/reopen, event/filter and outside dismissal; capture exact app surfaces and actual measured height.
- [X] T054 Record UX01-18 disposition, full appearance/VoiceOver/device/performance residuals and task handoff in ui-simplicity-review.md, quickstart.md and docs/qa/ui-simplicity-report.md. Original M1/M5/M6/M7 gates stay open.

Dependency order: T046 → T047 → T048–T051 (shared files sequential) → T052 → T053 → T054. T053 is a bounded preview review, not full T010/T040 or M7 acceptance. Scope-specific follow-up work remains explicitly recorded rather than inferred PASS.

## UI simplicity implementation disposition — 2026-10-05 continuation

T047–T052 complete on settled source. `UISimplicityTests` (6 tests) pins
missing/stale→Unknown, qualified-temp/pressure separation, enrollment≠work,
readable event titles with raw-code search, Off start refusal without
session/power, and Off settings events staying Off in history.
`DashboardView`/`AgentBadgeView`/`SettingsView`/`SettingsToolbar`/
`AppCoordinator`/`ActivityLogView` implement badge grid, single state line,
Mode label, quiet autosave, native toolbar, adaptive 290 pt empty dashboard,
contextual Start/Stop, truthful no-session history. Canonical verifier:
335 Swift (200 Core/42 CLI/93 App), 5 packaging, 7/7 checks PASS, source
unchanged (`docs/qa/preview-evidence/ui-simplicity/report.json`; fresh rerun
`/tmp/camlid-ui-verify-check/` identical). Native bounded preview: 4 panes,
badge persistence, 4 badges one row, footer gone, 290 pt stopped height, real
outside dismissal, menu Start/Stop battery refusal with powerActuation false;
8 screenshots under `docs/qa/preview-evidence/ui-simplicity/native/`.
Direct popover clicks via background CUA remain manual-check; full 30-cycle,
IME, actual VoiceOver, appearance/device matrix open. See
`docs/qa/ui-simplicity-report.md`. M1/M2/M5/M6/M7 gates stay open.

## Current scope — passive supervision (2026-10-05)

VoiceOver acceptance is excluded by explicit user request. Retain keyboard navigation, native control semantics, meaningful labels and non-color-only states. Historical VoiceOver “not run” observations above are historical, not current requirements. Observation covers all locally detected providers regardless of sleep selection. Settings badges select whether an agent may delay sleep; Enable all selects all providers. No bridge, hook, LaunchAgent or provider configuration setup is required. Process-only sources remain Unknown; disappearance never invents completed work. Current evidence and residuals: docs/qa/passive-supervision-report.md.

### Passive supervision implementation disposition

Checkbox-free button badges, Enable all, observation independent of sleep selection,
visible mode badges, compact unique Details and text metrics implemented. Unknown work
releases a bounded hold without a completion-sleep request; selected standalone process
presence and stale discovery cannot authorize completion sleep. Red-to-green regression
covers this policy and the single popover-dismissal owner. Actual CLI quit exits normally.
Canonical final:339 declared Swift tests (200 Core/42 CLI/97 App, one opt-in installed-provider
case skipped in canonical and passed separately),5 packaging,7 PASS, stable source hashes.
Installed version-only process checks:20 Codex +20 OpenCode lifetimes PASS; semantic task
completion is not established. Native enable-all/mode/config/restart and Command-W observed;
final keyboard/30-cycle250ms/appearance/device matrix remains partial, VoiceOver excluded.
Ten-minute hidden observer sample:0.9267% one-core CPU,73.59375MiB RSS; unchanged observer
paths, binary predates later completion-policy guard. Source-current supplemental scope
and all residuals: docs/qa/passive-supervision-report.md. T010/T018/T037/T039/T040/T053 remain
open for their full acceptance scope; M1/M2/M5/M6/M7 and numeric sensor qualification remain
open. No provider/background-service setup or power changes performed.

### Final native/performance fixes

Current canonical341 declared Swift (200/42/99, one installed-provider case skipped here and passed separately),5 packaging,7/7 PASS and stable source: docs/qa/preview-evidence/passive-supervision-final-native/report.json. Hidden Settings projections stop relayout while hidden; unchanged menu-bar status reuses its image while menu enablement still updates. Image reuse/transition/reinstall and anchor screen-hit handling have red-to-green regressions. Local outside classification excludes anchor screen points even for missing/different event windows.

Native WindowServer observations:10 Command-D/Escape +10 real outside-click cycles on the340-source build; final341-source status run4 observed opens/closes followed by1 unresolved close. No delivered-HID/250ms/full30-cycle PASS. Source-current Off/Auto persisted revisions7/8; Command-W hid Settings. Full keyboard focus/appearance/IME/device rows remain open, VoiceOver excluded. Final341-source10min idle observation is pinned by the final-native manifest; summary belongs to passive-supervision-report.md. Prior1.0083% CPU/50.17MiB full sample failed the strict CPU target and prompted menu-bar profiling/fix.

Final measured341-source settled idle:600.016s,0.2033% CPU,58.0MiB max RSS PASS after an explicit120s settling interval. Immediate post-UI peak112.33MiB remains FAIL against strict peak100MiB. Source hashes unchanged after sample. T039 stays open for full scope. Native Tab/Space validates all four modes, all four agent selections and Enable all with CLI agreement; ignored providers remain visible in the dashboard. Keyboard Navigation was enabled briefly via the native shortcut and restored/independently verified off. These primary badge paths supersede earlier unsuccessful focus attempts; full keyboard/IME/focus-restoration matrix remains open. Evidence: final-native/keyboard-badges.json and passive-supervision-report.md.

## Status dismissal follow-up — 2026-10-05

T010/T053 partial: native deactivation-before-status-action close/reopen reproduced and fixed; Debug30 consecutive status cycles and final Release10 cycles independently observed. Escape/app-switch/outside-desktop dismissal also observed on final Release.342 declared cases, five packaging tests, seven canonical checks PASS; verifier serializes shared AppKit suites without relaxing deadlines. [Evidence](../../docs/qa/preview-evidence/status-dismissal-fix/README.md). T010/T018/T037/T039/T040/T053 stay open for their remaining native/latency/performance/provider/device scope. Prior strict Debug post-UI RSS failure remains visible.

## Closed-lid observation/load continuation — 2026-10-05

[Evidence](../../docs/qa/preview-evidence/matched-ui-memory-2026-10-05/README.md): final342-source unchanged;320 concurrent CLI requests plus40 independent app/registry pairs observed Closed/display asleep under external LidRun and caffeinate, with no CamLid power assertion.200 actual harmless wrapper children completed;139 status reads accepted. Initial admission rejection, immediate717.6ms export timeout and117 omitted history records remain failures/limits; later515-record redacted export and64-run-cap recovery observed. Native matched memory trial incomplete; Debug112.33MiB peak remains FAIL. Debug normal quit passed; Release omitted-history guard prevented normal quit, exact owned QA PID cleaned up after export with SIGTERM (not a normal-quit PASS). No full task checkbox changed. T010/T018/T037/T039/T040/T053 and M1/M2/M5/M6/M7/numeric-temperature gates remain open.

## History load and native continuation — 2026-10-05

[Evidence](../../docs/qa/preview-evidence/history-load-diagnosis-2026-10-05/README.md): history retention batching fixed the identical seeded load (155 omissions/export timeout before; zero omissions/813-record export after). 344 Swift cases, five packaging tests, seven canonical checks PASS;125 source hashes match. Both native Settings protocols completed16 checkpoints; sampled RSS stayed below100MiB. Prior112.33MiB Debug failure remains open. Activity export/deletion/clear-all/empty-state and dark small/large window checks completed; both isolated copies exited normally without signals. Deeper replay reached256 replay tombstones and did not qualify accepted event load. T010/T018/T037/T039/T040/T053 remain unchecked for their full scope; M1/M2/M5/M6/M7 and numeric-temperature gates remain open. Signing inputs unavailable by user disposition. No full task checkbox changed.

## Immediate post-UI memory repair — 2026-10-06

[Evidence](../../docs/qa/preview-evidence/memory-peak-fix-2026-10-05/README.md): fresh source-pinned Debug16-action native replay PASS, UI child exited, first sample 0.346851s after close; 586 samples/600.011985s peaked at **71.843750MiB RSS**, strict100MiB memory subgate PASS without settling. Original112.33MiB failure remains byte-identical/FAIL.348 declared Swift cases (two opt-in cases skipped: installed-provider lifetimes and live read-only probe), five packaging tests and seven canonical checks PASS with128 stable source hashes and Debug/Release products. Original SwiftUI screens retained in an owned child; persistent policy/preferences/history/CLI authority unchanged. Active combined RSS increases. T039/SC-005 and full native/backend/device/signing gates remain open; no full task checkbox changed.

## Native UI process follow-up — 2026-10-06

[Evidence](../../docs/qa/preview-evidence/native-ui-process-followup-2026-10-06/README.md): current-source native close/reopen with Manual/Custom7, invalid-input validation, close/whole-quit Keep Editing, discard retaining applied state, clean-draft owned UI child termination/recreation and normal whole-app quit PASS. Main policy/CLI authority survived UI child termination; five status reads passed. Source unchanged, prior immediate ten-minute71.84375MiB memory verdict remains current. T018/T039/T040/T053 remain unchecked for their full scope; no task checkbox changed.

## Native cycles and keyboard/layout follow-up — 2026-10-06

[Evidence](../../docs/qa/preview-evidence/native-cycle-qa-2026-10-06/README.md): unchanged candidate passed Debug60/Release30 visibility/child-exit cycles with preserved configuration. Release29 captured dismissal inputs pass250ms; one missing trace and ready200ms remain unqualified. Native Settings/close/Escape shortcuts and dark small/large panes observed; Tab focus order/footer scrolling remain unqualified. Active memory diagnosed independently of the current immediate600s/71.84375MiB RSS PASS. All owned QA/observer processes stopped. T010/T018/T039/T040/T053 remain unchecked; no full task checkbox changed.

## Do-all continuation — 2026-10-06

Clean Release (348-test PASS build), isolated QA, M4/macOS 27.0.1. No product changes retained (128/128 hashes match).

- Baseline: canonical re-verify PASS, 348 tests, 7 checks, source unchanged.
- First-frame (temporary gated probes, reverted): cold init ~132ms + presentation ~134ms dominate; view build ~9ms. Evidence docs/qa/preview-evidence/doall-firstframe-2026-10-06/.
- T010/T039: 30/30 visibility PASS; opening p95 635–712ms FAIL; dismissal 28 PASS + 1 FAIL (264ms escape) + 1 INCONCLUSIVE.
- T018: CLI presets rev1→3→10, invalid rejected, concurrency clean, restart persistence PASS (normal quit/relaunch).
- T037/T040: Cmd-comma/Cmd-W/Escape PASS; Tab UNQUALIFIED (AX route unavailable); true-Light dashboard + General readable (partial); Dark restored.
- T039: settled hidden idle 600s PASS (35.64 MiB peak, 0.14% CPU); 50-read flood p95 13ms.
- Immediate post-UI 71.84 MiB / 600s verdict stands (no retained changes, no re-gate needed).
- Blocked unchanged: T022, T026, T032, M5, M6, M7/devices. No task checkbox changed.

### Do-all round 2 — 2026-10-06 (same build/state, no product changes)

- T053 bounded PASS: all four Settings panes opened via native AX toolbar clicks with screenshots
  (General 580×348/Timed/7, Agents 4 badges, Safety disabled-power + limits, Activity 14d/20MiB privacy);
  Cmd-W + Escape dismissal with child exit. Direct popover-click manual check and per-pane heights stay open.
- T043 addendum: L01–L20 rechecked on current source (no actuation APIs, observation-only IOKit/CGDisplay,
  14 known try!, semantic colors); zero new critical/high; M6 still blocked. See doall-coverage/T043-addendum.md.
- No task checkbox changed (blocked gates unchanged).

### Do-all round 3 — 2026-10-06 (same build/state, no product changes)

- Direct popover clicks: Start Preview PASS (timed session created, truthful notCharging safety stop,
  Stop + 1h59m shown), Stop Preview PASS (session null, Ready restored). Details toggle NOT established
  (2 targeted clicks, no expansion). One-shot desktop clicks take physical pixels (points×2); capture-bound
  clicks take image pixels — recorded after one outside-dismissal miss.
- T053 heights complete: General 580×348, Agents 580×388, Safety 580×508, Activity 580×288 via native
  AX pane clicks + list_windows bounds.
- Native autosave probe: AX set_value path applies with CLI agreement (stable 30/30s at restored 7);
  tight ≤1s latency UNQUALIFIED (programmatic path, tool gaps); one uncommanded 7→9 flip under rapid
  AX writes noted as T014 edge observation (converged, held). See doall-coverage/autosave/.
- All QA exited via normal CLI quit; observers stopped; 128/128 hashes match.

### Do-all round 4 — 2026-10-06 (same build/state family, no product changes)

- Tab focus: UNQUALIFIED ×3 with screenshot evidence (no visible focus ring after 2 Tabs on owned focus).
- IME: composing-defers-commit unit seam green; live IME open (needs native input-source env).
- Motion/contrast: covered statically (no custom animations; ReduceMotion/contrast helpers reviewed).
- Direct popover Start/Stop PASS; Details toggle not established; per-pane heights 348/388/508/288.
- Conflict probe NOT ESTABLISHED (frontmost-focus miss typed into Orca draft; disclosed, unsubmitted).
  CLI paths clean; conflict handling rests on unit coverage + close-guard handshake.
- Flood moderate: 100 seq p95 11ms + 30 parallel p95 27ms, 130/130 ok.
- Pre-warm experiment REJECTED with data: idle 135 MiB (>100) and warm open 495–522ms (>200).
  200ms + 100MiB jointly infeasible under fork-per-open; no product change. See PREWARM-VERDICT.md.
- Blocked gates re-verified still blocked: 0 signing identities; single Mac16,12/M4 (no device matrix);
  no qualified temp source; no users recruited; lid/physical untestable on in-use machine.

### Thermal qualification round — 2026-10-06 (product change, verified)

- T020 partial-PASS on Mac16,12/macOS 27: HID max(tdie) qualified (named sensor, unprivileged,
  64ms, load-tracked, independent app references). Other models stay unqualified.
- T022 integrated: TemperatureReader.read() live + LiveSensors worker sampling + stall guard +
  HealthMonitor projection. Canonical 354 tests / 7 checks PASS, source stable during verification.
- T026/SC-003 physical rows unchanged (still open); pressure stays safety authority.

### Do-all round 5 — 2026-10-06 (same build/state, no product changes)

- Dismissal retry 27/30 (1 over-budget escape, 2 outside trace gaps). No more blind retries;
  harness input-trace hardening is the fix, not product changes.
- M6 live faults: malformed frame → invalidInput rejection; 65MiB frame → peer killed, server
  healthy; corrupt prefs → defaults boot; read-only history → refused without mutation + recovered;
  UI child SIGTERM → parent/CLI survive, reopen works.
- Conflict ESTABLISHED: focus-gated keystrokes, invalid "75" correctly unapplied, concurrent CLI 9
  won cleanly, set_value cleanup to agreement. Automation limits documented (no select-all/AX on field).
- No task checkbox changed (gates as before).

### Opening/latency decision — 2026-10-06: keep + document (user chose option 1)

Fork-per-open retained; 200ms ready budget stays open-but-accepted as known ~0.5s limit.
No product change, no further latency trials planned.

### Do-all round 6 — 2026-10-06 (test additions only, no product change)

- Pipe fault contracts pinned in UtilityUIPipeTests: oversized-frame peer kill delivers nothing;
  malformed command/event frames decode to nil (try?-and-ignore). Both green.
- Details Tab+Space walk (4 iterations, owned focus): all no-ops, no focus ring ever visible.
  Product finding: dashboard popover controls lack keyboard operability (window shortcuts unaffected).
- Edge sweep closed: 19 numeric bounds, modes/opt-ins/enrollment bounds, conflict, M6 live faults,
  flood, crash drill, restart, light 4-pane, heights, idle-600s — all recorded under
  docs/qa/preview-evidence/doall-coverage-2026-10-06/.
- No task checkbox changed.

### UX refresh round — 2026-10-06 (user-tested, verified 358 PASS)

- Start/Stop wording, compact dashboard, working-agents filter, thermal clock fix (live 63.8°C chip),
  original menu-bar mark. Evidence docs/qa/preview-evidence/doall-coverage-2026-10-06/ux-refresh/.
- Preview.app rebuilt + relaunched for user testing. No task checkbox changed.

### Provider marks round — 2026-10-06 (user-tested, verified 360 PASS)

- Official per-provider Settings/dashboard marks (Orca user link, Claude/OpenAI/OpenCode paths),
  trademark notice, fallback glyph. Evidence doall-coverage/agent-marks/.
- Preview.app rebuilt + relaunched for user testing. No task checkbox changed.

### Provider glyph round — 2026-10-06 (user-tested, verified 360 PASS)

- Extracted product glyphs (orca whale, codex cloud-terminal, claude-code burst) replace app
  images; OpenCode terminal kept. Evidence doall-coverage/agent-marks/GLYPHS.md.
- Preview.app rebuilt + relaunched for user testing. No task checkbox changed.

### Orca dynamic compatibility — 2026-10-06 (user-tested, verified 363 PASS)

- Same-1.4 patches accepted dynamically; friendly versioned messages; live 1.4.221 rows verified.
- Preview.app rebuilt + relaunched. No task checkbox changed.

### UI/UX audit implementation — 2026-10-07 (authorized scoped increment)

Subsequent [compact UI feedback](../../docs/qa/compact-ui-2026-10-07.md): dashboard Details/expansion removed, empty content 180 pt/native 206 pt including chrome, semantic icon/value metric strip, Task unknown explained inline, Safety engineering disclosure replaced with concise Preview only notice. Final canonical 7/7 pass (369 declared / three skipped). Final Dark empty/Timed/Agents/Safety native checks recorded. Installed Preview refreshed and relaunched; user config/revision 20 preserved. Existing matrix/gate checkboxes unchanged.

Further [icon/text feedback](../../docs/qa/icon-ui-2026-10-07.md): remove Active/positive working summary and redundant Ready subtitle; timer/task count/Activity icons retain semantic names/help. Timed/Manual share a finite cap, unchanged; no infinite mode introduced. Apple system-symbol provenance/licensing recorded. Final canonical 7/7 pass; final Dark Timed/one-provider 268 pt, Activity Shift-Tab/Space activation verified. Pointer targeting inconclusive; no full matrix/gate claimed. Installed Preview refreshed, settings preserved.

- User authorized updating UI from QA results. [Implementation report](../../docs/qa/uiux-implementation-2026-10-07.md), [gallery/receipts](../../docs/qa/preview-evidence/uiux-implementation-2026-10-07/README.md), [NUI follow-up disposition](../../docs/planning/uiux-next-feature.md).
- T006/T008/T010/T037/T040: dashboard explicitly receives focus; borderless native badges retain keyboard semantics. Baseline reproduced focus behind popover; updated modes/Details activate via Tab/Space. Final Escape consumed, preserving Welcome behind it. Full final keyboard/pointer matrix remains unchecked.
- Existing command/agent/Welcome ownership: Start/Stop names/shortcuts/guards agree, truthful selected-work summary, live observations, color-independent selection, three-page read-only completion with bounded acknowledgement/Retry. Final native timeout/retry preserves consent and records once; no configuration patch during Finish.
- History refinement: stable top search/Type/Reason/actions, request-correlated loading/error/Retry and retained stale rows, human reasons/state before raw codes. Final native no-match/Clear/expanded-row Refresh and 560/640/900 pt pass; fault/export/delete GUI rerun remains.
- Updates: measured parent-hosted retention, moved presentation to owned helper. Parent keeps UpdateController/Sparkle/check guards; final unavailable/last-surface-close path verified. M5 signed-feed/install scope remains open.
- T018/T027/T039/T042 support: canonical 7/7 steps pass, 369 declared cases with three opt-in probes skipped; Debug/Release/actual CLI integration/packaging/read-only hardware preflight. Source hashes unchanged. Six added meaningful regression cases; pipe parser avoids repeated growing-buffer scans and oversize writer no longer blocks its MainActor reader.
- T043/T045 handoff: implementing-agent review and exact baseline patch recorded; independent review/full appearance/minimum-OS/hardware/performance rows remain. Accepted fork-per-open latency decision retained. No milestone task checkbox changed; M1/M5/M6/M7 unpassed. Original keyboard preference and foreground restored; isolated QA processes exited normally.
