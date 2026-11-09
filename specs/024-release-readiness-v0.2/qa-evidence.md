# Live QA evidence for v0.2 (2026-11-09)

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
