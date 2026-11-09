# CamLid power helper

The root helper that CamLid installs once, with an administrator password. It changes the Mac's sleep setting only while
the signed app holds a lease, and restores the setting when the lease ends.

## What ships

- `camlid-power-helper`, the daemon. The app copies it to `/Library/PrivilegedHelperTools/com.camlid.power-helper` and
  writes two launchd jobs to `/Library/LaunchDaemons/` (`HelperInstaller.swift`):
  - `com.camlid.power-helper`: started with `--standard-v1`, kept alive, serves the app over XPC.
  - `com.camlid.power-recovery`: started with `--recover-v1` every 15 seconds. It restores the setting when the daemon
    is gone.
- `CamLidPowerService`, the library the daemon links: the XPC listener, the lease service and the mechanisms. It uses
  `LidRecoveryJournal` for durable intent records and `LidNativeAdapter` for the pmset, power assertion and lid-control
  bindings.
- `camlid-power-qa`, a QA tool. It is part of this package but not of the app bundle.
- `Support/`: reference copies of the daemon plists, and `stage-local-candidate.py`, a script for QA builds. The app does
  not read these files; it writes its own plists.

## Behaviour

- **Standard** (default): while a lease is held, sets the system `SleepDisabled` setting with
  `/usr/bin/pmset -a disablesleep 1`, reads it back with `pmset -g`, and sets it back to 0 when the lease ends.
- **Strict** (experimental): a lease that asks for Strict uses the clamshell control instead of the global setting. A
  restart clears it ([ADR 0003](../../docs/adr/0003-strict-mode-lid-only-on-the-persistent-helper.md)).
- **Lease:** 30 seconds, renewed by the app every 10 seconds (`PowerLeaseService.leaseSeconds` and `heartbeatSeconds`).
  A session lasts at most 4 hours. When the client disconnects, its lease is released.
- **Journal:** the helper records what it will change before it changes it, so a crash, a restart or a lapsed lease
  leaves a record that the recovery job or the next start can act on.
- **Safety:** admission and monitoring use the helper's own readings (power source, battery, thermal state, lid and
  console user). A client cannot supply sensor evidence.
- **Who may talk to it:** the XPC listener accepts only the pinned app. The requirement comes from `PowerHelperIdentity`
  in `CamLidPowerWire`. With an Apple Team ID, it is the exact app identifier and team, anchored to Apple. Otherwise the
  pins in `/Library/Application Support/CamLidPowerHelper/identity.json` decide: version 2 pins the release
  certificate's SHA-1, and version 1 pins the exact code hash.

## Build and test

```sh
swift test --package-path Packages/CamLidPowerHelper
```

The app build embeds the helper through `scripts/embed-helper.sh`.

## Limits

- `SleepDisabled` is global and persistent. While it is set, a manual Sleep request, or a sleep caused by low battery or
  high temperature, may be blocked. The helper's safety checks reduce that exposure; they do not make the OS expire the
  setting.
- If launchd cannot run the daemon or the recovery job, nothing restores the setting until it can.
- A write that sets the same value as another program's write cannot be told apart from CamLid's own write.
- Lid-closed and manual-Sleep results on real hardware are in [spec 014](../../specs/014-persistent-helper/g2-trial.md)
  and [spec 016](../../specs/016-strict-lid-only/tasks.md). Unit tests use injected fakes and do not qualify a Mac.
