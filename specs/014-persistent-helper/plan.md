# Implementation Plan: Persistent Helper (Standard Mode)

**Feature context:** `014-persistent-helper` · **Spec:** [spec.md](spec.md) · **Decision:** [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md)

## Summary
Reuse the existing `PowerLeaseService`, `PMSetBackend`, journal, safety and XPC identity code. Add an installer, an independent recovery path, restart recovery from the persisted record, and a mode layer. No new power mechanism.

## Source touchpoints (existing)
- `Packages/CamLidPowerHelper/Sources/camlid-power-helper/main.swift`: selects the backend from argv (empty = global pmset; `--lid-specific-*` = Strict).
- `Packages/CamLidPowerHelper/Sources/CamLidPowerService/`: `PowerLeaseService`, `PMSetBackend`, `LeasePowerMechanism`, `PowerXPC`, `LocalIdentityPins`, `StoragePermissions`.
- `Packages/CamLidPowerHelper/Support/com.camlid.power-helper.plist`: reference plist (lacks explicit lid-specific arguments).
- `Packages/CamLidCore/Sources/CamLidCore/PowerController.swift` and `CamLidApp/AppCoordinator.swift`: app-side backend use.

## Design decisions
- **D1 Installer.** CLI `camlid helper install|uninstall|trust|status` plus an app action using a fixed-command administrator prompt. Installs the binary to `/Library/PrivilegedHelperTools/` and a LaunchDaemon plist with `RunAtLoad` and `KeepAlive`. The same code path serves both entry points.
- **D2 Identity.** Keep peer requirement checks. Without a Developer ID, pin the exact cdhash at install time; `trust` re-pins after a rebuild. Pins are written by root only.
- **D3 Restart recovery.** On startup the helper reads the journal before listening; an expired or orphaned owned policy is restored and verified first.
- **D4 Independent recovery (chosen in T103).** A second LaunchDaemon, `com.camlid.power-recovery`, runs `camlid-power-helper --recover-v1` every 15 s. It opens the journal without taking the helper lock (so a hung helper cannot block it), and restores only an acknowledged enable whose lease deadline plus a 10 s grace has passed, or one from another boot, then reads the policy back. Journal commits are revision-checked, so a racing helper write makes the recovery attempt fail and retry instead of overwriting. Worst-case restore after a helper hang is about deadline + 10 s grace + 15 s interval. Alternative rejected: a detached worker per session, which dies with the same failures it should cover. `--release-v1` is the same logic with no grace and is used by uninstall.
- **D5 Modes.** `PowerMode { standard, strict }` selects helper endpoint and storage directory. A small lock refuses a switch while a lease or unresolved journal exists in either.
- **D6 Strict.** Unchanged and frozen; surfaced only under an experimental setting.
- **D7 Wiring sessions to the helper.** `PolicyEngine.evaluate` stays unchanged and shared by Auto, Timed, Manual, CLI and simulator. After it, the coordinator computes `desired = mode in {auto, timed, manual} && closedLidOptIn && helper ready && state in {protected, completionGrace}` and calls a pure `PowerHoldReconciler` (acquire, renew every 10 s, release). A thin `PowerLeaseClient` (XPC, pinned helper identity) performs the calls and is replaced by a fake in tests. The helper's reply is the source of truth: `leaseVerified` and `powerActuationAvailable` become true only with a held, read-back lease; a helper refusal or stop (`safetyRefused`, `foreignGlobalSleepDisabled`, `renewalExpired`) becomes a safety stop or recovery conflict; verified restoration feeds `RestoreState`, so Sleep when done still waits for restoration. Closed-lid sessions are capped at the helper's 4 h maximum (`capDeadline = min(capDeadline, start + 4 h)`), consistent with the non-extending cap; Auto does not renew past it. When closed lid is unavailable the session shows the specific reason instead of a simulated Protected state. Shared wire types move to a small `CamLidPowerWire` library rather than making the app depend on `CamLidPowerService` (IOKit and native adapters).

- **D8 Permission on untrialled Macs (owner decision 2026-10-31, option D).** Exact support rows stay the only way
  to be "qualified". Any other Mac may run closed lid after the user accepts "untested configuration" for its exact
  model and build. Rationale: the safety layers proven in G2 (lease, recovery job, restart restore, foreign-policy
  refusal) do not depend on the model; the model-dependent part is how `pmset disablesleep` behaves, which is the same
  command on current Macs. A pure `ClosedLidPermit.decide(row:acknowledgement:system:)` returns `qualified(id)`,
  `untestedAcknowledged` or `notPermitted(reason)`; the coordinator uses it where it used `closedLidSupportRow`, and
  `ProtectionReadiness` already has an `untestedConfiguration` state to project it. The acknowledgement is a
  preference (`model`, `osBuild`, date), not configuration, so config migration cannot set it. Conflict detection
  reads `launchctl print system/<label>` for a short list of known labels and changes nothing.

## Phases
0. Spec and decisions (this folder, ADR). 1. Helper core: restart recovery, independent recovery, plist fix. 2. Installer and trust. 3. Mode layer and UI. 4. Fake-backed tests for all failure classes. 5. Controlled physical qualification (owner-approved, attended). 6. Integration sign-off (G3).

## Risks
- Untested Macs may behave differently from the trialled one (for example `pmset` output during shutdown); the
  acknowledgement makes that the user's informed choice, it does not remove the risk.
- Agent-activity evidence (M3) is not qualified; a false "completed" lets the Mac sleep mid-task and a false "working" holds it awake too long. Closed lid raises the cost of both.
- The app and the helper run separate safety checks; tests must show they cannot disagree silently (app thinks safe, helper refuses).
- Independent recovery design is unproven; D4 may need a prototype first.
- Persistent root daemon raises the attack surface; peer rejection must be tested with real invalid signatures.
- cdhash pinning makes contributor builds awkward (open ADR question).
- Unsigned binaries are blocked by Gatekeeper when downloaded.
