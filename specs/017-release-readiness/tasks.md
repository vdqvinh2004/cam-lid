# Tasks: Release readiness for v0.1.0

**Feature context:** `017-release-readiness` · **Status:** 18/19 checked (T015 partly). Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [x] T001 Owner decides Q-A: Strict stays visible, labelled experimental. — 2026-11-05.
- [x] T002 Run the measurement gate (User Story 2); record the result in the QA addendum; choose window or no window. — 2026-11-06: no window; the result is in `specs/017-release-readiness/qa-addendum.md`.

## Phase 1 — Readiness and wording (US1)
- [x] T010 [US1] Build kind comes from the build configuration: `ProtectionBuildKind.current` (DEBUG → development, otherwise release). The hardcoded `.preview` is gone. — 2026-11-05.
- [x] T011 [US1] Precedence tests: release facts with a verified lease → Protected; without a lease → Ready with `leaseNotVerified`; unknown ownership without a helper → Needs setup, not Conflict. The last one was an existing bug (a missing helper showed Conflict); fixed here. — 2026-11-05.
- [x] T012 [US1] Renamed: `commandNotAvailableInPreview` → `commandNotAvailable`; `modeOffPreview` → `modeOff`; `backendPendingM1` → `automationUnavailable` (admit, renew, finish); `previewOnly` → `backendUnverified`. `previewPowerDisabled` removed with the Preview state. No aliases (see FR-003). Activity labels keep the old codes, so stored history reads correctly. — 2026-11-05.
- [x] T013 [US1] `camlid status` has no `preview` field. `protection.readinessState` carries the state; top-level `effectiveState` and `reasonCodes` carry the same state and the blockers. `start` already reported `powerActuation` from the lease, so it was not changed. — 2026-11-05.
- [x] T014 [US1] Preview branch removed from `OutcomeNotifications` (title and body); Activity labels for the new codes. — 2026-11-05.
- [~] T015 [US1] Live check: status and Dashboard agree at each checkpoint of a session. Status checked on the installed
  build (readiness never says Preview; `keepAwake` and `leaseVerified` agree with the session). Dashboard not checked:
  the popover is not readable through accessibility and the cua-driver connection dropped. 2026-11-05: the driver answers
  again on its default socket, with Accessibility and Screen Recording granted. A status snapshot taken then: auto session
  (an observed Orca task working), configured `timed`, `keepAwake` held and verified, shortcut registered. The popover was
  closed (no CamLid window listed). 2026-11-05, later: the menu-bar icon was clicked through desktop input, the popover was
  read from a screenshot, and a second click closed it. At idle it matches `camlid status`: Ready, neither Auto nor Timed
  active, battery 83%, lid open, thermal fair, Orca 2 working. CPU and temperature differ a little between the two reads
  (sampled at different times). Second checkpoint, same day, Auto started with `camlid start --mode auto`: the Dashboard
  showed Auto selected and "Sleep when done: After 2 min", but its header read "Unknown" while status had session
  `protected`, `keepAwake` held and verified, and `leaseVerified` false. Cause: `MenuBarController.presentedState` maps
  `protected` to `unavailable` whenever the helper lease is unverified, even with the lid open. Decided by the owner: a verified
  lid-open keep-awake shows "Keeping awake (lid open)", never "Protected". Fixed in code 2026-11-05. Installed 2026-11-05
  (CDHash `0068507b…`): with the closed-lid lease verified, the Dashboard showed Protected, matching status. The new label
  has not been seen live; it needs an unverified lease with the lid open. 2026-11-06: the checkpoint after the Auto session ended matched (Ready, no session, no selected mode, no working task). Still open: the lid-open label on the live app, which needs an unverified lease with the lid open.

## Phase 2 — Sensor timing (US2)
- [x] T020 [US2] Measure sensor-call time and scheduling delay under 100 % CPU for three minutes (the gate). — 2026-11-05,
  Mac17,3, ten cores busy for 180 s (`SensorTimingGateTests`, env-gated). Lid read alone: p99 7 ms, max 11 ms, never
  over 200 ms, from either queue. Whole production read: temperature read median 146 ms, max 478 ms; the whole pass
  went over 200 ms in 13 of 153 reads, and each such pass marked the lid unknown. The stall budget was measured on
  the whole pass, so a slow temperature read stopped the lid.
- [x] T021 [US2] Each source has its own budget (`LiveSensorProvider.settle`): the lid is measured on its own call,
  the die temperature on its own call, and the worker queue is `.userInitiated`. — 2026-11-05.
- [x] T022 [US2] Decision from T020: no tolerance window. The lid call stays far inside 200 ms under full load, so the
  gate's rule (time only the call, raise QoS) applies. — 2026-11-05.
- [x] T023 [US2] Tests: `SensorStallBudgetTests` (4): a slow temperature never marks the lid; a slow lid marks only
  the lid; the lid keeps its read-start time; the budget is 200 ms inclusive. `TemperatureReaderTests` now drives its
  slow read on the clock. — 2026-11-05.
- [x] T024 [US2] Live: three minutes at 100 % CPU with a session running; no `lidUnknown` stop. — 2026-11-05: 190 s
  with ten full-load processes, 95 samples. The session was `protected` in every sample, the lid was open and
  available in every sample, and there was no `slowSensorRead` or stop. Caveat: the session had the closed-lid option
  on, but the helper refused the closed-lid lease (thermal `fair`), so it ran on the lid-open keep-awake. The lid
  stayed open.

## Phase 3 — Release gate (US3)
- [x] T030 [US3] `scripts/release.sh` refuses ad-hoc builds unless `--adhoc`; `--adhoc` builds are named `-ADHOC`.
  `scripts/test-release-arguments.sh` checks the four refusal paths (4/4 pass). — 2026-11-05.
- [x] T031 [US3] Release notes from the template: known limits, signing table (certificate SHA-1, helper version,
  CDHashes, zip SHA-256). Checked in the signed local build's notes; no "Pre-release" or "Preview". — 2026-11-05.
- [x] T032 [US3] README status and build text match the signed release (not notarized, self-signed certificate,
  refusal without the identity). — 2026-11-05.
- [x] T033 [US3] Enable Private vulnerability reporting (owner signs in to `gh`, or uses the web page). — 2026-11-09: repository made public and reporting enabled through `gh api` (`{"enabled":true}`). SECURITY.md also offers e-mail.
- [x] T034 [US3] Full test run in all packages; signed build; install; `helper status` installed. — 2026-11-05: a signed
  local build was installed and `helper status` reports installed. CamLidPowerWire (11), CamLidPowerHelper (94),
  LidRecoveryJournal (21), LidNativeAdapter (22) and LidRecoveryBroker (33) pass. 2026-11-06: release built from commit
  `b685c16` with the release identity (SHA-256 `c5a27ab1…`); the notes name the commit and the signature holds after unzip.
- [x] T035 [US3] Owner approves; create the GitHub release. — 2026-11-09: release v0.1.0 created with `gh` as a pre-release, tag at ed2d060.
