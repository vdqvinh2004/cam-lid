# Tasks: M8 Awake Automation & Diagnostics

**Input**: [Spec](spec.md), [plan](plan.md), [research](research.md), [model](data-model.md), [contract](contracts/awake-automation.md), [validation](quickstart.md).
**Status**: 33/43 tasks complete as of 2026-10-08; 10 partial/deferred/acceptance-open. [Implementation evidence](../../docs/qa/awake-automation-report.md). FR/SC IDs below are local to M8.
**Tests**: Explicitly required by FR-022; add meaningful safety/contract tests before behavior, verify failure then implementation. Existing tests/baseline features are reused, not duplicated.
**Format**: `- [ ] Tnnn [P?] [USn?] Description with exact path`. [P] means separate files with no incomplete dependency; absent means sequential. Paths are repository-relative; named new source/test files are proposed, not present yet.

## Phase 1: Setup

- [x] T001 Record the user's lid-open display preference amendment in docs/planning/product-spec.md, docs/planning/architecture.md and specs/003-native-foundation/tasks.md T015; preserve default display sleep, closed-lid FR-003, M1/M2 backend ownership and all release gates (FR-005–007).
- [x] T002 Record accepted baseline and M1/M2 integration readiness in specs/011-awake-automation/evidence/integration-readiness.md; identify qualified backend/executor or explicitly keep live tasks blocked; no backend duplication, provider setup, actuation or simulated PASS for hardware (FR-005/022).

## Phase 2: Foundation

- [x] T003 Add portable diagnostic/status DTOs and stable reason/outcome enums in Packages/CamLidCore/Sources/CamLidCore/AutomationModels.swift; configuredMode separate from nullable activeSessionMode, missing owner/effect/coverage unknown, protection cannot be verified with powerActuation=false (FR-001–003).
- [x] T004 Extend allowlisted operations in Packages/CamLidCore/Sources/CamLidCore/IPC.swift and Packages/CamLidCore/Sources/CamLidCore/LocalControlTransport.swift using existing same-UID authentication and "<=64 KiB" frames; add diagnostic/admit-renew-finish/sleep request payloads without shell commands, arbitrary duration, argv/output or privilege escalation (FR-004/008/010/014/021).

**Checkpoint**: Typed contracts available. Foundation does not require live backend; T002 may explicitly record blocked live acceptance.

## Phase 3: US1 — Shared awake diagnosis (P1, MVP)

**Goal**: Extend existing diagnostics and truthful status, not rebuild the window.
**Independent Test**: GUI and CLI match seeded blockers/partial results without power mutation; saved Timed with no session remains inactive.

- [x] T005 [P] [US1] Add shared diagnostic schema/redaction/status compatibility tests in Packages/CamLidCore/Tests/CamLidCLITests/AutomationCLITests.swift, including app unavailable, partial/all-failed coverage, legacy configured mode and no active session (FR-001/003–004, SC-001).
- [x] T006 [P] [US1] Extend collector tests in Packages/CamLidCore/Tests/CamLidAppTests/SleepDiagnosticsTests.swift for system/display/user/global/kernel distinction, unknown types, timeout and truncation; require "5-second total deadline; 64 KiB combined subprocess output; at most 256 owner rows; one in-flight collection" (FR-001–004, SC-001).
- [x] T007 [US1] Extend Packages/CamLidCore/Sources/CamLidApp/SleepDiagnostics.swift with typed shared snapshot, fixed read-only pmset augmentation where public reader lacks coverage, explicit partial failures and "5-second total deadline; 64 KiB combined subprocess output; at most 256 owner rows; one in-flight collection"; trim encoded reply to "<=64 KiB", discard raw output and redact owner identifiers by default (FR-001–004/021).
- [x] T008 [US1] Wire on-demand diagnosis and additive truthful status through Packages/CamLidCore/Sources/CamLidApp/ControlService.swift, Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift and Packages/CamLidCore/Sources/CamLidCLI/Commands.swift; never run subprocesses on periodic status tick or infer active mode from defaults (FR-001–004).
- [x] T009 [US1] Render shared report in Packages/CamLidCore/Sources/CamLidApp/SleepDiagnosticsView.swift and Packages/CamLidCore/Sources/CamLidApp/UtilityUICoordinator.swift; preserve whole-row disclosure, Refresh/Cmd-R, readable reason/coverage, loading/error/empty states and no foreign-blocker actions (FR-001–004/020).
- [x] T010 [US1] Record isolated GUI/CLI/no-mutation and privacy evidence in docs/qa/awake-automation-report.md using specs/011-awake-automation/quickstart.md US1; report actual checks and limitations, not implementation assumptions (SC-001/008).

