# Plan: v0.2 — lid-open keep-awake, wrapper, shortcut, calibration

## Layers

1. **Assertion owner.** New `KeepAwakeAssertion` in `CamLidApp`: creates and releases `IOPMAssertion`, reads back with `IOPMCopyAssertionsByProcess`. Injected, so tests can use a fake.
2. **Coordinator.** `holdDesired` splits into the closed-lid (helper) path and the lid-open (assertion) path. The lid state chooses the path during the session.
3. **Readiness.** `assertionVerified` evidence; a precedence test for lid-open protected.
4. **IPC.** Implement admit, renew and finish in `AppCoordinator` (now refused with `backendPendingM1`). Reuse `AutomationModels` receipts and the `EnrollmentSet` bound.
5. **CLI.** Route `run` to `RunCommand` (now `externalObservationOnly`); connect `isArmed` to the admission result. Stdio inheritance is already implemented.
6. **Shortcut.** New `GlobalHotKey` (Carbon `RegisterEventHotKey`), registered at start and released at quit.

## Test strategy

- Assertion: fake API; create → read back → release; read-back failure → unverified.
- Readiness table: lid-open protected; closed-lid protected; unverified never protected.
- Admit, renew, finish: owner checks, expiry, bound of 20, one-use receipts.
- `RunCommand`: exit mapping, signal forwarding, refusal without the app.
- Live: `pmset -g assertions`, `kill -9`, the four `camlid run` cases.

## Risks

- More holds for closed-lid-off users → release note and Dashboard copy.
- A stuck assertion if release fails → owned by the process; read back on each renew; quit releases all.
- The wrapper used to hide general workloads → explicit command only; nothing persisted; shown in Activity.
