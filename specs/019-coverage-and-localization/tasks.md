# Tasks: v0.3 — coverage, Vietnamese, maintenance

**Feature context:** `019-coverage-and-localization` · **Status:** 7/27 checked. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [x] T001 Owner decides Q-E: build audio holds, after research. — 2026-11-05.

## Phase 1 — Localization (US1)
- [ ] T010 [US1] Inventory every user-visible string (Dashboard, Settings, Activity, Onboarding, Updates, menu, notifications, help).
- [ ] T011 [US1] Create the String Catalog with English and Vietnamese values.
- [ ] T012 [US1] Replace literals with catalogue keys; keep keys stable.
- [ ] T013 [US1] Test: every key has a Vietnamese value.
- [ ] T014 [US1] Screen check in Vietnamese; record any English left.

## Phase 2 — Helper guard (US2)
- [x] T020 [US2] `scripts/check-helper-version.sh` compares the helper's source fingerprint with a recorded baseline
  (`scripts/helper-version.baseline`), not a tag. — 2026-11-05.
- [x] T021 [US2] `scripts/test-check-helper-version.sh`: six cases (record, unchanged pass, changed without a bump
  fails, bumped passes, re-record, lower version fails). — 2026-11-05.
- [x] T022 [US2] `release.sh` calls the guard before it builds; a failure refuses the release. — 2026-11-05.

## Phase 3 — Simulation and start (US3)
- [x] T030 [US3] `simulate --use-current-config`. — 2026-11-05: reads the saved settings file; defaults when none is saved; fixtures refuse the flag. Live with the debug CLI on the real file: `configSource: saved`, and the echoed mode and `closedLidOptIn` match the file; output without the flag is unchanged.
- [ ] T031 [US3] Replay one recorded session; record the match.
- [x] T032 [US3] `start` stops persisting the mode; release note. — 2026-11-05: `start --mode manual` ran the session in
  manual while the saved mode stayed `timed` (checked live with `config get`). The release note is still to write.

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
- [x] T070 Research whether other processes' power assertions give a reliable audio signal. — 2026-11-05, on this Mac
  (macOS 26A434). A 6-second system sound at 10 % volume created no assertion of its own. `coreaudiod` already holds
  `PreventUserIdleSystemSleep` named `com.apple.audio.…:output.context.preventuseridlesleep` with or without playback,
  so it does not tell playback apart. Brave held `NoIdleSleepAssertion` named "Playing audio" for as long as a page
  played audio. So only Chromium-based browsers show a named playback signal. Music apps and other browsers were not
  tested.
- [ ] T071 Go or no-go for the audio hold. Needs the owner: a browser-only rule covers web audio, not music apps.
  Build it for browsers only, or wait until another signal is found?

## Phase 8 — Audio hold (US7, Q-E)
- [ ] T080 [US7] Implement the signal reader chosen in T070, behind a protocol with a fake for tests.
- [ ] T081 [US7] Add an audio-playback rule type next to watched programs, for Auto sessions.
- [ ] T082 [US7] Tests: the rule holds while audio plays; ends after the quiet period (proposed 60 s); never holds without an audio source; Activity records start and end only.
- [ ] T083 [US7] Live: audio plays with the lid open and the Auto session holds; audio stops; the hold ends within the quiet period.
