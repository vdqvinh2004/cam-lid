# CLI contract v0.3: additions to contract v1

**Extends:** [003 contracts/cli.md](../../003-native-foundation/contracts/cli.md) (contract v1). Nothing in v1 changes, except that `status` gains the additive keys listed under G15. **Used by:** [spec 031](../spec.md).

## Common rules

- Every result is JSON with `schemaVersion: 1` and `command`.
- `accepted` is `true` for a write that took effect and `false` for a refusal. Reads never set it.
- Exit codes as v1: `0` ok · `2` input invalid (including `revisionConflict`, as `config set` already does) · `3` policy or capability denied · `4` app or helper unavailable · `5` recovery needed.
- A write to the configuration takes `--expectedRevision N`. A preference-backed write (D2) returns the new value and no revision.
- Every write is refused while the app is quitting (`applicationTerminating`, exit 3).
- A refusal names its `reason` and carries `retryable` and `hint`. A successful write carries `changed`: `false` means the state already matched, so nothing was written. `camlid commands` lists every command, reason and exit code.
- Flags use `--name value` or `--name=value`, as in v1.

## Session (G1)

### `camlid session duration <minutes|infinite> [--expectedRevision N]`

Changes the running Timed session's duration and restarts its timer, as the Dashboard does. Session-only: the saved default does not change.

- Success: `{accepted: true, changed, command: "sessionDuration", revision, durationSeconds, capApplied}`. `durationSeconds` is 0 for Infinite. When the session already runs that duration, `changed` is false and its countdown is not restarted.
- Refusals: `noTimedSession` (3) · `durationUnitRequired` (2) · `invalidDuration` (2) · `invalidRevision` (2) · `revisionConflict` (2) · `settingsPending` (3) · `appUnavailable` (4) · `applicationTerminating` (3).

### `camlid session sleep-delay <minutes> [--expectedRevision N]`

Changes the running Auto session's delay after work ends (0 to 30 minutes). Session-only.

- Success: `{accepted: true, changed, command: "sessionSleepDelay", revision, sleepDelayMinutes}`.
- Refusals: `noAutoSession` (3) · `durationUnitRequired` (2) · `invalidDuration` (2) · `invalidRevision` (2) · `revisionConflict` (2) · `settingsPending` (3).

### `camlid start [--mode auto|timed] [--duration 45m|2h|infinite]`

Starts a session through the same checks as the Dashboard buttons. No flags means Auto. `manual` is read as `timed`, as the Dashboard shows it.

- Success: `{accepted: true, changed, command: "start", outcome, mode, effectiveState, durationSeconds, capApplied, replacedSessionPseudonym, savedMode, revision, closedLid, closedLidPermit, powerMode, powerActuation, note}`. `outcome` is `started`; `alreadyRunning` (the same mode and timer already run, so nothing changed); `timerChanged` (the running Timed session took another timer); or `replaced`. `powerActuation` is true only when the Mac's hold is verified.
- Refusals: `sessionAlreadyActive` (3, another session runs and `--replace` is not given) · `durationRequired` (2) · `durationNotApplicable` (2) · `durationUnitRequired` (2) · `invalidDuration` (2) · `invalidMode` (2) · `closedLidOff` (3) · `closedLidNotPermitted` (3) · `batteryEntryLow` (3) · `batteryUnknown` (3) · `notCharging` (3) · `powerUnknown` (3) · `notStarted` (3) · `settingsPending` (3) · `applicationTerminating` (3) · `recoveryRequired` (5) · `revisionConflict` (2) · `commitUnconfirmed` (5) · `storageUnavailable` (4) · `appUnavailable` (4).
- A refused start changes nothing, and `--save-mode` saves only after the start passes its checks.

### `camlid start … --replace` (D4, accepted)

Ends a running session of another mode, or changes a running Timed session's timer, and starts the new one in one call. Same flags and checks as `start`.