## Phase 4: US2 — Qualified display preference (P1)

**Goal**: Apply existing saved preference to owned active resources.
**Independent Test**: Both display choices during sessions, closed-lid internal panel off, Stop/safety/quit and foreign ownership on accepted support row. Live completion requires M1/M2 acceptance recorded by T002.

- [~] T011 [US2] Add display intent/lid-unknown/closed-lid/release tests in Packages/CamLidCore/Tests/CamLidCoreTests/DisplayPreferenceTests.swift covering missing preference=true, active edits preserving deadlines, finite/Infinite safety and no foreign release (FR-005–007, SC-002). — **2026-11-03 cleanup:** Not planned: the display-sleep preference had no effect and was removed from Settings (the stored value stays readable).
- [~] T012 [US2] Extend Packages/CamLidCore/Sources/CamLidCore/PowerController.swift to bind accepted backend system/display resources to existing displaySleepAllowed; missing means true, display hold only when lid open, unknown lid reports unavailable, closed lid clears display hold; retain M2 ownership/restore guards and no backend implementation here (FR-005–007). — **2026-11-03 cleanup:** Not planned (see T011).
- [~] T013 [US2] Apply active per-field preference updates and verified/requested/unavailable read-back in Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift and Packages/CamLidCore/Sources/CamLidApp/SettingsView.swift; do not restart finite duration or Auto delay; preserve active pickers, readable mode icon and no Auto Timed countdown (FR-003/006–007/019–020). — **2026-11-03 cleanup:** Not planned (see T011).
- [~] T014 [US2] Record supervised display preference/session/safety/quit/crash evidence for affected M1 support rows in docs/qa/awake-automation-report.md; distinguish physical panel observation, task continuity and restoration; leave live task incomplete if backend unavailable (SC-002). — **2026-11-03 cleanup:** Not planned (see T011).

## Phase 5: US3 — Protected existing command wrapper (P1)

**Goal**: Optional central-policy protection with exact direct-child lifecycle.
**Independent Test**: Admit before launch or launch nothing; preserve IO/exit; revoke without child kill; lost receipts release and never re-arm. No independent assertion fallback.

- [x] T015 [P] [US3] Add protected wrapper IO/exit/signal/failed-spawn/denied-launch tests in Packages/CamLidCore/Tests/CamLidCLITests/ProtectedRunTests.swift; unprotected existing RunCommand behavior unchanged, detached descendants not declared complete (FR-008–010, SC-003).
- [x] T016 [P] [US3] Add admission/replay/UID/boot/generation/Stop/app-loss tests in Packages/CamLidCore/Tests/CamLidCoreTests/CommandAdmissionTests.swift; enforce "at most 20 concurrent admitted jobs; renewal every 10 seconds; 30-second ownership expiry", no Timed/inactive admission and no universal joint-failure guarantee (FR-008/010, SC-003).
- [x] T017 [US3] Implement session-bound revocable admission in Packages/CamLidCore/Sources/CamLidCore/AutomationModels.swift and Packages/CamLidCore/Sources/CamLidCore/PolicyEngine.swift; require explicit Auto, verified backend/current safety, "at most 20 concurrent admitted jobs; renewal every 10 seconds; 30-second ownership expiry", strictly increasing receipt sequence, matching UID/boot/generation, failed-spawn cleanup and terminal revocation (FR-008/010).
- [~] T018 [US3] Integrate admit/renew/finish with existing app service and accepted M2 owned lease in Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; Stop/safety/lost owner invalidates admissions, delayed events cannot re-arm, normal direct-child finish releases only its contribution and never claims detached completion (FR-005/008–010). — **2026-11-03 cleanup:** Superseded by ADR 0002: CamLid does not wrap or launch agents; `run` is disabled.
- [~] T019 [US3] Add --keep-awake admission-before-launch, renewals, stderr revocation reporting and finish cleanup in Packages/CamLidCore/Sources/CamLidCLI/RunCommand.swift and Packages/CamLidCore/Sources/CamLidCLI/Commands.swift; preserve direct argv/stdin/stdout/exit semantics, no automatic app/mode launch, no output/argument persistence (FR-008–010/021). — **2026-11-03 cleanup:** Superseded by ADR 0002 (see T018).
- [~] T020 [US3] Record wrapper policy, IPC security and qualified live lease release evidence in docs/qa/awake-automation-report.md; simulate failed executor separately and retain existing joint/OS failure limitations (SC-003). — **2026-11-03 cleanup:** Superseded by ADR 0002 (see T018).

