---
name: camlid
description: Keep a Mac awake from the command line with the CamLid app. Use when a long command (build, test, export, download) must not be interrupted by sleep, when asked to keep the Mac awake, or when asked why the Mac is awake.
---

# CamLid: keep the Mac awake

CamLid is a macOS menu bar app. Control it only with its `camlid` command. Do not use MCP, do not edit CamLid files, and do not change its settings.

The command is `/Applications/CamLid.app/Contents/Helpers/camlid`. Use this full path if `camlid` is not on PATH.

## 1. Check first

    camlid status --json

Read `effectiveState` and `activeSessionMode`. If the command fails because CamLid is not running, tell the user to open CamLid. Do not launch it yourself.

## 2. Keep the Mac awake for one command (preferred)

    camlid run -- <command> [arguments]

- The Mac stays awake while the command runs. The exit code is the command's exit code.
- If CamLid is not running, the exit code is 4 and the command does not run.

Example: `camlid run -- make test`

## 3. Keep the Mac awake for a session (only when asked)

    camlid start --mode auto
    camlid start --mode timed --duration 30m
    camlid stop

- `auto`: awake while the agents the user selected are working, then the Mac may sleep.
- `timed`: awake for `--duration`. Use `infinite` for no limit, or a step such as `30m`. Other values are refused with `invalidDuration`.
- Stop only a session you started. Never stop a session the user started unless they ask.
- If `start` is refused, read `reason` in the JSON and report it. Do not retry in a loop.

## 4. Diagnose

    camlid diagnose --json
    camlid helper status --json

Use `diagnose` to explain why the Mac is awake. Read `protection`, `activeSessionMode` and `errors`. Use `helper status`
for the closed-lid helper: only `status` = `installed` means it is ready. Otherwise tell the user; do not install it yourself.

## Rules

- If you started a session, run `camlid stop` when your work is done.
- Do not change CamLid settings or closed-lid mode.
- `camlid helper install`, `uninstall` and `trust` need an administrator password. Ask the user to run them.
- Closed-lid protection depends on the user's settings and on the helper. Do not assume it works. Check `camlid diagnose --json`.
