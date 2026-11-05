# Tasks: Release readiness for v0.1.0

**Feature context:** `017-release-readiness` · **Status:** 6/19 checked. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [x] T001 Owner decides Q-A: Strict stays visible, labelled experimental. — 2026-11-05.
- [ ] T002 Run the measurement gate (User Story 2); record the result in the QA addendum; choose window or no window.

## Phase 1 — Readiness and wording (US1)
- [x] T010 [US1] Build kind comes from the build configuration: `ProtectionBuildKind.current` (DEBUG → development, otherwise release). The hardcoded `.preview` is gone. — 2026-11-05.
- [x] T011 [US1] Precedence tests: release facts with a verified lease → Protected; without a lease → Ready with `leaseNotVerified`; unknown ownership without a helper → Needs setup, not Conflict. The last one was an existing bug (a missing helper showed Conflict); fixed here. — 2026-11-05.
- [x] T012 [US1] Renamed: `commandNotAvailableInPreview` → `commandNotAvailable`; `modeOffPreview` → `modeOff`; `backendPendingM1` → `automationUnavailable` (admit, renew, finish); `previewOnly` → `backendUnverified`. `previewPowerDisabled` removed with the Preview state. No aliases (see FR-003). Activity labels keep the old codes, so stored history reads correctly. — 2026-11-05.
- [x] T013 [US1] `camlid status` has no `preview` field. `protection.readinessState` carries the state; top-level `effectiveState` and `reasonCodes` carry the same state and the blockers. `start` already reported `powerActuation` from the lease, so it was not changed. — 2026-11-05.
- [x] T014 [US1] Preview branch removed from `OutcomeNotifications` (title and body); Activity labels for the new codes. — 2026-11-05.
- [ ] T015 [US1] Live check: status and Dashboard agree at each checkpoint of a session. Needs an installed build.

## Phase 2 — Sensor timing (US2)
- [ ] T020 [US2] Measure sensor-call time and scheduling delay under 100 % CPU for three minutes (the gate).
- [ ] T021 [US2] Time only the sensor call in `LiveSensorProvider.finish()`; raise the sampler queue's quality of service.
- [ ] T022 [US2] If the gate requires it, add the tolerance window within the spec limits; closed, missing and stale paths stop at once.
- [ ] T023 [US2] Test: a stalled source stops the session within the configured bound.
- [ ] T024 [US2] Live: three minutes at 100 % CPU with a closed-lid session; no `lidUnknown` stop.

## Phase 3 — Release gate (US3)
- [ ] T030 [US3] `scripts/release.sh` refuses ad-hoc builds unless `--adhoc`; test the refusal.
- [ ] T031 [US3] Release-notes template (fingerprint, helper version, CDHash table, tested configuration, limits, Strict line); no "pre-release" or "Preview" wording.
- [ ] T032 [US3] Update `README.md` status, signing and install text (FR-007).
- [ ] T033 [US3] Enable Private vulnerability reporting (owner signs in to `gh`, or uses the web page).
- [ ] T034 [US3] Full test run in all packages; signed build; install; `helper status` installed.
- [ ] T035 [US3] Owner approves; create the GitHub release.
