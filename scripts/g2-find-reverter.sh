#!/bin/bash
# Finds which other root helper resets `pmset disablesleep`. Run with sudo. For each phase it sets SleepDisabled to 1,
# watches for about 80 s and reports whether and when it was reset, with the named helpers paused (SIGSTOP). Every
# paused process is continued and SleepDisabled is set back to 0 on exit, including on Ctrl+C.
set -u
pid_of() { launchctl print "system/$1" 2>/dev/null | awk '$1=="pid"{print $3; exit}'; }
LIDRUN=$(pid_of com.lidrun.app.helper)
LIDWALK=$(pid_of com.lidwalk.helper)
PAUSED=""
cleanup() {
  [ -n "$PAUSED" ] && kill -CONT $PAUSED 2>/dev/null
  pmset -a disablesleep 0
  echo "restored: SleepDisabled=$(pmset -g | awk '/SleepDisabled/{print $2}'), paused processes continued"
}
trap cleanup EXIT INT TERM

phase() {
  local label="$1"; shift
  PAUSED="$*"
  [ -n "$PAUSED" ] && kill -STOP $PAUSED
  pmset -a disablesleep 1
  local start=$SECONDS reverted=""
  for _ in $(seq 1 40); do
    sleep 2
    if [ "$(pmset -g | awk '/SleepDisabled/{print $2}')" = "0" ]; then reverted=$((SECONDS - start)); break; fi
  done
  pmset -a disablesleep 0
  [ -n "$PAUSED" ] && kill -CONT $PAUSED
  PAUSED=""
  if [ -n "$reverted" ]; then echo "$label: RESET by someone after ${reverted}s"; else echo "$label: HELD for $((SECONDS - start))s"; fi
  sleep 5
}

echo "LidRun helper pid=${LIDRUN:-none}, LidWalk helper pid=${LIDWALK:-none}"
[ -n "$LIDRUN" ] && phase "LidRun helper paused" "$LIDRUN"
[ -n "$LIDWALK" ] && phase "LidWalk helper paused" "$LIDWALK"
[ -n "$LIDRUN" ] && [ -n "$LIDWALK" ] && phase "both paused" "$LIDRUN" "$LIDWALK"
echo "done"
