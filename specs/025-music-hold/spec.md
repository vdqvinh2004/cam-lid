# Feature Specification: music hold (browsers, Spotify, Apple Music)

**Status:** Implemented for v0.2 (not released), 2026-11-09. Browser output was checked live on Brave. Spotify and Apple Music
are covered by code and unit tests only: their playback was not started on the owner's Mac.

## Goal

An Auto session stays awake while music plays, with the same mechanism as Auto's agent work. Each source is a switch in
Watched programs, off by default. When the music stops, Sleep when done applies (2 minutes by default).

## Decisions (owner, 2026-11-09)

1. **Sources:** a browser, Spotify and Apple Music. Each has its own switch, like an agent's detection toggle.
2. **Auto only:** the music hold is a lifetime hold reason (`musicPlayback`). The run cap and the safety stops still apply.
   Timed and Infinite sessions ignore it.
3. **Detection:** CoreAudio lists the processes that run audio output. The app matches their bundle IDs, and a helper matches
   by prefix. The read needs no permission and sends nothing to the program (ADR 0002: observer only).
4. **Browsers:** Chromium browsers only (Chrome, Brave, Edge, Vivaldi, Opera, Arc, Chromium). Safari and Firefox are not
   detected.
5. **Quiet period:** the output is read every 5 seconds and the hold bridges 10 seconds between reads. This replaces the
   60-second quiet period of spec 023. The wait after the music stops is Sleep when done.

## Requirements

- **FR-001** Each source has a switch, off by default. The switches are preferences, not configuration.
- **FR-002** While a switch is on and an Auto session runs, playback of that source holds the session.
- **FR-003** The outputs are read at most every 5 seconds, and only while a switch is on.
- **FR-004** The Dashboard names the source, for example "Music is playing in Spotify." (not verified live)
- **FR-005** On macOS older than 14.2 nothing is detected. The rest of the app works as before.

## Verification

- Unit tests: `MusicPlaybackTests` (4 tests). The full suite passes: 358 tests in 69 suites.
- Release build: passes.
- Live, Brave: its helper `com.brave.Browser.helper` reports running output while the test page plays, and the output stops
  about 9 seconds after Pause.
- Live, QA copy with Brave: the Auto session was `protected` while the tone played, and CamLid's power assertion was present.
  The session entered `completionGrace` 18 seconds after Pause and returned to `ready` 121 seconds later, which is Sleep when
  done. With Brave paused, the session stayed `ready`, so the hold comes from the music.
- Not verified live: Spotify, Apple Music, other Chromium browsers, and the Dashboard text.

## Known limits

- Browsers other than Chromium are not detected.
- A program that keeps its audio output open while paused holds the session until it closes the output. Brave closes it
  within about 9 seconds. Spotify and Apple Music were not measured.

## Out of scope

Safari, Firefox, other music apps, and controlling playback.
