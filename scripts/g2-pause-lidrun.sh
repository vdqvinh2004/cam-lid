#!/bin/bash
# Pauses the LidRun helper (SIGSTOP) while a G2 trial runs, because it resets `pmset disablesleep` that it did not set.
# Run with sudo in its own terminal and leave it open. Press Enter (or close the terminal, or Ctrl+C) to continue the
# helper; the trap below always continues it.
set -u
PID=$(launchctl print system/com.lidrun.app.helper 2>/dev/null | awk '$1=="pid"{print $3; exit}')
if [ -z "$PID" ]; then echo "LidRun helper is not running; nothing to pause."; exit 0; fi
trap 'kill -CONT "$PID" 2>/dev/null; echo "LidRun helper continued"' EXIT INT TERM HUP
kill -STOP "$PID" && echo "LidRun helper (pid $PID) paused. Press Enter when the trial is finished."
read -r _
