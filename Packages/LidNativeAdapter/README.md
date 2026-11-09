# Native OS bindings

Swift bindings to the macOS power interfaces that the CamLid power helper uses: the `pmset` runner, an owned idle power
assertion, the shared lid (clamshell) control with its root-domain calls, and a conservative safety sampler (battery,
AC, thermal state, lid, displays and topology).

- `NativeHelperEnvironment` (in `CamLidPowerService`) composes these bindings for the shipping daemon.
- `NativeSafetySampler` gates on fresh readings: a missing or stale reading counts as unsafe.
- `NativeEpisodeCalls` adapts the assertion and the lid control to the `OneEpisodePowerCalls` seam of `LidRecoveryBroker`.
- `LidAttendedPreflight` is a read-only executable. With no arguments or `--readiness` it reads sensors and reports; any
  other argument is refused before any sensor or power call.

Platform: macOS 13 or later. Depends on `LidRecoveryBroker`.

## Build and test

```sh
swift test --package-path Packages/LidNativeAdapter
```

Tests use fake OS boundaries. They do not assert power or change the lid control.

## Boundaries

- The shared lid control is not rolled back when a connection closes, and an idle assertion's timeout does not expire the
  lid bit.
- Behaviour on real hardware is qualified by the closed-lid trials in [spec 014](../../specs/014-persistent-helper/g2-trial.md)
  and [spec 016](../../specs/016-strict-lid-only/tasks.md), not by these tests.
