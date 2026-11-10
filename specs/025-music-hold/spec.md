# Feature Specification: music hold (browsers, Spotify, Apple Music)

**Status:** Implemented for v0.2 (not released). Revised 2026-11-10: a browser needs its playback assertion as well as its
output, and Apple Music ends its hold at its playback assertion once that assertion has been seen on this Mac. Spotify keeps
the output signal alone. The timings were measured live on this Mac with a read-only probe: four Spotify runs, one Apple Music cycle, and
one Brave test. Apple Music and Brave come from a single cycle each, not from a repeated test.

## Goal

An Auto session stays awake while music plays, with the same mechanism as Auto's agent work. Each source is a chip in
Settings › Agents, off by default. When the music stops, the hold ends promptly and Sleep when done applies (2 minutes by
default). The run cap (120 minutes by default) still bounds every Auto session.

## Decisions (owner, 2026-11-09 and 2026-11-10)

1. **Sources:** a browser, Spotify and Apple Music. Each has its own switch, like an agent's detection toggle. Browsers and Apple Music are always listed in Settings › Agents and can be clicked; Spotify is listed when its app is installed on this Mac.
2. **Auto only:** the music hold is a lifetime hold reason (`musicPlayback`). The run cap and the safety stops still apply.
   Timed and Infinite sessions ignore it. The cap stays at its default, 120 minutes (owner, 2026-11-10).
3. **Detection:** CoreAudio lists the processes that run audio output. The app matches their bundle IDs, and a helper matches
   by prefix. Two sources also read a playback assertion, which is released when playback stops:
   - a Chromium browser holds the named "Playing audio" power assertion while its audio is audible;
   - Apple's Music app holds the "com.apple.Music.playback" assertion while it plays. The app uses it once it has been seen on
     this Mac. Until then Music is judged by its output alone, so a Mac without that assertion still gets the output-only hold.

   Spotify holds no assertion, so it is judged by its output alone. All reads need no permission and send nothing to the
   program (ADR 0002: observer only).
4. **Browsers:** Chromium browsers (Chrome, Brave, Edge, Vivaldi, Opera, Arc, Chromium) share one chip and one signal. Safari has its own chip and signal, measured on 2026-11-10 with YouTube. Firefox is not
   detected.
5. **Quiet periods and reads:** while a hold is in force the signals are read every 2 seconds, and every 5 seconds otherwise.
   A source judged by its assertion (a browser, and Music once its assertion has been seen) bridges 3 seconds after its last
   playing read. Spotify, an output-only source, keeps a 5-second bridge: its output had no gap at a track change in three live
   runs with a manual Next (owner, 2026-11-10). Music, before its assertion is seen, is also output-only and keeps the
   10-second bridge, since its track changes have not been measured. The wait after the music stops is Sleep when done.

## Requirements

- **FR-001** Each source has a switch, off by default. The switches are preferences, not configuration.
- **FR-002** While a switch is on and an Auto session runs, playback of that source holds the session.
- **FR-003** The signals are read at most every 2 seconds while a hold is in force, every 5 seconds otherwise, and only while
  a switch is on. The assertions are read only while a browser or Music outputs.
- **FR-004** The Dashboard names the source, for example "Music is playing in Spotify." (not verified live)
- **FR-005** On macOS older than 14.2 nothing is detected. The rest of the app works as before.
- **FR-006** A browser counts as playing only while its output runs and its playback assertion is held. An output stream that
  stays open in silence holds nothing.
- **FR-007** Apple Music counts as playing while its output runs and, once its assertion has been seen on this Mac, while the
  assertion is held. Before that, its output alone counts.

## Verification

- Unit tests: `MusicPlaybackTests` (13 tests). The full suite passes: 288 + 371 + 68 tests in three targets.
- Release build: passes.
- Live, Apple Music, read-only probe (2026-11-10), one play and one pause:
  - The app's playback assertion `com.apple.Music.playback` appeared about 44 seconds before audio output started.
  - Audio output ran for about 148 seconds. The assertion was released at the pause; the output stream closed about 5.2 seconds
    later.
- Live, Spotify, four driver-controlled runs through the Playback menu (2026-11-10), with a read-only probe:
  - Spotify and its helper processes held no power assertion at any time, during playback or after it.
  - Audio output closed 2.6 to 2.7 seconds after the pause in all four runs.
  - Three runs changed track with a manual Next. The output had no gap at any change, sampled every 0.5 seconds, and the window
    title changed about 3 seconds after the press in both runs that read it.
  - One of the four runs (the first) reopened the output about 20 seconds after the pause; the probe was stopped right after, so its length is
    not known. A repeat of that run, with the same sequence and a 60-second watch, did not reopen. Two other runs followed the output for 120 seconds after
    the pause without a reopen. The cause is not known.
- Replay of the recorded probe logs through the new hold (2026-11-10): the Music hold ended 2.1 seconds after its assertion was
  released, before the output stream closed. With the 5-second Spotify bridge, the Spotify hold ended 5.8 to 6.9 seconds after
  the pause in the four runs. The earlier 10-second bridge ended it 11.0 to 12.0 seconds after the pause, on the same four logs.
  Before this revision, Music's hold followed the output, so it would have ended about 15 seconds after the pause (estimated).
- Live, Brave, read-only probe (2026-11-10): a test page played a tone, paused it, then ran a silent `AudioContext` at zero gain.
  - Play: the test process held the "Playing audio" assertion about 0.4 seconds after the click.
  - Pause: the assertion was released about 2 to 3 seconds after pause. The output stream stayed open about 10 seconds after
    pause (a 0.5-second probe).
  - Silent output: the output stream opened about 0.4 seconds after the silent start, and the test process held no
    "Playing audio" assertion during that phase. The stream closed about 0.4 seconds after the context closed.
  - Limit of this test: another Brave process was playing audio throughout, so the QA copy's end-to-end check could not
    isolate the test tab. The per-process measurement is the evidence.
- Before this revision (2026-11-09, QA copy with Brave): the Auto session was `protected` while the tone played, and entered
  `completionGrace` 18 seconds after Pause, because the output stream was still open.
- Live, Safari, YouTube playing (2026-11-10), read-only: the audio came from com.apple.WebKit.GPU, and Safari held "com.apple.WebCore: HTMLMediaElement playback" under its own process name. Safari's pause and muted playback are not yet checked.
- Not verified live: other Chromium browsers, automatic track changes at the end of a track, Apple Music track changes, the
  Dashboard text, and Apple Music on other macOS versions.

## Known limits

- Browsers other than Chromium and Safari are not detected. Firefox is not installed here and was not measured.
- The assertion names are read from this Mac (macOS 26): the Chromium "Playing audio" assertion and Music's
  "com.apple.Music.playback". A macOS version or a browser that names them differently is not detected by its assertion. Music
  then keeps the output-only hold; a browser has no such fallback and is not detected.
- Spotify has only the output signal. Its output closes about 2.7 seconds after pause and had no gap at three manual track changes.
  The 5-second bridge depends on that; automatic track changes at the end of a track were not measured. One of four runs showed the output
  reopening about 20 seconds after pause (cause unknown; not seen in the other three runs). A program that keeps its output open while paused holds
  the session until the run cap.
- Music's assertion is used once it has been seen. If Music plays without it later (for example through AirPlay or a radio stream),
  that playback is judged by its assertion and may end early. This was not checked.
- A Spotify switch that stays on after Spotify is removed has no chip, because Spotify is listed only when installed. It does nothing without the app.

## Out of scope

Safari, Firefox, other music apps, and controlling playback.