## Phase 6: US4 — Exact lifetime rules (P2)

**Goal**: Explicit lifetime protection for unsupported programs without AI completion inference.
**Independent Test**: Exact selectors, stable identities, absence/unknown, rule overlap and explicit Stop; stopped/Timed do nothing.

- [x] T021 [P] [US4] Add rule validation/epoch/unknown/Stop/deadline tests in Packages/CamLidCore/Tests/CamLidCoreTests/LifetimeRuleTests.swift; reject generic selectors, bound unknown with existing wait policy, no process-derived completion sleep (FR-011–013, SC-004).
- [x] T022 [P] [US4] Extend Packages/CamLidCore/Tests/CamLidAppTests/NativeProcessListTests.swift for exact executable/bundle identity, PID/start-time/UID reuse, complete absence vs truncation/error, path changes and no argv collection (FR-011–013/021, SC-004).
- [x] T023 [US4] Add validated LifetimeRule.swift and optional migration-safe rules in Packages/CamLidCore/Sources/CamLidCore/LifetimeRule.swift and Packages/CamLidCore/Sources/CamLidCore/Configuration.swift; enforce "at most 20 rules; selectorValue 1–1024 UTF-8 bytes; label 1–80 characters; duplicates by kind/value rejected", absolute normalized executable file or installed bundle identity, no wildcard/regex/generic targets, missing rules=empty (FR-011/021).
- [x] T024 [US4] Extend existing Packages/CamLidCore/Sources/CamLidApp/NativeProcessList.swift and Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift sampling with same-UID exact metadata and stable PID/start-time identities; "at most 4096 processes per observation; two complete absent observations at least 5 seconds apart", errors/truncation/staleness unknown, no basename/argv fallback (FR-011–013).
- [x] T025 [US4] Integrate separate lifetime contribution/epoch in Packages/CamLidCore/Sources/CamLidCore/PolicyEngine.swift; only explicit Auto, safety/cap unchanged, unknown bound reuses waiting policy, current lifetime epoch ineligible for completion sleep, Stop generation suppresses re-arm, never fabricate NormalizedEvent AI completion (FR-012–013).
- [x] T026 [US4] Add revision-aware rule editing/list/remove in Packages/CamLidCore/Sources/CamLidApp/SettingsEditor.swift, Packages/CamLidCore/Sources/CamLidApp/SettingsView.swift and Packages/CamLidCore/Sources/CamLidCLI/Commands.swift; show relevant lifetime reason in Packages/CamLidCore/Sources/CamLidApp/DashboardView.swift only while relevant, preserve agent CLI-detection-only settings and no implicit arm; record scenario evidence in docs/qa/awake-automation-report.md (FR-011–013/019–021, SC-004/008).

## Phase 7: US5 — Guarded terminal sleep (P2)

**Goal**: Read-only dry-run followed by separately revalidated safe request.
**Independent Test**: All blocked/unknown cases mutate nothing; one qualified allowed case records requested then physical observed sleep.