- Success: as `start`, with `outcome` `replaced` (or `timerChanged`) and `replacedSessionPseudonym` (or `null`): the pseudonym `logs list` shows for the session that ended. The pseudonym replaces the raw session ID, so a reply never carries it.
- A switch is checked before the running session ends, so a refused switch leaves that session as it was.

### `camlid start … --save-mode` (D3)

Saves `--mode` as the next session mode (`mode` in the configuration), then starts, as the Dashboard does. Without the flag, `start` saves nothing.

- Refusals: as `config set --file` for `mode` (`revisionConflict`, exit 2).

## Activity (G2)

### `camlid logs list [--limit N] [--cursor X] [--category C] [--reason R] [--query Q] [--include-routine]`

- Success: `{command: "logsList", records: [...], nextCursor: string | null, hiddenRoutineCount: N}`. Each record has the redacted shape of `logs export`: no prompts, transcripts, command output or task identifiers.
- Refusals: `invalidFilter` (2) · `invalidCursor` (2) · `storageUnavailable` (4).

### `camlid logs delete --session <id> --confirm` and `camlid logs delete --all --confirm`

- Success: `{accepted: true, command: "logsDelete", receipt: {...}}`, where `receipt` has the fields of `DeletionReceipt` (ActivityStore).
- Refusals: `confirmationRequired` (2) · `unknownSession` (2) · `storageUnavailable` (4).

## Agents (G3)

### `camlid agents list [--json]`

- Success: `{command: "agentsList", agents: [{provider, enabled, observedState, confidence, evidenceAgeSeconds, workingCount, waitingCount, processCount}]}`. Music sources are under `music` (G4), not here.
- This replaces the status object that `agents list` returns today.

### `camlid agents enable <provider>|--all` and `camlid agents disable <provider>|--all`

Changes one provider's enrolment, or all of them. The other entries are kept.

- Success: `{accepted: true, command: "agentsEnable" | "agentsDisable", enrolled: [providers], revision}`.
- Refusals: `unknownProvider` (2) · `revisionConflict` (2) · `recoveryRequired` (5).

## Music and audio (G4)

### `camlid music list`

- Success: `{command: "musicList", sources: [{id, enabled, playingNow}]}`, with ids `chromium`, `spotify`, `apple-music` and `safari`.

### `camlid music set <id> on|off`

- Success: `{accepted: true, command: "musicSet", id, enabled}`. Refusal: `unknownSource` (2).

### `camlid audio-hold on|off`

- Success: `{accepted: true, changed, command: "audioHold", enabled, holding}`. Spec 029 defines what the hold does.

## Watched programs (G5)

### `camlid watch enable <id>` and `camlid watch disable <id>`

- Success: `{accepted: true, command: "watchEnable" | "watchDisable", id, enabled, revision}`.
- Refusals: `invalidRuleID` (2) · `ruleNotFound` (2) · `revisionConflict` (2).

## Updates (G6, D5)

### `camlid update status [--json]`

- Success: `{command: "updateStatus", phase, reason, version, sessionActive, recoveryRequired, automaticChecks, installationAvailable}`.

### `camlid update check`

Asks GitHub once. Downloads nothing.

- Success: `{accepted: true, command: "updateCheck", phase, reason, version}`.
- Refusals: `qaCopy` (3) · `recoveryRequired` (5). A check that fails is not a refusal: `phase` and `reason` in `update status` say what happened, for example `networkUnavailable`.

### `camlid update install [--stop-session]`

Downloads, checks, replaces the app and restarts, as the window does.

