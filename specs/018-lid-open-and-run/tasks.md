# Tasks: v0.2 — lid-open keep-awake, wrapper, shortcut, calibration

**Feature context:** `018-lid-open-and-run` · **Status:** 1/23 checked. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [ ] T001 Write and accept ADR 0006 (amends ADR 0002).
- [x] T002 Confirm Q-C and Q-D. — Q-C: yes, with the default. Q-D: default (display sleep not in v0.2). 2026-11-05.

## Phase 1 — Lid-open keep-awake (US1)
- [ ] T010 [US1] `KeepAwakeAssertion` with create, read-back and release; a fake for tests.
- [ ] T011 [US1] Tests: create → read back → release; read-back failure → unverified.
- [ ] T012 [US1] Split `holdDesired` into the lid-open and closed-lid paths.
- [ ] T013 [US1] Readiness evidence `assertionVerified`; precedence tests.
- [ ] T014 [US1] Dashboard and Settings copy for the lid-open and lid-closed cases.
- [ ] T015 [US1] Sleep diagnostics label CamLid's own assertion and exclude it from "another app".
- [ ] T016 [US1] Live: acceptance items 1–4 of User Story 1 on the installed build.

## Phase 2 — Command wrapper (US2)
- [ ] T020 [US2] Implement admit, renew and finish (replace the `backendPendingM1` stubs).
- [ ] T021 [US2] Route `camlid run` to `RunCommand`; connect `isArmed`.
- [ ] T022 [US2] Tests: exit mapping, signal forwarding, refusal without the app.
- [ ] T023 [US2] Activity records exit status, duration and hold state only; test that argv and output are not stored.
- [ ] T024 [US2] Live: the four User Story 2 cases.

## Phase 3 — Shortcut (US3)
- [ ] T030 [US3] `GlobalHotKey` (⌃⌥⌘K), registered at start, released at quit.
- [ ] T031 [US3] Check with another app in front; no permission prompt.

## Phase 4 — Calibration (US4)
- [ ] T040 [US4] Calibration runs for Claude Code, Codex and OpenCode with `scripts/agent-activity-calibrate.py`; record in the QA addendum.
- [ ] T041 [US4] Adjust thresholds only with recorded runs.
- [ ] T042 [US4] Fixture for the busy-without-session rule.

## Phase 5 — Release and regression
- [ ] T050 Release note for the behaviour change (lid-open holds for closed-lid-off users).
- [ ] T051 Full test run in all packages.
- [ ] T052 Closed-lid regression: subset of S1–S4 on the installed build.
- [ ] T053 Owner approves release.
