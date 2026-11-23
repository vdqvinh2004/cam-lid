# Feature Specification: General audio hold (v0.3)

**Status:** Released in 0.3.0 beta on 2026-11-23, behind the "Any audio" chip, which is off by default. It extends spec 025 from four sources to any app, and replaces spec 019 FR-007 and User Story 7 for that general case. The research gate (T001–T003) is partly done on this Mac; the owner's app matrix (T021) and the go/no-go (T003) are open, and D1–D6 are for the owner to confirm.

## Goal

An Auto session also stays awake while any app plays audio, not only the four sources in spec 025. LidWalk does this for the default output device.

## Before this change (read in the code and specs, 2026-11-19)

- Spec 025 (released in 0.2.0): four opt-in sources (Chromium browsers, Safari, Spotify, Apple Music). Each one reads CoreAudio's list of processes that run audio output, then matches bundle IDs (`MusicPlayback.swift`).
- Spec 025 measured that the output flag closed 2.6 to 2.7 seconds after playback paused, in all four runs. The quiet period therefore has a few seconds of latency built in.
- Spec 019 T070 (2026-11-05): power assertions are not a generic signal. `coreaudiod` holds `PreventUserIdleSystemSleep` with or without playback, and only Chromium browsers name a playback assertion.
- The gap: other players (for example VLC, IINA, podcast apps), Firefox, and any app outside the four sources do not hold the Mac awake.
- LidWalk watches the default output device, holds while anything plays, and stops when the audio goes quiet.

## Decisions (owner to confirm)

- **D1. Signal.** The CoreAudio flag that a process is running audio output, for every process not on the exclusion list. This is the same read that spec 025 uses. No audio content is read. *Recommended.*
- **D2. Exclusions.** Audio-server and alert processes never count, for example `coreaudiod`, `systemsoundserverd` and CamLid itself. The list comes from the research in T002, not from a guess.
- **D3. Start and end.** Output must last 3 seconds before it holds, so short alerts do not. The hold ends 60 seconds after output stops, the quiet period proposed in spec 019. *Recommended.*
- **D4. Default.** Off. An opt-in chip, "Any audio", sits in Settings › Agents next to the four source chips. *Recommended.*
- **D5. Activity.** Record the start and end of the hold with the app's display name. Record no content and no file names. *Recommended.*
- **D6. Gate.** If the research finds false holds from system sounds that the exclusion list cannot remove, or misses real playback, the feature is not built. The result is recorded here, as spec 019 T070 was.

## Requirements

- **FR-001** While an Auto session runs and the "Any audio" chip is on, output from a process that is not excluded holds the session once it has lasted for D3's start time. The hold ends after the quiet period.
- **FR-002** Audio alone never starts a session.
- **FR-003** The rule reads only whether a process is producing output. It reads no audio content, records no audio, and needs no new permission.
- **FR-004** The four spec 025 sources keep working. A process counted by a source is not counted again.
- **FR-005** The hold appears in Activity with its start and end, with the read-back that spec 018 FR-002 requires.
- **FR-006** The exclusion list is a constant in code and is covered by a test.

## Success criteria

- **SC-001** Live matrix on the owner's Mac. Spotify, Apple Music, one other player, Firefox, Chrome and Safari each hold while they play. A system alert and a notification sound at 10 % volume do not hold. Silence never holds. The hold ends 60 seconds after playback stops. Results are recorded in tasks.md.
- **SC-002** Unit tests cover the 3-second start, the 60-second end, the exclusion list, the default-off setting and the rule that audio alone never starts a session.
- **SC-003** A code review confirms that no audio content, file or new permission is used.

## Out of scope

Microphone input (calls, dictation), per-app volume, video frames, and any change to the four spec 025 sources.

## Open after this spec

D1–D6 (owner). The research results decide D2 and D6.
