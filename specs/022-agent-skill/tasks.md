# Tasks: agent skill for the CamLid command (v0.2)

**Feature context:** `022-agent-skill` · **Status:** 16/20 checked (2 partly, 2 open). Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [x] T001 Location: the repository root `.agents/` folder, not `.agent` (spec decision 1).
- [x] T002 ADR 0002 amended for one file: [ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md), section "Amendment (2026-11-09)".

## Phase 1 — Skill file (FR-001 to FR-004)
- [x] T010 [FR-001] `.agents/skills/camlid/SKILL.md`, in English, 51 lines (under 80), no secrets.
- [x] T011 [FR-002] Covers `status --json`, `run --`, `start` (auto and timed), `stop`, `diagnose --json` and `helper status --json`. The last one was missing and was added on 2026-11-09.
- [x] T012 [FR-003] Rules: no settings changes, no stopping a session it did not start, no retry loops, helper admin commands go to the user.
- [~] T013 [FR-004] Each command is run or parsed against the installed binary before each release. Checked 2026-11-09 (run, stop, status, helper status, diagnose and a refused start); on the same day `status --json` and `helper status --json` were run again against the installed 0.1.0 build. Repeat before each release.

## Phase 2 — Settings button and writer (FR-005 to FR-008, FR-010)
- [x] T020 [FR-005] Toggle "Let AI agents use CamLid" in Settings › General, off by default. `SettingsView.swift`.
- [x] T021 [FR-006] The folder is chosen in an open panel, and the file is written only after the button is pressed. Never at launch. `UtilityUICoordinator.swift` (`setAgentSkill`), `AgentSkillInstaller.swift` (`install`).
- [x] T022 [FR-007] Never overwrites a SKILL.md CamLid did not write, and asks first. `aSkillFileCamLidDidNotWriteIsReplacedOnlyWithConsent`.
- [x] T023 [FR-008] Off removes only the file CamLid wrote, and only while its contents are unchanged. `removeDeletesOnlyTheFileItWrote`, `aFileChangedSinceInstallIsLeftInPlace`, `aFileCamLidNeverWroteIsNotRemovedEvenWhenIdentical`, `aFileDeletedByHandIsReportedAndNotRecreated`.
- [x] T024 [FR-010] The only file written is the skill file. No hooks, plugins, wrappers or agent settings. `installWritesExactlyOneFileAndRemembersIt`.
- [x] T025 The record survives a relaunch, and only one installation is allowed at a time. `theRecordSurvivesARelaunchAndOnlyOneFolderIsAllowed`.

## Phase 3 — Bundle and release (FR-009)
- [x] T030 [FR-009] The build copies the skill into the app (`scripts/embed-helper.sh`). Checked 2026-11-09: the Release build's `Contents/Resources/SKILL.md` is identical to the repository file.
- [x] T031 [FR-009] `scripts/release.sh` fails if the bundled copy differs (`verify()`). Checked 2026-11-09: a changed copy makes the comparison fail.
- [x] T032 [FR-009] A build without the bundled copy writes nothing and says so. `aBuildWithoutTheBundledSkillWritesNothing`.

## Phase 4 — Tests (SC-001 to SC-003)
- [x] T040 [SC-002] Turning it on writes exactly one file, and turning it off removes only that file. `installWritesExactlyOneFileAndRemembersIt`, `removeDeletesOnlyTheFileItWrote`.
- [~] T041 [SC-003] The bundled skill matches the repository file in every release. Checked for this build; `scripts/release.sh` repeats the check on each release (T031).
- [ ] T042 [SC-001] An agent that reads the skill keeps a build awake with `camlid run` and reports the result. Not done: it needs an agent run on the owner's Mac.

## Phase 5 — Documents and GUI
- [x] T050 README "Command line" section describes the skill and the button (2026-11-09).
- [ ] T051 [FR-005, FR-006] Look at the button in the built app: the open panel, the conflict alert and turning it Off. Status: see the report.
