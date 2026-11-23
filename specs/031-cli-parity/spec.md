# Feature Specification: CLI parity for every interface function (v0.3)

**Status:** Released in 0.3.0 beta on 2026-11-23. Proposed on 2026-11-20 after an audit of the v0.3 interface against the `camlid` CLI. Owner request: "Kiểm tra xem tất cả các chức năng ở giao diện đều có thể làm được với CLI chưa. Nếu chưa, thêm spec vào cho v0.3 hoàn thiện toàn bộ chức năng cho CLI". Nothing is implemented. Decisions D1–D7 are for the owner to confirm.

## Goal

Every function a person can use in CamLid's menus and windows can also be done with `camlid`, with the same effect, the same refusals and the same history record, and with a JSON result. Everything a window shows can also be read with `camlid`. Where a shell cannot do a step honestly (a macOS permission prompt), the CLI says so and names the step.

## Before this change (audit read in the code, 2026-11-20)

The CLI today (`Packages/CamLidCore/Sources/CamLidCLI/Commands.swift`; app-backed commands in `runWithRealIO`):

- Session: `start --mode auto|timed|manual [--duration …] [--closed-lid]`, `stop`, `sleep`.
- Read: `status`, `diagnose`, `doctor`, `agents list`, `logs export --output`.
- Settings: `config get`, `config validate --file`, `config set --file [--dry-run] [--expectedRevision]`. The file takes 19 keys.
- Other: `watch list|add|remove`, `helper status|install|uninstall|trust` (with `--replace-pins`), `recover --owned-only`, `quit`, `simulate`.
- Refused by design: `event`, `bridge`, `run`.

Findings that shape the gaps:

1. `start` is refused while a session runs (`sessionAlreadyActive`, exit 3). The Dashboard changes the running session's Timed duration and sleep delay. It does not switch a running session's mode: clicking the other mode while a session runs saves it as the next session mode and leaves the running session unchanged (`startPreviewSession` returns when a session exists). No notice says so.
2. A Dashboard mode button saves the mode as the next session mode (`ConfigPatch.mode`) and starts a session when none runs. `start` does not save the mode.
3. `status` has no app version, no language, no music sources, no audio-hold state, no skill state, no Welcome state and no automatic-update setting. It has `updates` (phase, reason, version, session and recovery flags) and `permissions.notifications`.
4. `agents list` reaches the app, which answers with the status object (it contains `agentDetection` and `tasks`). It does not return the list shape of contract v1 ([003 contracts/cli.md](../003-native-foundation/contracts/cli.md)).
5. Several settings live in preferences, not in the configuration, so the CLI cannot read or set them: language (`CamLidLanguage`), music sources, the general audio hold (`CamLidAnyAudioHold`), the untested-Mac acknowledgement (`CamLidUntestedClosedLidAcknowledgement`), the Welcome flag, the daily update check and the agent skill path.
6. `watch` adds and removes programs but cannot turn one on or off (`LifetimeRule.enabled` exists).
7. A bare `--duration` number is seconds: `--duration 60` starts a 60-second session. The window speaks minutes, and `60m` is the minute form.

## Audit: every interface function

Legend: ✔ the CLI does it today. ◐ partly, with the reason. ✗ no CLI route. The gap column names the requirement below.

### Menu bar and shortcut

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | Start an Auto session | `start --mode auto` | |
| ✔ | Stop the session | `stop` | |
| ✔ | Global shortcut ⌃⌥⌘K starts or stops Auto | `start --mode auto` or `stop`; `status.shortcut` | |
| ✔ | Why is my Mac awake? | `diagnose --json` | |
| ✔ | Quit CamLid | `quit` | |
| ✔ | Check for Updates… | `update check` | |
| ✔ | About CamLid: version and build | `version` | |
| ✔ | Open a window (Dashboard, Settings, Activity, Updates, Diagnostics, Welcome, About) | `open <window>` | |