- [x] T027 [P] [US5] Add eligibility matrix tests in Packages/CamLidCore/Tests/CamLidCoreTests/SleepDecisionTests.swift; "all admission inputs at most 5 seconds old; no user input for at least 60 seconds", no work/wait/unknown contributors, closed lid OR all connected displays confirmed asleep, verified restoration, Preview deny and no force bypass (FR-014–015, SC-005).
- [x] T028 [P] [US5] Add dry-run/no-mutation/fresh-revalidation/unsupported/structured-reasons tests in Packages/CamLidCore/Tests/CamLidCLITests/SleepCommandTests.swift; reject --force and never treat backend acknowledgement as observed sleep (FR-014–015, SC-005).
- [x] T029 [US5] Implement portable decision/reason model in Packages/CamLidCore/Sources/CamLidCore/SleepDecision.swift and extend Packages/CamLidCore/Sources/CamLidCore/PowerController.swift existing restoration gate; "all admission inputs at most 5 seconds old; no user input for at least 60 seconds", zero display without qualified evidence unknown, no release of foreign blockers, requested != observed (FR-014–015).
- [ ] T030 [US5] Add qualified read-only recent-input/display freshness to Packages/CamLidCore/Sources/CamLidApp/LiveSensors.swift and revalidated sleep admission to Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; unknown collector blocks, dry-run never restores or writes, actual request uses accepted M2 backend only after verified restoration (FR-005/014–015).
- [ ] T031 [US5] Add sleep/dry-run commands in Packages/CamLidCore/Sources/CamLidCLI/Commands.swift and structured requested/observed/blocked history through Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; report acknowledgement before suspension, record eligible supervised physical test after wake in docs/qa/awake-automation-report.md (FR-014–015, SC-005). **2026-11-05 blocked:** `camlid sleep --dry-run` works and returns `blocked` (`displayAwake`, `inUse`, `workUnknown`, `previewOnly`). The non-dry-run path passes `backendVerified: false` in `AppCoordinator`, so no request can become eligible; the supervised physical test cannot run until backend verification is designed. Evidence: [native matrix addendum](../../docs/qa/native-matrix-2026-11-05.md). Not ticked.

## Phase 8: US6 — Useful local alerts (P2)

**Goal**: Opt-in accurate alerts without remote services or new notify endpoint.
**Independent Test**: Authorization/denial/revoke, duplicates, ordinary flood and new critical safety/restoration reason.

- [x] T032 [US6] Add permission/rate/dedup/replay/Preview-copy tests in Packages/CamLidCore/Tests/CamLidAppTests/OutcomeNotificationsTests.swift; "at most 5 ordinary alerts per rolling 10 minutes; first critical safety/restoration alert per distinct reason/session bypasses ordinary budget; replay duplicates suppressed" (FR-016–017, SC-006).
- [x] T033 [US6] Add optional alert categories to Packages/CamLidCore/Sources/CamLidCore/Configuration.swift and current strict revision-aware config validation in Packages/CamLidCore/Sources/CamLidCLI/Commands.swift and Packages/CamLidCore/Sources/CamLidApp/SettingsEditor.swift; missing=all off, actual OS permission not a persisted authoritative Boolean (FR-016/021).
- [x] T034 [US6] Implement native authorization/status/delivery in Packages/CamLidCore/Sources/CamLidApp/OutcomeNotifications.swift and subscribe to existing accepted transitions in Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; enforce the T032 rate/critical bounds, fixed private reason templates, bounded dedup keys and no replayed history/argv/transcript payloads (FR-016–017/021).
- [x] T035 [US6] Add category/permission settings in Packages/CamLidCore/Sources/CamLidApp/SettingsView.swift and route explicit UI enablement through Packages/CamLidCore/Sources/CamLidApp/UtilityUICoordinator.swift; CLI stores intent without unexpected prompt, denial stays visible, no repeated prompt or Dashboard duplication; record native alert evidence in docs/qa/awake-automation-report.md (FR-016–017/019–020, SC-006/008).

