# QA record: app and CLI from the same start (T073)

**Feature:** [spec 031](spec.md) · **Task:** T073 · **Checked:** 2026-11-20, on the test fixtures, which are QA copies.

## What was run

Every row of the audit that was ✗ or ◐ (33 rows), plus the Dashboard switch row whose route changed with D4, was checked two ways from the same start:

- **App:** the function the window calls (`changeTimerDuration`, `setLanguage`, `activateDashboardMode`, `setUntestedAcknowledgement`, and so on), run on a QA-copy coordinator.
- **CLI:** `camlid` through `Commands.runWithRealIO` over the control socket of a second QA-copy coordinator.

The QA copies use their own temporary roots, in-memory preferences and a fake Mac identity. They do not touch the owner's app, socket, helper, login item, notification centre, network or skill file.

Automated: `ParityQATests.theAppAndTheCLIReachTheSameStateFromTheSameStart` (12 rows). Covered by the other agent suites: `AgentOperationsTests`, `AgentWritesTests`, `AgentRoutingTests`. Full run: 498 tests, 0 failures.

**Not possible here:** looking at a window, clicking a control, a macOS prompt, a login-item registration, a real update download, and the browser opening the releases page. Those rows are listed under "by hand" below. This environment has no GUI session on a signed app, and running them would touch the owner's Mac or GitHub.

## Results

