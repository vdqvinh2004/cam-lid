# Tasks: display option, copyable diagnostics, Chromium audio hold (v0.2)

**Feature context:** `023-feature-parity` · **Status:** 14/18 checked, 3 partly, 1 open. Sources: [spec.md](spec.md), [comparison.md](comparison.md).

Implemented 2026-11-09, not committed. Evidence is the focused and full CamLidCore test runs (354 tests in 69 suites pass) and a Release build. No live check was run: the open items are the ones that need a real Mac.

## Phase 0 — Decisions
- [x] T001 D1–D4 accepted as recommended, 2026-11-09 ([spec.md](spec.md), "Decisions").
- [x] T002 Spec 019 T071 recorded as go, browsers only. Tasks T080–T083 are tracked here as Phase 3.

## Phase 1 — Display option (US1; FR-001 to FR-004)
- [x] T010 [FR-001] Settings › General › New sessions: "Let the display sleep during sessions", bound to `allowDisplaySleep` through the existing `setAllowDisplaySleep` (`SettingsView.swift`).
- [x] T011 [FR-003] `DisplaySleepChoice` (`KeepAwakeAssertion.swift`) reads the setting while no session runs and holds it until the session ends. Test `theDisplayChoiceIsReadWhileIdleAndHeldDuringASession`.
- [x] T012 [FR-002] `AppCoordinator` reconciles a second `KeepAwakeAssertion` for `PreventUserIdleDisplaySleep` with its own reason. The same create, read-back and release path. Released at quit.
- [~] T013 [FR-004] Code evidence only: the "CamLid is active" rule in `SleepDiagnosticsCopy.swift` matches the process `camlid`, which creates the display assertion. Not seen on screen.
- [x] T014 [SC-001, SC-002] Tests in `DisplayHoldTests`: no display assertion by default; with the option off, exactly one held and released at the end.

## Phase 2 — Copyable diagnostics (US2; FR-005, FR-006)
- [x] T020 [FR-006] `DiagnosticReport.swift`: plain text from an allow-list of snapshot fields. Blocker sources, explanations and PIDs are left out.
- [~] T021 [FR-005] "Copy diagnostics" button in `SleepDiagnosticsView`, copying on press only. Built; not clicked on a live app.
- [x] T022 [SC-003] Test `excludedDetailNeverAppears` (`DiagnosticReportTests`).

## Phase 3 — Chromium audio hold (US3; FR-007, SC-004; from spec 019 T080–T083)
- [x] T030 [T080] `AudioPlaybackSignal`: the named "Playing audio" assertion of `NoIdleSleepAssertion` held by a browser process. The filter is pure and tested; the IOKit reader is live only.
- [x] T031 [T081] Implemented as a switch in Watched programs, "Keep Auto awake while a Chromium browser plays audio", not as a new rule row. Tradeoff: no new rule kind and no config field; the switch is a preference, like the update check.
- [~] T032 [T082] The hold ends 60 s after the last playback observation (`AudioPlaybackHold`). It only counts for Auto sessions, through the policy's hold reason `browserAudioPlayback`. The Dashboard shows "A Chromium browser is playing audio." Activity records start and end only as state transitions; not checked in the history.
- [x] T033 [T082] Tests in `AudioPlaybackSignalTests`: holds while the signal exists, ends after the quiet period, never holds without a signal, ignores other assertions and other apps.
- [ ] T034 [T083] Live check with a Chromium browser on this Mac. Not run.

## Phase 4 — Verification and records
- [x] T040 Focused suites pass; full CamLidCore run: 354 tests in 69 suites pass.
- [x] T041 Release build succeeds (`xcodebuild`, `CODE_SIGNING_ALLOWED=NO`); the bundled SKILL.md matches the repository file.
- [x] T042 Status and task records updated with the evidence above.