## Phase 9: US7 — Operational login startup (P2)

**Goal**: Finish existing stored intent with native registration; no session auto-resume.
**Independent Test**: Actual enable/approval/revoke/disable/login/update/uninstall state, zero auto sessions.

- [x] T036 [US7] Add login intent/actual-state/registration-error/revoke/no-auto-arm tests in Packages/CamLidCore/Tests/CamLidAppTests/LoginItemControllerTests.swift; missing intent=false, OS enabled/requiresApproval/notRegistered/notFound/error authoritative (FR-018/021, SC-007).
- [x] T037 [US7] Implement native SMAppService.mainApp register/unregister/status reconciliation in Packages/CamLidCore/Sources/CamLidApp/LoginItemController.swift and Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift; keep existing launchAtLogin intent separate, preserve errors, startup recovery never resumes/arms sessions (FR-018).
- [x] T038 [US7] Show actual approval/registration/error alongside persistent preference in Packages/CamLidCore/Sources/CamLidApp/SettingsView.swift and Packages/CamLidCore/Sources/CamLidApp/UtilityUICoordinator.swift; refresh on Settings activation, use native approval guidance, avoid fake successful config read-back (FR-018–020).
- [~] T039 [US7] Integrate owned login registration cleanup into existing M5 update/uninstall procedure in specs/006-signed-beta/quickstart.md and specs/006-signed-beta/plan.md; run signed isolated-app login/revoke/disable/update/uninstall checks and record evidence in docs/qa/awake-automation-report.md, never change user's installed login preference as QA without authorization (FR-018/022, SC-007). — **2026-11-03 cleanup:** Superseded by ADR 0004: updates are manual downloads and uninstall is Remove helper then delete the app.

## Phase 10: Polish & cross-cutting acceptance

- [x] T040 Run integrated Core/CLI/App suites and existing simulator policy/security/recovery cases; record invalid UID/frame/replay, malformed config, privacy, continuous-clock/wake and critical safety results in docs/qa/awake-automation-report.md; confirm no new dependency, foreign resource change, arguments/output collection or Preview actuation (FR-021–022, SC-001–007).
- [x] T041 Inspect all affected native surfaces using specs/011-awake-automation/quickstart.md at small/large sizes, light/dark, keyboard/labels/hover/disclosure/loading/error states; verify active pickers, no Auto countdown, readable menu icon, detection-only Agent settings and no duplicated mode controls; record artifacts in docs/qa/awake-automation-report.md (FR-019–020, SC-008).
- [x] T042 Audit supervised physical evidence for affected power/display/sleep/lease support rows and update docs/planning/limitations.md and Tests/Hardware/PowerFeasibility.md; distinguish simulator/native/physical outcomes and leave unavailable support unclaimed (FR-005/022, SC-002–005).
- [x] T043 Update README.md, docs/planning/roadmap.md, specs/README.md and docs/qa/awake-automation-report.md with actual feature dispositions, command help links, migrations/limits and M5/M6 regression status; M8 cannot claim integrated PASS with unresolved critical/high defects or replace M7 user gate (FR-022, SC-001–008).

## Dependencies & execution order

Setup T001–002 -> Foundation T003–004 -> story work. Record blocked M1/M2 state rather than holding read-only work indefinitely.

| Story | Tasks | Dependencies | Independent acceptance |
| --- | --- | --- | --- |
| US1 P1 | T005–010 (6) | Foundation; no live backend | Shared truthful bounded diagnosis with no host mutation |
| US2 P1 | T011–014 (4) | Foundation; M1/M2 for live execution/acceptance | Qualified display preference and release behavior |
| US3 P1 | T015–020 (6) | Foundation; M1/M2 for verified hold | Admission/child behavior/expiry; no US2 display extension required |
| US4 P2 | T021–026 (6) | Foundation; existing process collector/policy; M1/M2 for hold | Exact lifetime rules, no AI completion inference |
| US5 P2 | T027–031 (5) | Foundation; existing M2 restoration/sleep capability | No-mutation dry-run, safe request and independent observation |
| US6 P2 | T032–035 (4) | Foundation; existing transitions only | Accurate opt-in local alerts; works in Preview |
| US7 P2 | T036–039 (4) | Foundation; signed identity for OS/login acceptance | Registration/read-back/no automatic session |
| Cross-cutting | T040–043 (4) | Implemented stories; physical/live gate evidence for final PASS | Integrated regression and release-gate disposition |

