---
name: camlid
description: Keep a Mac awake from the command line with the CamLid app. Use when a long command (build, test, export, download) must not be interrupted by sleep, when asked to keep the Mac awake, or when asked why the Mac is awake.
---

# CamLid: keep the Mac awake

CamLid is a macOS menu bar app. Control it only with its `camlid` command. Do not use MCP, do not edit CamLid files, and do not change its settings unless the user asks.

The command is `/Applications/CamLid.app/Contents/Helpers/camlid`. Use this full path if `camlid` is not on PATH.

## Start with the catalog

    camlid commands

This prints every command with its usage, flags, reply fields, refusal reasons and the exit codes. Read it before you use a command you have not used in this session. Every reply is JSON with `schemaVersion` and `command`.

## Reading a reply

- A write carries `accepted`. `true` means it took effect. `changed` says whether anything changed. `false` means the setting or session already was what you asked for, so repeating the call is safe.
- A refusal has `accepted: false`, a `reason`, `retryable` and a `hint`. Act on the hint. Retry only when `retryable` is true, and only after the change the hint names. Do not retry in a loop.
- Exit codes: `0` done · `2` the call is wrong, so fix it · `3` the Mac or the app refuses now, so read `reason` · `4` CamLid or its helper cannot be reached; ask the user to open CamLid, and do not launch it yourself · `5` recovery is needed first.

## Units

Write durations with a unit: `45m`, `2h` or `infinite`. A bare number such as `60` is refused, so it is never read as seconds. A Timed session runs `infinite` or whole minutes from 5 to 480. An Auto session's sleep delay is `0m` to `30m`.

## Keep one command awake (preferred)

    camlid run -- <command> [arguments]

- The Mac stays awake while the command runs, and the exit code is the command's own.
- `run` uses an Auto session. When the command ends, the Mac may stay awake a little longer while agents still work, then it sleeps as usual.
- If CamLid is not running, the exit code is 4 and the command does not run.

Example: `camlid run -- make test`

## Keep the Mac awake for a session (only when asked)

    camlid start                                    # Auto
    camlid start --mode timed --duration 45m
    camlid start --mode timed --duration 45m --replace
    camlid session duration 2h                      # change a running Timed session's timer
    camlid session sleep-delay 5m                   # change a running Auto session's delay
    camlid stop

- `start` with no flags asks for Auto. Its reply's `outcome` says what happened: `started`, `alreadyRunning` (nothing changed), `timerChanged` or `replaced`. `replacedSessionPseudonym` names the session that ended.
- A session of another mode, or with another timer, is refused with `sessionAlreadyActive`. Add `--replace` only when the user asked for that switch: it ends the running session, or changes its timer, and starts the new one.
- `--save-mode` also saves the mode as the user's next default. Use it only when the user asks for that.
- `--closed-lid` needs the user's closed-lid setting on and a permitted helper. Otherwise it is refused with `closedLidOff` or `closedLidNotPermitted`. Do not change that setting yourself.
- Stop only a session you started. Never stop a session the user started unless they ask.

## Read the state

    camlid status --json
    camlid diagnose --json
    camlid doctor --json

`status` shows `effectiveState`, `activeSessionMode`, the `session` and the settings `revision`. `powerActuation: true` is the sign that the Mac's hold is verified. `accepted: true` alone does not mean the Mac is protected. Use `diagnose` to explain why the Mac is awake, and `doctor` for permissions and the closed-lid helper.

## Settings (only when asked)

    camlid config get                          # the saved values and their revision
    camlid config set <key> <value>            # one setting, for example runCapMinutes 120
    camlid config set <key> <value> --expectedRevision N

Read the revision first and pass it with a write. A change made elsewhere then refuses with `revisionConflict` instead of being overwritten.

## Ask the user first

These need the user, not you:

- `camlid helper install`, `helper uninstall` and `helper trust` need an administrator password.
- `camlid closed-lid acknowledge-untested`: the user decides this, after reading the warning.
- `camlid update install`, `camlid quit` and `camlid logs delete`.

Closed-lid protection depends on the user's settings and on the helper, so do not assume it works. Check `camlid doctor --json`, and `camlid helper status --json`. Only `status` = `installed` means the helper is ready.

## Rules

- If you started a session, run `camlid stop` when your work is done.
- Do not change closed-lid mode or other settings the user did not ask you to change.
- Do not write or delete the agent skill file yourself. `camlid skill status` shows whether it is installed.
