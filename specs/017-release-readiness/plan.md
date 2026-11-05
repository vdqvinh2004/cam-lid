# Plan: Release readiness for v0.1.0

## Files

| File | Change |
|---|---|
| `Packages/CamLidCore/Sources/CamLidApp/AppCoordinator.swift` | `protectionReadiness()` takes build kind from configuration; status and start replies; renamed reason codes; `powerActuation` from the lease |
| `Packages/CamLidCore/Sources/CamLidCore/ProtectionReadiness.swift` | Build-kind mapping; blocker copy; precedence tests |
| `Packages/CamLidCore/Sources/CamLidApp/LiveSensors.swift` (`LiveSensorProvider.finish`) | Time the sensor call only; sampler queue quality of service; window only if the gate requires it |
| `Packages/CamLidCore/Sources/CamLidApp/OutcomeNotifications.swift` | Remove the Preview branch |
| `Packages/CamLidCore/Sources/CamLidApp/ActivityLogView.swift` | Readable text for renamed codes |
| `scripts/release.sh` | Identity guard, `--adhoc`, ADHOC file name, notes template |
| `README.md` | Status, signing and install text |

## Compatibility

- CLI contract change: `preview` is removed; `effectiveState` and `state` take real values. The release notes list the change. Renamed codes parse for one version.
- Helper unchanged: `PowerHelperVersion` stays 1 because no helper source change is planned. If the helper changes, bump it and follow ADR 0005.

## Test strategy

- **Unit:** readiness precedence table (release facts with and without a lease); build-kind mapping; sensor timing with an injected clock (call-only timing and the stall path); release script refusal in a temporary copy.
- **Live:** three-minute full-load closed-lid session on the installed release build; five status-versus-Dashboard checkpoints; closed-lid session end; `helper status` installed.

## Risks

- Renamed reason codes can break scripts. Mitigation: one-version alias.
- A timing change can hide a real stall. Mitigation: stall test and the window limits.
- Removing Preview can expose blockers that were hidden. Mitigation: write each blocker in plain words before publishing.