US1/6/7 do not require US2–5. US2–5 are independently simulator-testable against existing M2 contracts; live acceptance needs accepted backend, not another story's implementation. Shared AppCoordinator/Configuration/Commands/Settings edits must be serialized or explicitly integrated to avoid conflicts. Tests marked [P] can be authored in parallel; execute relevant failing tests before implementation. All implementation/test assertions must match the [model bounds](data-model.md).

## Parallel examples

- US1: T005 CLI contract tests and T006 App collector tests are independent files after foundation.
- US2: Serialize T011 -> T012 -> T013 -> T014; no safe intra-story parallel implementation proposed. Its initial test authoring can overlap US6 T032, a different test file.
- US3: T015 CLI wrapper and T016 core admission tests in parallel; T017–019 sequential shared-flow integration.
- US4: T021 policy validation and T022 native observation tests in parallel; T023–026 sequential.
- US5: T027 portable decision and T028 CLI contract tests in parallel; T029–031 sequential.
- US6: Serialize T032–035; T032 test authoring can overlap US7 T036, a different file.
- US7: Serialize T036–039; T037 concrete native controller can overlap US1 T007 only after their respective prerequisite tests and without parallel AppCoordinator edits.

Parallel opportunities do not request agents or change ownership. No speculative shared framework or scaffolding tasks.

## Implementation strategy

MVP: T001–010 (10 tasks), demonstrate US1 in Preview with meaningful tests and native evidence. Then US6/US7 as independent increments. Advance US2/3/4/5 after M1/M2 acceptance; simulate first, verify physical effects separately. Run T040–043 for integration, extend M5/M6 existing gates and proceed to M7 only after required PASS. Do not mark tasks complete merely because this plan or a simulator exists.

## Requirement coverage

FR-001–004 -> T003/005–010; FR-005–007 -> T001–002/011–014/042;
FR-008–010 -> T004/015–020; FR-011–013 -> T021–026;
FR-014–015 -> T004/027–031; FR-016–017 -> T032–035;
FR-018 -> T036–039; FR-019–020 -> T009/013/026/035/038/041;
FR-021 -> T004/007/019/023/026/033–034/040;
FR-022 -> all story acceptance plus T039–043. SC-001–008 map to the story checkpoints and T040–043. Full VoiceOver acceptance remains excluded by the existing explicit user revision, not silently reinstated here.


## Implementation handoff — 2026-10-08

Completed markers identify implemented/tested work or the explicit evidence/report task, not milestone/release acceptance. Requirements checklists remain reviewer-owned and unchanged.