| Row (audit) | CLI route | Result | By hand (QA copy or the signed app) |
|---|---|---|---|
| Check for Updates… | `update check` | QA copy refuses (`qaCopy`, exit 3) | Run the check on a Mac with a release; compare the window and `update status` |
| About CamLid: version and build | `version` | Read tested; `copyright` added | Open About; compare the version, build and copyright |
| Open a window | `open <window>` | Unknown window refused; no window opened here | Open each of the ten windows with `camlid open` and check it shows |
| Mode button also saves the mode (D3) | `start --save-mode` | **Compared, same:** saved mode, session mode and timer (2700 s) match | — |
| Click the other mode while a session runs (D4) | `start --replace` | **Compared, same session:** timed, 2700 s. The window also saves the mode; the CLI saves only with `--save-mode`, as D3 says | Click the other mode in the window and check it shows the new session |
| Change the Timed duration of the running session | `session duration` | **Compared, same:** 2700 s and timed | Change the picker in the window; check the countdown |
| Change "Sleep when done" of the running Auto session | `session sleep-delay` | Covered: `sessionSleepDelayNeedsAnAutoSession` (9 min changes; the same value changes nothing; a Timed session is refused). Not compared in the harness: the delay has no field in `status` | Change the slider in the window after `session sleep-delay` |
| Choose Agents… (opens Settings › Agents) | `open settings.agents`; `agents enable`/`disable` | Enrolment **compared, same** (see the two agent rows). The window was not opened | Open the pane |
| Activity button | `open activity`; `logs list` | `logs list` covered by `logsListPagesFiltersAndSearchesLikeTheActivityWindow`. The window was not opened | Open Activity and compare the rows |
| Update notice (opens Updates) | `update status`; `open updates` | Read tested. The window was not opened | Open Updates |
| Agent badges (working and waiting) | `agents list` | Shape tested: `agentsListNamesEachProviderWithItsState` | Compare the badges with `agents list` |
| Music badges (playing now) | `music list` | Read tested | Compare the badges with `music list` |
| Language: System, English, Tiếng Việt | `language get`; `language set` | **Compared, same:** English. The two new Dashboard notices have Vietnamese text in the catalogue | Switch to Tiếng Việt in the window and look at the notices |
| Apply startup preference | `login apply` | QA copy refuses (`loginItemFailed`, exit 4); tested by `aQACopyDoesNotRegisterALoginItem`. Not in the harness: saving `launchAtLogin` on a QA copy triggers the same refusal | Toggle Launch at login on the signed app and check Login Items |
| Allow Notifications… (macOS prompt) | `notifications request` | **Compared, same:** both sides report `unavailable` and the CLI refuses. Decided and undecided permissions are tested with injected answers | Ask on the signed app and confirm the macOS prompt appears |
| Check for new releases once a day | `update auto` | **Compared, same:** on | Toggle in the window; check `update status` |
| Let AI agents use CamLid (writes the skill file) | `skill status`; `skill install`; `skill remove` | CLI refuses on a QA copy (`qaCopy`), tested. **Divergence:** the window's toggle is not guarded on QA copies, so on a QA copy it writes into the copy's own home folder, while the CLI refuses. Recorded for a decision | On the installed app, toggle the window and `camlid skill install`; both must write the same file |
| Per-agent "may delay sleep" toggles | `agents enable`/`disable <provider>` | **Compared, same:** one provider | Toggle an agent in Settings › Agents |
| Enable All, Disable All | `agents enable --all`; `agents disable --all` | **Compared, same:** Enable All. Disable All is implemented; not in the harness | Click Disable All and compare |
| Music sources: Chromium, Spotify, Apple Music, Safari | `music set <source> <on|off>` | **Compared, same:** Chromium. The other sources use the same code path; not each compared | Toggle each source in Settings › Agents |
| Any audio hold (spec 029) | `audio-hold on|off` | **Compared, same:** on. Toggle and refusal tested (`theGeneralAudioHoldChangesOnlyWhenItDiffers`) | Toggle in Settings › Agents |
| Watched program: turn on or off | `watch enable`/`disable <id>` | Covered over the control socket: `watchedProgramsTurnOnAndOffThroughTheControlChannel` (add; disable; disable again changes nothing; enable; unknown id refused) | Toggle a program in Settings › Agents |
| Allow on this untested Mac | `closed-lid acknowledge-untested --confirm`/`--revoke` | **Compared, same:** acknowledged. Refused without a flag, and refused where the Mac cannot be identified (`macIdentityUnavailable`) | Read the warning in Settings › Closed Lid and confirm it |
| List events; search; filter by type and reason | `logs list --query --category --reason --cursor` | Covered: `logsListPagesFiltersAndSearchesLikeTheActivityWindow` (paging, category, search, invalid cursor). The window's list was not opened | Search in Activity and compare |
| Show or hide routine updates | `logs list --include-routine` | Implemented; not separately tested. Routine updates are hidden by default | Toggle in Activity and compare the counts |
| Delete one session's history; delete all; the deletion receipt | `logs delete --session`/`--all --confirm` | Covered: `logsDeleteRefusesAnUnknownSessionAndClearsTheHistoryOnce` (unknown refused; a second delete changes nothing; receipt present) | Delete from the window and compare the receipt |
| Check for updates | `update check` | QA copy refuses (tested). The GitHub check was not run | As the first row |
| Update to a version: download, check, replace, restart | `update install` | QA copy refuses (tested). The download, replacement and restart were not run. Checksum and writable-folder refusals: `UpdateInstallTests` (existing) | Install a release on a QA copy |
| Stop Session and Install | `update install --stop-session` | QA copy refuses (tested). The session end and restart were not run | As the row above, with a session running |
| Open Releases | `open releases` | Implemented: it opens the same page as the button. Not run, because it would open a browser | Click Open Releases and compare the page |
| Allow notifications (Welcome) | `notifications request` | As Allow Notifications… above | As above |
| Finish (mark Welcome done) | `welcome complete` | **Compared, same:** the Welcome flag is set | — |
| Version, build and copyright | `version` | Read tested, with `copyright` | Compare with About |

## Divergences and decisions

1. **Skill toggle on a QA copy.** The CLI refuses (`qaCopy`) on purpose (T044). The window does not. On a QA copy the window writes into the copy's own home folder, so nothing reaches the owner's file. Decide whether the window should refuse too.
2. **Saved mode on the Dashboard switch (D4).** The window saves the mode as well as switching the session. The CLI switches the session and saves only with `--save-mode` (D3). That is the agreed difference.

## Bugs found while writing this record (fixed)

- `config set` with an unchanged value still wrote the settings and bumped the revision. It now writes nothing and answers `changed: false`.
- `notifications request` reported a change on every call, and could ask macOS where the app cannot ask. It now asks only while the permission is undecided, and reports `unavailable` outside an app bundle.
- `closed-lid acknowledge-untested` reported `acknowledged` from the closed-lid permit, not the stored choice, and silently did nothing without a Mac identity. It now reports the stored choice and refuses with `macIdentityUnavailable`.
- `quit` had a route but no catalogue entry, so its flags and reply fields were undocumented. It has one now.

## Still to do before a release

The rows marked "By hand" above need a pass on a QA copy with a GUI, and on a Mac with a published release for the update rows. This record does not claim they were run.
