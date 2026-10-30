# G2 attended trial: Standard mode on one Mac

Purpose: decide whether closed-lid actuation may be enabled on one exact Mac model and OS build. Owner-run, attended,
on AC power. A pass is the only reason to add a row to `QualifiedSupportRows.rows`; until then no build asks the helper to
hold power. This passes no other gate. Run the install trial first ([install-trial.md](install-trial.md)).

## Preconditions
- AC connected, battery at least 50%, no external display, no other sleep-preventing tools running, `pmset -g` shows `SleepDisabled 0`.
- Helper installed and `--helper-inspect` returns `accepted=true state=ready`.
- A disposable workload that proves progress while the lid is closed:
  `while true; do date +%s >> /tmp/g2-progress.log; sleep 5; done`
- Know the manual restore: `sudo pmset -a disablesleep 0`, and `sudo camlid helper uninstall --force`.

## Enabling the trial build (local edit, never committed before a pass)
Add one row for this Mac to `QualifiedSupportRows.rows` in `Packages/CamLidCore/Sources/CamLidCore/SupportRows.swift`, using
`sysctl -n hw.model kern.osversion`, rebuild, reinstall the helper (`helper trust` if only the app changed) and turn on
"closed lid" in Settings. The `noRowIsQualifiedInShippedCode` test will fail on the local edit by design.

## Trials (record time, `SleepDisabled` before / during / after, and `/tmp/g2-progress.log` gaps)
| # | Action | Pass when |
|---|---|---|
| 1 | Timed 10 min, close the lid for 5 min, reopen | `SleepDisabled 1` while held; progress log has no gap over 15 s with the lid closed; Stop returns it to 0 |
| 2 | Start Timed, press Stop with the lid open | `SleepDisabled` back to 0 within 5 s; dashboard shows restoration verified |
| 3 | Start Timed, `kill -9` the CamLid process | `SleepDisabled` back to 0 within 35 s |
| 4 | Start Timed, `sudo kill` the helper process | launchd restarts it; `SleepDisabled` 0 within 35 s |
| 5 | Start Timed, `sudo kill -STOP` the helper (hang) | recovery job restores within about 55 s of the last renewal; then `sudo kill -CONT` and stop the session |
| 6 | Start Timed, unplug AC | session stops with a stated reason; `SleepDisabled` 0 within 15 s |
| 7 | Start Timed 30 min, `sudo shutdown -r now` | after reboot and login `SleepDisabled` is 0 (cross-boot restore) |
| 8 | Auto with a real agent task (T706): start, work, completion grace, then lid closed | held during work; released after grace; Mac sleeps only after restoration is verified |
| 9 | Another app sets `sudo pmset -a disablesleep 1` before starting | CamLid refuses and does not clear it |

## Abort
Stop and restore (`sudo pmset -a disablesleep 0`) if `SleepDisabled` stays 1 for more than 2 minutes after a stop, the Mac
feels hot, the battery drops below 30%, or any trial behaves differently from the table. Report the exact output.

## Result
All nine rows pass on the exact model and OS build, evidence kept locally, owner approves in writing: add the row
(`id`, `model`, `osBuild`) in a commit of its own. Any failure leaves the table empty.
