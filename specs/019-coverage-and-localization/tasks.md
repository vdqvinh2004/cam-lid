# Tasks: v0.3 — coverage, Vietnamese, maintenance

**Feature context:** `019-coverage-and-localization` · **Status:** 1/27 checked. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [x] T001 Owner decides Q-E: build audio holds, after research. — 2026-11-05.

## Phase 1 — Localization (US1)
- [ ] T010 [US1] Inventory every user-visible string (Dashboard, Settings, Activity, Onboarding, Updates, menu, notifications, help).
- [ ] T011 [US1] Create the String Catalog with English and Vietnamese values.
- [ ] T012 [US1] Replace literals with catalogue keys; keep keys stable.
- [ ] T013 [US1] Test: every key has a Vietnamese value.
- [ ] T014 [US1] Screen check in Vietnamese; record any English left.

## Phase 2 — Helper guard (US2)
- [ ] T020 [US2] `scripts/check-helper-version.sh` comparing helper sources with the last tag.
- [ ] T021 [US2] Test on a clean tree (pass) and on a deliberate change (fail).
- [ ] T022 [US2] Call it from `release.sh`.

## Phase 3 — Simulation and start (US3)
- [ ] T030 [US3] `simulate --use-current-config`.
- [ ] T031 [US3] Replay one recorded session; record the match.
- [ ] T032 [US3] `start` stops persisting the mode; release note.

## Phase 4 — Coverage (US4)
- [ ] T040 [US4] Qualify one more Mac or macOS build, or record "not planned for 0.3".

## Phase 5 — Owner tests (US6)
- [ ] T050 [US6] T026: lid transitions; record; temperature stays blocked without a reference.
- [ ] T051 [US6] T306: battery stop-level session with the lid closed.
- [ ] T052 [US6] Grace in a real session.
- [ ] T053 [US6] VoiceOver walkthrough.
- [ ] T054 [US6] Notch and second display.

## Phase 6 — Repo hygiene (US5)
- [ ] T060 [US5] Resolve every `[~]` in specs 002–011 (done, or a recorded reason).
- [ ] T061 [US5] Remove or replace references to ignored directories; scripted check.
- [ ] T062 [US5] Update `specs/README.md`.

## Phase 7 — Audio research (FR-007)
- [ ] T070 Research whether other processes' power assertions give a reliable audio signal; record in a spec note.
- [ ] T071 Go or no-go for the audio hold, from the T070 result.

## Phase 8 — Audio hold (US7, Q-E)
- [ ] T080 [US7] Implement the signal reader chosen in T070, behind a protocol with a fake for tests.
- [ ] T081 [US7] Add an audio-playback rule type next to watched programs, for Auto sessions.
- [ ] T082 [US7] Tests: the rule holds while audio plays; ends after the quiet period (proposed 60 s); never holds without an audio source; Activity records start and end only.
- [ ] T083 [US7] Live: audio plays with the lid open and the Auto session holds; audio stops; the hold ends within the quiet period.