### Dashboard

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | Start Auto or Timed, with a duration | `start --mode timed --duration 60m` | |
| ✔ | Infinite Timed | `start --mode timed --duration infinite` | |
| ✔ | Click the active mode again to stop | `stop` | |
| ✔ | Mode button also saves the mode as the next session mode | `start --mode timed --duration 60m --save-mode` | |
| ✔ | Click the other mode while a session runs | `start --mode timed --duration 60m --replace` (the running session switches; D4) | |
| ✔ | Change the Timed duration of the running session | `session duration <45m|2h|infinite>` | |
| ✔ | Change "Sleep when done" of the running Auto session | `session sleep-delay <0m..30m>` | |
| ✔ | Choose Agents… (opens Settings › Agents) | `open settings.agents`; `agents enable` and `agents disable` for each agent | |
| ✔ | Activity button | `open activity`; `logs list` | |
| ✔ | Turn on keep-awake with the lid closed | `config set --file` (`closedLidOptIn`) | |
| ✔ | Install, reinstall or remove the helper | `sudo camlid helper install`, `sudo camlid helper install --replace-pins`, `sudo camlid helper uninstall` | |
| ✔ | Update notice (opens Updates) | `update status`; `open updates` | |
| ✔ | Metrics, status, reason and banner | `status` (`health`, `effectiveState`, `reasonCodes`) | |
| ✔ | Agent badges (working and waiting) | `agents list` | |
| ✔ | Music badges (playing now) | `music list` | |

### Settings › General

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | Default Timed duration | `config set --file` (`timerMinutes`) | |
| ✔ | Default Sleep when done | `config set --file` (`completionDelayMinutes`) | |
| ✔ | Let the display sleep during sessions | `config set --file` (`allowDisplaySleep`) | |
| ✔ | Language: System, English, Tiếng Việt | `language get`; `language set <system|english|vietnamese>` | |
| ✔ | Launch at login | `config set --file` (`launchAtLogin`) applies the login item | |
| ✔ | Apply startup preference | `login apply` | |
| ✔ | Notification categories | `config set --file` (`notificationCategories`) | |
| ✔ | Allow Notifications… (macOS prompt) | `notifications request` | |
| ✔ | Check for new releases once a day | `update auto <on|off>` | |
| ✔ | Let AI agents use CamLid (writes the skill file) | `skill status`; `skill install`; `skill remove` | |

### Settings › Agents

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | Per-agent "may delay sleep" toggles | `agents enable <provider>`; `agents disable <provider>` | |
| ✔ | Enable All, Disable All | `agents enable --all`; `agents disable --all` | |
| ✔ | Music sources: Chromium, Spotify, Apple Music, Safari | `music set <source> <on|off>` | |
| ✔ | Any audio hold (spec 029) | `audio-hold <on|off>` | |
| ✔ | Watched programs: list, add (path or bundle ID), remove | `watch list`, `watch add`, `watch remove` | |
| ✔ | Watched program: turn on or off | `watch enable <id>`; `watch disable <id>` | |

### Settings › Closed Lid

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | Keep awake with the lid closed | `config set --file` (`closedLidOptIn`) | |
| ✔ | Closed-lid mode | `config set --file` (`powerMode`) | |
| ✔ | Allow on this untested Mac | `closed-lid acknowledge-untested --confirm`; `--revoke` | |
| ✔ | Allow on battery | `config set --file` (`chargingOnly`, `batteryModeAllowed`) | |
| ✔ | Stop below battery level, battery time limit, start on battery at or above | `config set --file` (`batteryFloorPercent`, `batteryCapMinutes`, `batteryEntryPercent`) | |
| ✔ | Session time limit | `config set --file` (`runCapMinutes`) | |
| ✔ | Retain waiting sessions | `config set --file` (`waitRetentionMinutes`) | |
| ✔ | Stop if CPU stays busy | `config set --file` (`cpuStopEnabled`) | |
| ✔ | Changed elsewhere: Use current, Apply my value | `config get`; `config set --file --expectedRevision` | |

### Activity window

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | List events; search; filter by type and reason | `logs list --query <text> --category <c> --reason <code>` | |
| ✔ | Show or hide routine updates | `logs list --include-routine` | |
| ✔ | Export redacted | `logs export --output` | |
| ✔ | Delete one session's history; delete all; the deletion receipt | `logs delete --session <sessionPseudonym> --confirm`; `logs delete --all --confirm` | |

