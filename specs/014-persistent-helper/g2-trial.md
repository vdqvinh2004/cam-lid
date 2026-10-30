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

## Results on Mac17,3 / 26A434 (owner's Mac)
Pre-trial finding (2026-10-31): the LidRun helper (`com.lidrun.app.helper`) resets `pmset disablesleep` 40–60 s after
another process sets it (`scripts/g2-find-reverter.sh`: LidRun paused → held 81 s; LidWalk paused → reset after 47 s).
Trials run with the LidRun helper booted out.

| # | Date | Result | Evidence |
|---|---|---|---|
| 1 | 2026-10-31 | PASS | Lease acquired 01:23:17, renewed 56 times, released when the 10 min cap was reached at 01:33:20 with verified restore (`SleepDisabled` 0). Lid opened 01:33:12 (`powerd` lidopen assertion) after about 5 min closed. Progress log 01:22:26–01:39:50 has no gap over 15 s. |
| 2 | 2026-10-31 | PASS | Lease acquired 01:41:26; Stop pressed 01:42:22; helper `release` → `restore end state=restored reason=userStop` at 01:42:23 (about 1 s); `SleepDisabled` 0. |
| 3 | 2026-10-31 | PASS | Lease acquired 01:44:53; app killed with SIGKILL 01:45:27; helper `restore … reason=clientDisconnected` in the same second; `SleepDisabled` 0. |
| 4 | 2026-10-31 | PASS (SIGTERM) | Lease acquired 01:47:57; helper sent SIGTERM 01:48:30; `restore … reason=helperStopping` 01:48:32; launchd restarted it (new pid, `start state=ready`); the app's next renewal got `invalidLease` and the session stopped; `SleepDisabled` 0. SIGKILL variant: see 4b. |
| 4b | 2026-10-31 | PASS (SIGKILL) | Lease acquired 01:52:54; helper killed with SIGKILL 01:53:10; launchd restarted it in the same second; it read the journal and restored (`restore … reason=helperRestart`, `start state=restored`) by 01:53:11; next renewal `invalidLease`; `SleepDisabled` 0. |
| 5 | 2026-10-31 | PASS, with finding | Lease acquired 01:55:41; helper stopped (SIGSTOP) 01:56:03; the independent recovery job restored at 01:56:55 (`independentRecovery`, 52 s) and the owner saw `SleepDisabled` 0 at 01:56:57. Finding: when the stale helper resumed (01:57:21) its in-memory journal revision was behind, so its own restore failed the revision check and it reported `recoveryRequired / restorationFailed` (no write was made; `SleepDisabled` stayed 0); a restart (01:57:24, new pid) returned it to `ready`. To fix: reload the journal on a revision conflict and adopt an acknowledged restore. |
| 6 | 2026-10-31 | PASS | Lease acquired 01:59:49; charger unplugged 02:00:04; helper `poll stop reason=safetyStop` and verified restore at 02:00:10 (6 s); app session `safetyStopped` with `notCharging`; `SleepDisabled` 0. |
| 9 | 2026-10-31 | PASS, with UI finding | `SleepDisabled` set to 1 by hand; Timed started; helper refused (`acquire` → `preexistingOverride`, 02:02:36) and wrote nothing; `SleepDisabled` stayed 1 until the owner reset it. The dashboard showed only "Stopped — safety" without the reason, because the banner read the reconciler, which resets once the session stops. Fixed after the trial: the banner now reads the session's helper stop reason (test added); not yet re-checked in the app. |
| 7 | 2026-10-31 | **FAIL** (fixed in `7606e1c`, re-run pending) | Lease held, then `sudo shutdown -r now` at about 02:05:41. During shutdown the helper's restore failed (`monitorFailed`, then `restoreFailed`, error not logged by that build), leaving the journal at `restoreLidPolicy / pending`. After boot the helper started `recoveryRequired / uncertainPreviousMutation` and did not clear it, so **`SleepDisabled` was 1 after reboot** until reset by hand. |
| 7 (reinstall) | 2026-10-31 | finding, fixed | After reinstalling, the helper and the recovery job started together (RunAtLoad). The recovery job finished the interrupted restore first (`recovery outcome=restored`, 02:14:39); the helper's own commit then hit a journal revision conflict and it stayed `recoveryRequired / startupInspectionFailed` until restarted. Fixed: on a revision conflict the helper reloads the journal and adopts an acknowledged restore that reads back cleared. |
