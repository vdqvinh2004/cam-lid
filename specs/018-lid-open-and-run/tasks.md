# Tasks: v0.2 — lid-open keep-awake, wrapper, shortcut, calibration

**Feature context:** `018-lid-open-and-run` · **Status:** 1/23 checked. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [x] T001 Write and accept ADR 0006 (amends ADR 0002); ADR 0002 links to it. — 2026-11-05.
- [x] T002 Confirm Q-C and Q-D. — Q-C: yes, with the default. Q-D: default (display sleep not in v0.2). 2026-11-05.

## Phase 1 — Lid-open keep-awake (US1)
- [x] T010 [US1] `KeepAwakeAssertion` with create, read-back and release, behind an injectable `KeepAwakeSystem`.
- [x] T011 [US1] Tests (5): create → read back → release; read-back failure → unverified; refused create retried;
  re-read at most every 15 s; release is idempotent. — 2026-11-05.
- [x] T012 [US1] Lid-open path `keepAwakeDesired` (protected or grace, lid not closed) next to the closed-lid helper
  path `holdDesired`, which is unchanged.
- [~] T013 [US1] Deviation: readiness stays closed-lid only. Lid-open evidence is reported as `keepAwake`
  (`held`, `verified`, `issue`) in `camlid status`, and counts toward the Dashboard's `powerActuationAvailable`.
- [ ] T014 [US1] Dashboard and Settings copy for the lid-open and lid-closed cases.
- [x] T015 [US1] Sleep diagnostics label CamLid's own assertion and exclude it from "another app". — 2026-11-05: the rule
  reads "CamLid is active" (the old title repeated itself in the headline); test `camLidsOwnAssertionsAreCamLidNotAnotherApp`
  passes (12 tests in the suite). Not yet seen on screen.
- [~] T016 [US1] Live: acceptance items 1–4 of User Story 1 on the installed build. — 2026-11-05. Item 1, with the
  closed-lid option off: the session is `protected`, `keepAwake` is held and verified, and one CamLid assertion is
  listed; the helper is installed but not used. Item 2: a timed stop releases the assertion at once; the Auto grace
  case was not run. Item 3: `kill -9` on the app, and the assertion is gone within 3 s. Item 4: `SleepDisabled` stays
  0 throughout. Not run: a session with the helper not installed.

## Phase 2 — Command wrapper (US2)
- [x] T020 [US2] Implement admit, renew and finish (replace the `backendPendingM1` stubs). — done 2026-11-05, live
  checked. The seam
  exists: `CommandAdmissions` (receipts, uid and generation checks, 20 jobs, 10 s renewal, 30 s ownership) and
  `PolicyEngine.mayAdmitCommand` (Auto sessions only, not latched, backend verified, safety clear). Open design point:
  an admitted command must count as work for the Auto policy, or the hold ends when the agent-task state goes to grace.
  Admission also needs an Auto session, so `camlid run` starts one (as the shortcut does) before admitting.
- [x] T021 [US2] `camlid run` is routed to `CommandRun` (CamLidCLI). It asks for an admission and renews it; it no
  longer reports observation events, so `RunCommand` stays only for its existing tests. — 2026-11-05.
- [~] T022 [US2] Tests: exit mapping, refusal without the app, refusal reason, and the admit/renew/finish flow in the app
  (`ProtectedRunTests`, `CommandRunAdmissionTests`). Signal forwarding is not automated; live-checked 2026-11-05: SIGINT
  reached the command (exit 5), SIGTERM gave 143.
- [~] T023 [US2] Activity records exit status and duration (live: `commandFinished`, `exitStatus:0`, `durationSeconds:8`).
  Only reason codes are stored, so no argv or output; live-checked 2026-11-05 (22,713 exported rows, none with the argument
  text). Not yet a test. The hold state is in the state column, not a code.
- [~] T024 [US2] Live: the four User Story 2 cases. — 2026-11-05 on build 5: (1) exit codes and stdio: `exit 7` → 7 with
  no stdout; `echo hello` passes through; a missing command → 127. (2) The hold is visible while the command runs
  (one CamLid assertion, session `auto`/`protected`, `keepAwake` verified) and it is finished (`commandFinished`).
  (3) App not running → exit 4 and no launch. (4) A hold ending early (`camlid stop`) leaves the command running to its
  own exit code, and stderr names the reason. Not run: a real safety stop (the cause was a `stop`, not a safety rule).

## Phase 3 — Shortcut (US3)
- [x] T030 [US3] `GlobalHotKey` (⌃⌥⌘K), registered at launch and released at quit. — 2026-11-05: `camlid status` reports
  `shortcut.registered: true` on the installed build.
- [~] T031 [US3] Check with another app in front; no permission prompt. — 2026-11-05: System Events sent the chord
  while Terminal was in front. The first press started an Auto session (`configuredMode` stayed `timed`); the second
  stopped it and released the assertion. No prompt was seen on the desk, but the screen was not inspected.

## Phase 4 — Calibration (US4)
- [x] T040 [US4] Calibration runs for Claude Code, Codex and OpenCode with `scripts/agent-activity-calibrate.py`; record in the QA addendum. — 2026-11-05: one valid run per agent, cheap models at low effort (Claude Haiku 5.5, Codex gpt-6-luna, OpenCode big-pickle with `--standalone`); see `specs/018-lid-open-and-run/qa-addendum.md`. Thresholds unchanged (T041).
- [ ] T041 [US4] Adjust thresholds only with recorded runs.
- [x] T042 [US4] Fixture: a CPU-busy process that is not a recognised agent is not Working (ADR 0002). — 2026-11-05: reading agreed with the owner; `BusyNonAgentProcessTests`.

## Phase 5 — Release and regression
- [x] T050 Release note for the behaviour change (lid-open holds for closed-lid-off users). — 2026-11-06: in the 0.1.0 release notes (the template in `scripts/release.sh`).
- [x] T051 Full test run in all packages. — 2026-11-06: CamLidCore 325, CamLidPowerWire 11, CamLidPowerHelper 94, LidRecoveryJournal 21, LidNativeAdapter 22 and LidRecoveryBroker 33 pass.
- [ ] T052 Closed-lid regression: subset of S1–S4 on the installed build.
- [ ] T053 Owner approves release.