### Updates window

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | Read update state: phase, reason, version | `status.updates` | |
| ✔ | Check for updates | `update check` | |
| ✔ | Update to a version: download, check, replace, restart | `update install` | |
| ✔ | Stop Session and Install | `update install --stop-session` | |
| ✔ | Open Releases | `open releases` | |

### Sleep diagnostics window

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | Show what keeps the Mac awake | `diagnose --json` | |
| ✔ | Copy diagnostics | the same facts as `diagnose --json` | |
| ✔ | Refresh | run `diagnose` again | |

### Welcome (onboarding)

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | Detected agents | `agents list` | |
| ✔ | Install the helper | `sudo camlid helper install` | |
| ✔ | Allow notifications | `notifications request` | |
| ✔ | Finish (mark Welcome done) | `welcome complete` | |

### About

| CLI | Function | Today's route | Gap |
|---|---|---|---|
| ✔ | Version, build and copyright | `version` | |

**Totals:** 65 functions. 65 have a CLI route (✔), 0 have a partial route (◐), 0 have none (✗).

## Requirements

### Gaps

- **G1 Live session controls.** Add `camlid session duration <minutes|infinite>` and `camlid session sleep-delay <minutes>`. They change only the running session, as the Dashboard does, and are refused when no matching session runs. Whether a running session can switch mode is D4, not a parity gap. If D4 is accepted, `start --replace` ends the running session and starts the new one in one revisioned call, with the same safety checks as `start`. Without it, `start` keeps refusing with `sessionAlreadyActive`.
- **G2 Activity history.** Add `camlid logs list` with `--limit`, `--category`, `--reason`, `--query`, `--include-routine` and a cursor. Add `camlid logs delete --session <id>` and `camlid logs delete --all`. Both require `--confirm` and print the `DeletionReceipt` the window shows. `logs export` stays as it is.
- **G3 Agents.** `camlid agents list --json` returns the contract v1 shape: each provider with its enrolment, observed state, confidence, freshness and working, waiting and process counts. It stops returning the status object. Add `camlid agents enable <provider>`, `camlid agents disable <provider>`, and `--all` for both. Each changes one entry of `adapterEnrollment` and keeps the revision check.
- **G4 Music and audio holds.** Add `camlid music list`, `camlid music set <chromium|spotify|apple-music|safari> on|off`, and `camlid audio-hold on|off` for the general hold (spec 029). Expose the sources and the hold in `status` (G15).
- **G5 Watched programs.** Add `camlid watch enable <id>` and `camlid watch disable <id>`. `watch list` returns each rule as stored, with its id and `enabled` flag.
- **G6 Updates.** Add `camlid update status`, `camlid update check`, `camlid update install [--stop-session]`, and `camlid update auto on|off` (the daily check). `install` is refused while a session runs unless `--stop-session` is given, which matches the window's "Stop Session and Install". A QA copy's CLI refuses `install`.
- **G7 Language.** Add `camlid language get` and `camlid language set system|english|vietnamese`. The running app changes at once.
- **G8 Agent skill.** Add `camlid skill status`, `camlid skill install` and `camlid skill remove`. They use the same installer as the Settings toggle and write only `~/.agents/skills/camlid/SKILL.md`.
- **G9 Untested Mac.** Add `camlid closed-lid acknowledge-untested --confirm` and `--revoke`. Before it records anything, the command prints the same warning text as the window.
- **G10 Notifications.** Add `camlid notifications request`. The app shows the macOS prompt, and the CLI reports the result or `waitingForMacOSApproval`. `status.permissions.notifications` remains the read.
- **G11 Welcome.** Add `camlid welcome status` and `camlid welcome complete`, which set the same flag as Finish.
- **G12 Version.** Add `camlid version --json`, with the CLI build, the app version and build, and the helper version. `status` also carries the app version (G15).
- **G13 Windows.** Add `camlid open <dashboard|settings|settings.general|settings.agents|settings.closed-lid|activity|updates|diagnostics|welcome|about>`. Included only if D1 is accepted.
- **G14 Login item.** Add `camlid login apply`, the same action as "Apply startup preference", which runs whether or not the value changed.
- **G15 Status fields.** `camlid status --json` gains `version`, `language`, `music` (each source, enrolled and playing now), `audioHold`, `updates.automaticChecks`, `skill` (installed path or none) and `welcome` (done or not). Existing keys stay. `schemaVersion` stays 1.
- **G16 Duration units.** A bare number in `--duration` is refused with `durationUnitRequired` (exit 2), so that `60` cannot be read as seconds. The minute form (`60m`) and the hour form (`1h`) are unchanged. See D7.