- T004 is partial: diagnosis/sleep and deny-only command operations use the authenticated transport. Diagnostic JSON plus base64 wire envelope fits 64 KiB. Typed lease receipts/renewal remain gated.
- T011–014 and T018–020 remain open: no qualified M1/M2 live backend exists. Display binding and protected admission/renew/finish lease integration stay gated.
- T015 complete: focused checks cover direct argv, stdin/stdout/stderr inheritance, exit/signal mapping, spawn failure, denial-before-launch and direct-child-only completion reporting. Live admission/renewal/release remains gated under T018–020.
- T021–026 complete: exact selector validation and migration, bounded same-user process snapshots, two-scan absence, bounded unknown holds, Auto-only lifetime policy, revision-aware CLI/Settings editing, and relevant Dashboard reasons are implemented. Synthetic lifecycle tests and a native scanner smoke test pass; live app process-transition and physical power acceptance remain open.
- T027–029 complete: portable decision, restoration gate and blocker matrix are tested. T030–031 remain partial: Preview samples display/input separately, rejects stale/future samples, recollects on each request and refuses actual requests. Actual blocked requests now record their blockers through existing V1 history; dry-run and invalid requests write nothing. No qualified backend sleep request, requested/observed history or physical sleep evidence exists.
- T035 complete for Preview/native-adapter acceptance: explicit GUI enablement produced native consent; Allow returned `didGrant: 1`, `hasError: 0`. Real sequence-0 failure delivery and a transient completion banner were observed. All four category switches persisted. A no-power fixture using production OutcomeNotifications and real macOS delivery verified 0 submissions with categories Off, 5 ordinary submissions, suppression of the sixth, 2 critical bypasses, deduplication of repeated safety/restoration reasons, and 7 native delivered requests without errors. Revocation refreshed the existing Settings window to disabled. Restoration outcomes were injected, not actual backend failures; critical means application-budget bypass, not Apple's Critical Alerts entitlement. Signed/physical M5/M1/M2 gates remain open. Earlier consent errors/buffered checks remain historical evidence in the report.
- T039: owned login update/removal procedure added to M5 docs. On 2026-10-08, `security find-identity -v -p codesigning` reported 0 valid identities; signed register/login/revoke/update/uninstall acceptance remains NOT RUN.
- T041: All five Settings tabs inspected in both appearances at 500×360/840×720. Light Activity Log and Sleep Requests were captured at their 560×360/501×360 minimums plus 840×720; disclosures and menu openings verified. Follow-up state is isolated. Installed Preview Dashboard opens and Escape closes it; direct layer-25 capture corrects the layer-0 discovery limitation. Twelve hidden native diagnostic fixtures cover loading/empty/error at both sizes and appearances without clipping; these do not prove live collection. After unlock, Defaults Tab/Shift-Tab focus, the visible focus ring and native Timed help tooltip were verified. Global keyboard navigation was temporarily enabled and restored Off; pointer and prior focus restored. Further isolated QA fixed the missing native Edit menu with red/green regression and native Select All/Cmd-A replacement checks. Agents, Watched Programs, Safety and Activity keyboard focus/readbacks, direct Auto/Timed activation/switch/stop and finite/Infinite timer edits were observed; saved defaults stayed unchanged and Preview never actuated power. The desktop then moved to another Space. Final continuation completed the remaining Dashboard checks: active Auto delay changed 2→5 min without changing the saved 2-min default or restarting the session; native Tab/Shift-Tab rings covered Auto, Timed, the delay picker and Activity; Space switched to Timed and opened the delay menu. Native Activity/Auto hover help and the right-click menu were observed. Cropped native menu-bar evidence shows readable inactive/active icons in Light/Dark, including the truthful safety-stopped icon. Existing icon regressions cover distinct Auto/Timed symbols. Preview never actuated power; low battery and an intermittent unknown lid remained safety-latched rather than bypassed. See the [QA report](../../docs/qa/awake-automation-report.md). T041 is complete for the affected Preview UI matrix, not physical/VoiceOver acceptance.
- T040: Final serial regression passes 437 executed tests (440 cases; three optional live probes skipped); five earlier packaging tests pass. Both final Debug/Release Xcode builds succeed with signing disabled. New red/green checks cover reordered terminal alerts, distinct run/epoch identities, process-only evidence exclusion, blocked-sleep history and permission refresh when returning to Settings, plus standard native editing-menu bindings. Earlier concurrent-run timing failures retained. This does not satisfy M6 load/performance or M5 signing gates.
- Continuation checks: `WatchCommandTests` 5/5 and `ProtectedRunTests` 3/3 pass. No GUI or native OS acceptance was run for these changes.
- T042: physical evidence audit found zero accepted M8 power rows. All relevant hardware cases remain NOT RUN; no simulated support PASS.
- Cleanup: final isolated QA parent/helper quit and were verified absent by exact PID and NSWorkspace before removing their bundle/state/build artifacts. Installed Preview remains running. Filtered process listings and layer-0 window lists must not be used as proof of process exit.
