# Tasks: automatic update setting (v0.2)

**Feature context:** `021-automatic-updates` · **Status:** 15/19 checked. Open: the GUI check, the owner's review of the
privacy wording, release notes and the installed-build check. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [x] T001 Owner decisions, 2026-11-09: once a day (24 hours); install mode deferred; ADR 0004 amended.
- [x] T002 ADR 0004 amendment for the opt-in daily check: [ADR 0004](../../docs/adr/0004-distribution-through-github-releases.md), section "Amendment (2026-11-09)".

## Phase 1 — Setting and scheduled check (FR-001 to FR-004, US1 to US3)
- [x] T010 [FR-001] Setting `CamLidAutomaticUpdateChecks` in the app's preferences; Off when the key is missing, so an upgrade never turns it on. `UpdateController.swift`; `offByDefaultAndNeverRequestsOnItsOwn`.
- [x] T011 [FR-002] A scheduled check starts the same request as the manual check (`startRequest`, `GitHubReleaseDriver`). No new endpoint, no cookies, no account.
- [x] T012 [FR-003] At most one request per 24 hours, counted from the last request of any kind, kept across relaunches. `checksAtMostOnceADayWhileOn`, `aManualCheckCountsTowardTheDay`, `theDayAndTheSettingSurviveARelaunch`.
- [x] T013 [FR-003] A session or a recovery makes the check wait; the next hourly tick tries again. `aSessionOrRecoveryWaitsAndTheNextTickTriesAgain`.
- [x] T014 [FR-004] Never downloads or installs: the check reads release metadata only; no new code path does more.
- [x] T015 [US3] Agent activity and unsaved Settings do not delay the daily check. `agentActivityAndUnsavedSettingsDoNotDelayTheDailyCheck`.

## Phase 2 — Settings window and copy (FR-005, US1, US2)
- [x] T020 [FR-005] Settings › General toggle "Check for new releases once a day", with the request described in its footer. `SettingsView.swift`, `SettingsEditor.swift`, `UtilityUICoordinator.swift`, `UtilityUIProcess.swift`.
- [x] T021 [US2] The Updates window's default text names the daily check when it is on. `UpdatesView.swift`.
- [ ] T022 [FR-005] Look at the toggle in the built app, light and dark, with the keyboard and VoiceOver. Not done: see the report for the GUI check status.

## Phase 3 — Documents (FR-006)
- [x] T030 [FR-006] README "Updating" and "Privacy" name the setting and the one daily request (drafted 2026-11-09).
- [x] T031 [FR-006] SECURITY.md names the setting and the daily request (drafted 2026-11-09).
- [ ] T032 [FR-006] Owner reviews the privacy wording in README and SECURITY.md before release. Owner decision.

## Phase 4 — Tests (SC-001 to SC-003)
- [x] T040 [SC-001] With the setting Off, no request is made by the scheduler at any time. `offByDefaultAndNeverRequestsOnItsOwn`.
- [x] T041 [SC-002] With Check on, at most one request per 24 hours, and none while a session is active. `checksAtMostOnceADayWhileOn`, `aSessionOrRecoveryWaitsAndTheNextTickTriesAgain`.
- [x] T042 [SC-003] Switching to Off stops scheduled checks at once. `turningItOffStopsTheChecksAtOnce`.

## Phase 5 — Release
- [ ] T050 Release notes for v0.2 mention the setting. The template in `scripts/release.sh` still needs an owner pass before publishing.
- [~] T051 On the installed build: switch Check on, confirm one request in the day, switch Off. Owner, before release. QA build (2026-11-09): on writes the setting and off clears it; the first scheduled request and the deferred manual check were not observed ([qa-evidence.md](../024-release-readiness-v0.2/qa-evidence.md)).
