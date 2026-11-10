# Live QA evidence for v0.2 (2026-11-09 and 2026-11-10)

What was checked on a real Mac, how, and what was not. The gate is in [tasks.md](tasks.md); the risks are in [spec.md](spec.md).

## Setup

- Release candidate: `dist/CamLid-0.2.0-macos-arm64.zip`. SHA-256 verified. The `SKILL.md` in its bundle equals `.agents/skills/camlid/SKILL.md`.
- QA instance: the same source, built in Release with `CFBundleIdentifier` set to `com.camlid.qa.rc` and re-signed ad hoc. It used an isolated state directory under `~/Library/Caches` (the control socket path must stay under 104 bytes). The helper pins the release certificate, so this build reports "Needs setup", and closed-lid was not exercised.
- The installed app (`com.camlid.CamLid`, revision 231) was read only. No action was sent to it.
- GUI: cua-driver, background delivery only. CLI: the release binary, with `CAMLID_CONTROL_DIRECTORY` pointing at the QA control socket.
- Browser: Brave, driven by Playwright CLI, on a local page that loops a quiet tone.

## Results

| Check | Result |
| --- | --- |
| Display option on (default): a timed session holds the system only | Pass. `pmset` shows `PreventUserIdleSystemSleep` only. |
| Display option off: a timed session also holds the display | Pass. `PreventUserIdleDisplaySleep` named "CamLid keeps the display on while a session runs". Both released on stop; no CamLid assertion afterwards. |
| Copy diagnostics | Pass. The button was pressed; `pbpaste` shows the report (version, mode, protection, restoration, process names, blocker types, coverage, error keys). |
| Chromium audio: Brave's audio assertion | Pass for the assertion. `NoIdleSleepAssertion` named "Playing audio" appears while the tone plays and is gone after pause. |
| Chromium audio: CamLid's own hold decision | Not isolated. Orca had two working tasks, which keep Auto awake on their own. |
| Chromium audio: other browsers | Not run. |
| Chromium audio switch | Shown in the Agents pane. Its value was set in the QA preferences only. |
| Skill button, on 2026-11-09 (location: home folder) | Pass in the QA copy. On wrote `<QA folder>/home/.agents/skills/camlid/SKILL.md`, equal to the repository SKILL.md, and the Settings text showed the path. Off removed the file. The installed home folder was never touched. |
| Skill button: a file CamLid did not write | Pass. Cancel left the file and the switch off. Replace wrote the bundled skill, and Off then removed it. |
| Update switch | On writes `CamLidAutomaticUpdateChecks = 1`; off writes 0. |
| Update: first scheduled request | Not observed; the first request comes on the first hourly tick. A manual check showed "Update check deferred … when agents are no longer active" while Orca had two working tasks, so no request was sent. |
| Skill commands, release CLI | Pass: `status`; `helper status` (installed); `diagnose`; `start --mode timed --duration 2m` refused (`invalidDuration`); `stop` with no session; `run -- /usr/bin/true` exits 0; `run` with CamLid not running exits 4 (`appUnavailable`) and the command does not run. |
| General pane, top section | Checked on screen. The lower sections (AI agents, Updates) are below the fold. Background scrolling did not reach the window, so they were checked in the accessibility tree only. |
| Sleep diagnostics window | Opens from the menu. Copy works (above). |
| Dashboard popover | Not reached: the QA instance's status item was not reachable. |

## Not done, and why

- Light and dark appearance: needs a system appearance change, which also affects the owner's apps.
- VoiceOver walkthrough and keyboard focus order: not run.
- Visual check of the lower Settings sections: needs a foreground scroll, which was not used without the owner's approval.
- Owner items, unchanged: privacy wording (021 T032), closed-lid session (014, 016), launch at login, the Documents or Desktop prompt (gate G17), the agent run (022 SC-001), and the upload and tag (ADR 0004).

## Test-suite hygiene

- Tests that wrote a preference value through `UserDefaults(suiteName:)` left an empty preference plist behind. The daemon wrote the empty domain back a few seconds after `removePersistentDomain`, so deleting the file was not enough. A probe reproduced it: 2 of 8 rounds with a 3-second wait, with and without `CFPreferencesAppSynchronize`.
- Fixed: `AgentSkillInstaller`, `UpdateController` and `AppCoordinator` take a `PreferenceStore`, which `UserDefaults` conforms to. Every test uses `MemoryPreferences` (in `TestPreferences.swift`), so no test writes a preference file. A full run (358 tests in 69 suites) created none, checked by file time after the run.
- The 1,423 older `CamLidTest.*` files, from runs before this change, remain in `~/Library/Preferences`. They were not removed; the owner decides.

## Cleanup

