# Tasks: General audio hold (v0.3)

**Feature context:** `029-general-audio-hold` · **Status:** 7/11 checked. Sources: [spec.md](spec.md).

## Phase 1 — Research gate (D2, D6)

- [ ] T001 On the owner's Mac, record which CoreAudio processes report output while each of these plays or sounds: Spotify, Apple Music, one other player, Firefox, Chrome, Safari, a system alert, a notification sound, and silence. Partly done on 2026-11-19 on this Mac: `afplay` on a sound file reports output (its bundle ID is empty); silence reports nothing; `osascript beep 2` (4-second window) reported no process. Not done: the apps and the notification sound.
- [ ] T002 From T001, write the exclusion list and note any false holds that remain. The provisional list in code: `coreaudiod`, `systemsoundserverd`, `CamLid`, `camlid`, and the CamLid bundle ID. Confirm it after the app matrix.
- [ ] T003 Go or no-go, recorded in spec.md (as spec 019 T071 was). Open: the owner decides after T001.

## Phase 2 — Rule (FR-001 to FR-004)

- [x] T010 Generic audio-output reader: `MusicOutput.Process` carries the PID; `AudioOutputHold.countedNames` decides which processes count. The read is the existing CoreAudio read, so no new permission.
- [x] T011 Start and end rule as a value (`AudioOutputHold`): 3 seconds to start, 60 seconds quiet to end.
- [x] T012 "Any audio" chip in Settings › Agents, default off (`AnyAudioChip`, `SettingsEditor.anyAudioHold`).
- [x] T013 Connected to the Auto session (only an Auto session holds), to Activity (start and end, with app names) and to the reason line. A process counted by an enabled spec 025 source is not counted again.

## Phase 3 — Checks (SC-001 to SC-003)

- [x] T020 Unit tests (`AudioOutputHoldTests`): thresholds, exclusions, default off, and audio alone never starting a session.
- [ ] T021 Live matrix (SC-001), recorded here. Not done: needs the owner's apps playing.
- [x] T022 Review: reads only the output flag and the process name; no audio content and no new permission (SC-003). Checked by reading `MusicPlayback.swift`, `AudioOutputHold.swift` and `AppCoordinator.musicHoldReason`.

## Phase 4 — Docs

- [x] T030 README and SECURITY.md describe the rule without adding data.