### Shared rules

- **FR-001** Every new write goes through the app over the control socket, so it uses the same revision checks, refusals and history records as the window. The CLI never writes preference keys directly.
- **FR-002** A QA copy's CLI keeps all reads and refuses every write that changes the shared helper or the installed app. That is already true for `helper`, and it extends to `update install` and `skill install`.
- **FR-003** Nothing is deleted, acknowledged, installed or enabled without an explicit flag (`--confirm`, `--stop-session`). Reads never change state.
- **FR-004** Each new command returns the v1 envelope (`schemaVersion`, `command`, `accepted`, `reason`, `reasonCodes`) and uses the v1 exit codes: 0 ok, 2 input invalid, 3 policy or capability denied, 4 app or helper unavailable, 5 recovery needed. Each command is listed in [contracts/cli-v0.3.md](contracts/cli-v0.3.md).
- **FR-005** The agent skill file that spec 022 installs (`.agents/skills/camlid/SKILL.md`) lists the new commands, and the app's copy is regenerated with it.

## Success criteria

- **SC-001** A parity test lists every row of the audit with its CLI route and fails if a route is missing from the CLI's dispatch table.
- **SC-002** Each ✗ and ◐ row has tests for its command: the accepted case and each refusal named in the contract.
- **SC-003** For each window action and its CLI command, run in the same state on the QA copy, the effect and the history record are the same.
- **SC-004** `camlid status --json` includes every field listed in G15.
- **SC-005** `--duration 60` is refused, and `--duration 60m` starts a 60-minute session. Test.

## Decisions (accepted: the owner asked for every recommendation, 2026-11-20)

- **D1. Windows (G13).** Recommended: include `camlid open`. It is cheap, and then every entry point in the app has a CLI route. Alternative: leave it out and call window navigation out of scope.
- **D2. Where the preferences live.** Recommended: keep language, music, audio hold, untested acknowledgement, Welcome flag, update check and skill path in preferences, and expose them over the control socket. That changes no schema and keeps the app as the only writer. Alternative: move them into the configuration, which adds a schema change and a revision check for each.
- **D3. Saving the mode.** The Dashboard saves the mode as the next session mode, and `start` does not. Recommended: keep `start` as an explicit session and add `start --save-mode`, so the Dashboard's behaviour is one flag away.
- **D4. Mode switch while a session runs.** Today the window saves the other mode as the next one and leaves the session alone, with no notice (finding 1). Recommended: switch the running session, since the buttons read Start: add `start --replace`, with the same safety checks as `start`. Alternative: keep saving only, and show a notice that the running session keeps its mode.
- **D5. Installing an update from the shell.** Recommended: refuse with a session running unless `--stop-session` is given, as the window asks first.
- **D6. Shorthand for settings.** Recommended: add `camlid config set <key> <value>` for the 19 keys, mapped to the same patch as `--file`, as a convenience. The file form stays.
- **D7. Duration units (G16).** Recommended: refuse a bare number. Alternative: keep seconds and document it. Existing scripts that pass a bare number would then fail loudly instead of starting a session of the wrong length.

## Out of scope

- The macOS permission prompts themselves. The CLI can ask for one and report the result; the app shows the prompt.
- File choosers. The CLI takes explicit paths (`watch add --executable` or `--bundle-id`).
- The reverse gap: Orca metadata consent is in the configuration and the CLI (`config set --file`), but no Settings control shows it. Adding a control is a separate choice.
- Opening external pages (Releases on GitHub, System Settings). The CLI can print the URL (G6) but does not open a browser.

## Related

- Contract: [contracts/cli-v0.3.md](contracts/cli-v0.3.md)
- Tasks: [tasks.md](tasks.md)
- Contract v1: [003 contracts/cli.md](../003-native-foundation/contracts/cli.md)
- Agent skill: [022 agent skill](../022-agent-skill/spec.md)
- Settings and language: [028 Vietnamese interface](../028-vietnamese-ui/spec.md), [030 About panel](../030-about-panel/spec.md)