- Success: `{accepted: true, command: "updateInstall", phase}`. The CLI returns once the install has started.
- Refusals: `sessionActive` (3, unless `--stop-session`) · `updateNotReady` (3, its `detail` names the update's reason) · `recoveryRequired` (5) · `qaCopy` (3).

### `camlid update auto on|off`

Sets the daily check (spec 021).

- Success: `{accepted: true, command: "updateAuto", automaticChecks}`.

## Language (G7)

### `camlid language get`

- Success: `{command: "languageGet", language, resolved}`, where `language` is `system`, `english` or `vietnamese`, and `resolved` is `en` or `vi`.

### `camlid language set system|english|vietnamese`

- Success: `{accepted: true, command: "languageSet", language}`. Refusal: `invalidLanguage` (2).

## Agent skill (G8)

### `camlid skill status`

- Success: `{command: "skillStatus", installed, path}`, where `path` is `~/.agents/skills/camlid/SKILL.md`.

### `camlid skill install` and `camlid skill remove`

- Success: `{accepted: true, command: "skillInstall" | "skillRemove", installed}`.
- Refusals: `skillConflict` (2) · `skillModified` (2) · `skillWriteFailed` (4) · `qaCopy` (3).

## Untested Mac (G9)

### `camlid closed-lid acknowledge-untested --confirm` and `camlid closed-lid acknowledge-untested --revoke`

Without `--confirm`, the command prints the warning text the window shows and exits 2 with `confirmationRequired`. It records nothing in that case.

- Success: `{accepted: true, changed, command: "closedLidAcknowledge", acknowledged, closedLidPermit}`. `acknowledged` is the stored choice.
- Refusal: `macIdentityUnavailable` (3) when this Mac's model and macOS build cannot be read, so nothing is recorded.

## Notifications (G10)

### `camlid notifications request`

- Success: `{accepted: true, changed, command: "notificationsRequest", permission}`, where `permission` is the app's notification state, `requesting` right after the request.
- Refusal: `notificationsUnavailable` (3).

## Welcome (G11)

### `camlid welcome status` and `camlid welcome complete`

- Status: `{command: "welcomeStatus", done}`.
- Complete: `{accepted: true, command: "welcomeComplete", done: true}`. Sets the same flag as the Finish button.

## Version (G12)

### `camlid version [--json]`

- Success: `{command: "version", cli: {version, build}, app: {version, build, copyright} | null, helper: {bundledVersion, state}}`. `cli` is always present, so the command has no exit 4. `app` is `null` when the app cannot answer. `helper.state` says what the helper is doing.

## Windows (G13, D1 accepted)

### `camlid open <window>`

Windows: `dashboard`, `settings`, `settings.general`, `settings.agents`, `settings.closed-lid`, `activity`, `updates`, `diagnostics`, `welcome`, `about`, `releases` (the project's releases page, in the browser).

- Success: `{accepted: true, command: "open", window}`.
- Refusals: `unknownWindow` (2) · `appUnavailable` (4).

## Login item (G14)

### `camlid login apply`

Applies the saved `launchAtLogin`, even when the value has not changed.

- Success: `{accepted: true, changed, command: "loginApply", launchAtLogin, state}`, where `state` is the login item's state.
- Refusal: `loginItemFailed` (4).

## Status (G15)

`camlid status --json` adds these keys. The existing keys do not change.

| Key | Shape |
|---|---|
| `version` | `{version, build}` |
| `language` | `{language, resolved}` |
| `music` | `[{id, enabled, playingNow}]` |
| `audioHold` | `{enabled, holding}` |
| `updates.automaticChecks` | boolean |
| `skill` | `{installed, path}` |
| `welcome` | `{done}` |

## Duration units (G16, D7)

`--duration` accepts `<n>h`, `<n>m` and, for Timed, `infinite`. A bare number is refused with `durationUnitRequired` (exit 2), and a unit other than `h` or `m` with `invalidDuration` (exit 2). D7 is accepted.

## Shorthand (D6, accepted)

`camlid config set <key> <value> [--dry-run] [--expectedRevision N]` maps to the same patch as `--file`, for the 19 keys. Each value is read as JSON (`true`, `60`, `"timed"`). A string that is not valid JSON is taken as text. A value that changes nothing answers `changed: false`, writes nothing and keeps the revision.