- The QA app and its utility process were quit. No QA process remains.
- The QA state directories and the QA-only preference domains were removed.
- Scratch build copies were unregistered from Launch Services. None is registered now.
- The installed app quit during the skill-location check. The system log and the crash reports show nothing for it, so the cause is not known. It was started again in the background (`open -g`) and reports Ready, revision 231.
- A QA run needs its state folder to exist before launch. Without it the onboarding Finish fails with "Couldn't complete Welcome"; this is a QA setup mistake, not a product path.

## Incident and recovery (2026-11-09 and 2026-11-10)

- At 18:38:41 on 2026-11-09 the installed app recorded `configApplied` and `sessionStarted` in its history. The most likely cause is a QA command-line call without `CAMLID_CONTROL_DIRECTORY`, which reaches the installed app's default control socket. The history does not record which client sent a command, so this is not proven.
- Recovery, approved by the owner: the Auto session was stopped, and `chargingOnly` (true), `batteryModeAllowed` (false) and `mode` (off) were set back to defaults. The restore is recorded at 01:39:55 on 2026-11-10.
- Other `sessionStarted` events on 2026-11-09 (10:19:47, 11:33:50, 11:44:17, 12:03:14, 14:37:15, 16:50:50) are not attributed.
- Fix (commit `5139bc7`): `StateLocations` gives each copy one set of folders. The installed app's tool is the only one that reaches the owner's control socket. A QA copy (marked by `CamLidQAStateDirectory` in its Info.plist) reaches only its own folder, refuses helper install and removal, and registers no login item or global shortcut.

## Checks on 2026-11-10 (QA copy built from `5139bc7`)

- Tool without `CAMLID_CONTROL_DIRECTORY`: answered by the QA copy (`status --json`, exit 0).
- Tool pointed at the owner's folder: refused on the client side (exit 4), nothing sent.
- `helper install` from the QA tool: refused with `qaCopy` (exit 2).
- A configuration change went only to `history/preferences.json` under the QA folder.
- Owner files unchanged: `preferences.json` hash `633d2f96`, helper identity hash `c64cc72f`.
- Skill commands (FR-004): `status --json`, `helper status --json` and `diagnose --json` exit 0. `run -- /usr/bin/true` exits 0 once the QA copy allows battery sessions. Timed start was accepted and `stop` released it. `start --mode auto` and `start --mode timed` were refused with `notCharging` under default settings, as designed. `helper install`, `uninstall` and `trust` were not run; the QA tool refuses them by design.
- Screens (QA copy): the Agents and Closed Lid panes fit. The "CamLid is active" row shows with "Active now" during a QA timed session (023 T013 wording). The two header buttons of the Sleep diagnostics window fit, and the row labels are readable through accessibility.
- General pane: the top sections fit. The window is 608 pt tall, and the lower sections ("Recovery problems", "Updates", "AI agents") sit below the visible edge. The accessibility tree exposes no scroll area, and background scrolling is not delivered for this window, so whether they scroll is not confirmed.
- "Reinstall helper…" pressed in the QA copy: no administrator prompt appeared and the owner's helper was unchanged. No refusal text was visible, so the on-screen refusal message is not confirmed.
- Not run: Spotify and Apple Music playback (needs the owner to play music), login item and global shortcut in the QA copy (not enabled by rule), and a VoiceOver walk-through.

## Music hold timing and Settings layout (2026-11-10)

- Brave, read-only probe with a test page (tone, pause, then a silent `AudioContext` at zero gain). Pause: the "Playing audio" assertion was released about 2 to 3 seconds later, while the output stream stayed open about 10 seconds. The browser hold now needs the assertion, so a silent output stream holds nothing. Apple Music now ends its hold at its playback assertion (`com.apple.Music.playback`) once that assertion has been seen: one live cycle released the hold 2.1 seconds after pause, before the output stream closed 5.2 seconds later. Spotify has no assertion and keeps the output signal with a 5-second bridge (owner decision, 2026-11-10). Four driver-controlled runs showed its output closing 2.6 to 2.7 seconds after pause, with no gap at three manual track changes; in replay the hold ended 5.8 to 6.9 seconds after pause (10-second bridge: 11.0 to 12.0). One of the four runs reopened the output about 20 seconds after pause; a repeat of that run did not, and the cause is unknown. Details: spec 025, Verification.
- Another Brave process was playing audio throughout the probe. It was not identified and was not touched, so the QA copy's end-to-end check could not isolate the test tab.
- Settings › General at a temporary window height of 908 pt (pane height 820): all four groups fit, and a scroll bar appears at the right edge for the last footer line. The pane height was restored to its default of 520 pt. The change is not committed.
- Checked on the QA copy by driver only: the Settings menu opened, and the General and Closed Lid tabs were selected. No setting was changed in that check.
