# Tasks: Release readiness for v0.1.0

**Feature context:** `017-release-readiness` · **Status:** 0/19 checked. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [ ] T001 Owner decides Q-A (Strict visibility in the release).
- [ ] T002 Run the measurement gate (User Story 2); record the result in the QA addendum; choose window or no window.

## Phase 1 — Readiness and wording (US1)
- [ ] T010 [US1] Take build kind from the build configuration; remove the hardcoded `.preview` in `protectionReadiness()`.
- [ ] T011 [US1] Precedence test: release facts + verified lease + qualifying safety → protected; without a lease → ready or the true blocker.
- [ ] T012 [US1] Rename `commandNotAvailableInPreview`, `modeOffPreview`, `previewPowerDisabled` and `backendPendingM1` to behaviour-based codes; keep the old codes parseable for one version.
- [ ] T013 [US1] Remove the `preview` field and the "Preview" values from `camlid status`; `start` reports `powerActuation` from the lease.
- [ ] T014 [US1] Remove the Preview branch in `OutcomeNotifications`; readable Activity text for the new codes; test the mapping.
- [ ] T015 [US1] Live check: status and Dashboard agree at each checkpoint of a session.

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
