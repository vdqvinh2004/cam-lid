# Implementation Plan: Closed-Lid Best-Effort Hardening

**Feature context:** `013-closed-lid-hardening`
**Status:** Offline implementation complete 2026-10-20 (16/18 tasks). T501/T502 remain
blocked. No native power action, helper installation, app integration or shipping-gate change
was performed. This is not a qualification. Evidence:
[offline QA note](../../docs/qa/m9-closed-lid-hardening-offline-2026-10-20.md).
**Spec:** [spec.md](spec.md)
**Inputs:** [012 spec](../012-closed-lid-best-effort/spec.md),
[012 plan](../012-closed-lid-best-effort/plan.md),
[closed-lid product path](../../docs/planning/closed-lid-product-path-2026-10-19.md),
LidRun REA report (external path `cam-lid-v2/reports/`; not copied into
CamLid).

## Summary

M9 hardens the experimental best-effort closed-lid path without changing its actuator. The
current selector-12 path is narrow but has three practical gaps:

1. It only checks the global `SleepDisabled` policy at admission; a foreign change during an
   active session is invisible.
2. A current-boot pending enable/restore already maps to recovery-required, but the reason is
   too coarse to tell the user what happened.
3. Helper timeout/hang behavior is documented in prose, not encoded as a stable refusal or
   recovery reason.

M9 adds a read-only foreign-policy probe, explicit recovery reasons, helper-availability
mapping, and tests. It does not add a global setter, an administrator fallback, a second
watchdog, or a new power mechanism.

## Technical Context

**Language/Version:** Swift 6.0 (package tools version), macOS 14+.
**Primary dependencies:** existing `CamLidPowerService`, `LidRecoveryJournal`,
`LidNativeAdapter`; no new package.
**Storage:** existing helper journal and best-effort projection; no migration is required for
the real journal. The offline `BestEffortJournalEntry` gains an `intent` field so tests can
distinguish pending enable from pending restore.
**Testing:** Swift Testing (`@Suite`, `#expect`), fake clocks/probes/journals; no native action.
**Target platform:** macOS 14+; target MacBook Air remains the first support row.
**Project type:** menu-bar app plus privileged helper and CLI.
**Performance:** the probe is a bounded IORegistry property read, not a subprocess; no
per-second shell execution.
**Constraints:** no global sleep write, no admin fallback, no new privileged process, no
shipping-gate change, no app integration in M9.

## Constitution Check

| Gate | Assessment |
|---|---|
| I. Safety overrides keep-awake | Pass. A foreign policy or unreadable observation stops the session; no new override is added. |
| II. Third-person activity evidence | Not affected; no agent/provider integration is touched. |
| III. Native, minimal, accessible | Pass. Reuses the existing root-domain read and service model; no new dependency or helper. |
| IV. One policy, two interfaces | Pass for the offline contract tests; actual GUI/CLI wiring remains G3 and needs separate approval. |
| V. Private, explainable operation | Pass. New reasons/receipts contain no prompts, secrets or user content. |
| Platform constraints | The actuator stays undocumented and experimental; M9 does not claim verified restoration or shipping qualification. M1 remains blocked. |

No constitution violation is introduced. The existing best-effort exception remains explicit:
the shared lid bit has no trustworthy getter, so the product uses acknowledged-only cleanup
and never promotes it to verified/protected.

## Project Structure

### Documentation

```text
specs/013-closed-lid-hardening/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/status.md
├── checklists/requirements.md
└── tasks.md
```

### Source and tests

```text
Packages/CamLidPowerHelper/
├── Sources/CamLidPowerService/
│   ├── NativeHelperEnvironment.swift      # read-only global policy access
│   ├── LeasePowerMechanism.swift          # observation protocol + lid-specific adapter
│   └── PowerLeaseService.swift            # active-session conflict stop/reason
└── Tests/CamLidPowerServiceTests/
    ├── LidSpecificMechanismTests.swift
    └── PowerServiceTests.swift

Tests/Experiments/BestEffortLidSession/
├── Sources/BestEffortLidSession/
│   └── BestEffortProductModel.swift       # reasons, journal intent, re-arm basis, presentation
└── Tests/BestEffortLidSessionTests/
    ├── BestEffortProductModelTests.swift
    └── SimulatedLidSessionTests.swift
```

No application, CLI executable, helper plist, entitlement or installer path is changed in M9.

## Design Decisions

### D1 — Observe foreign policy; never own or clear it

Add a read-only observation to the mechanism boundary:

```swift
public enum ForeignPolicyObservation: Sendable, Equatable {
    case clear
    case conflicted
    case unreadable
}

public protocol LeasePowerMechanism: AnyObject {
    // existing members...
    func readForeignPolicy() throws -> ForeignPolicyObservation
}
```

The method is **required**, not defaulted: a new mechanism must state whether it observes a
foreign policy. `GlobalSleepMechanism` returns `.clear` because its own `readApplied()` already
observes the flag it owns; test mechanisms must also implement it.
- `LidOnlyLeaseMechanism` reads the root-domain `SleepDisabled` boolean through a small
  injected closure. The production closure lives in `NativeHelperEnvironment`; tests inject a
  fake.
- Do **not** read `AppleClamshellCausesSleep` here. It is derived/stale policy, not a conflict
  signal.
- Do **not** spawn `/usr/bin/pmset` from the probe. The existing IORegistry read is cheaper and
  avoids a subprocess on the helper's serial queue.

### D2 — Stop semantics and state mapping

`PowerLeaseService.poll()` checks, in order:

1. session cap and lease deadline;
2. safety freshness;
3. own applied state (`readApplied()`); a read failure remains `monitorFailed`;
4. foreign global policy observation; a conflict/unreadable takes precedence over an own
   applied-state mismatch for the stop reason;
5. own applied-state mismatch, if the foreign observation is clear.

A definite `.conflicted` stops with reason `foreignGlobalSleepDisabled`. An `.unreadable`
stops with reason `foreignPolicyUnreadable`. Both are fail-closed: the session must not continue
with an unknown outside policy.

After CamLid's own one-shot clear:

- if the clear returns `callsAcknowledgedOnly`, the own cleanup receipt is retained;
- if the reason was a foreign conflict or unreadable observation, the final state is
  `recoveryRequired`, not `cleanupAcknowledged`, even when the own calls succeeded;
- if the clear itself fails, `restorationFailed` is more severe and remains the reason;
- the UI explains that CamLid stopped and did not clear the other actor's policy;
- a same-boot helper restart re-observes the policy before treating an acknowledged enable or
  restore as cleanup; an acknowledged enable still gets one own-lid clear, and the model boot
  accepts the same observation;
- readiness later refuses a new start while `SleepDisabled` is true/unknown.

If the global policy becomes clear again, the old session stays stopped. A new start must pass
all normal gates. Do not add a new user-facing state unless the UI tests show that
`recoveryRequired` is ambiguous; the default is to reuse it.

### D3 — Keep the no-blind-clear recovery policy

Do not change the current behavior for a current-boot pending enable/restore. The lack of a
trustworthy shared-bit getter means the journal cannot prove whether a pending write landed.
The safe outcome remains:

- current-boot pending enable → `recoveryRequired`; no clear;
- current-boot pending restore → `recoveryRequired`; no retry clear;
- current-boot acknowledged enable → `recoveryRequired` with
  `currentBootEnableAcknowledged`; no clear and no cleanup claim;
- previous-boot abnormal baseline → `recoveryRequired`;
- acknowledged restore with normal baseline → `cleanupAcknowledged` (never verified).

M9 improves **explainability**, not the recovery authority:

- add `intent` to the offline `BestEffortJournalEntry` so the projection can distinguish an
  enable from a restore;
- add stable reasons `pendingCurrentBootEnable`, `pendingCurrentBootRestore`,
  `currentBootEnableAcknowledged`, `previousBootAbnormalBaseline` and
  `previousBootSuperseded`;
- keep the existing one-clear/no-retry journal rules;
- keep the existing risk copy and reboot guidance.

A guarded same-boot clear remains a separate product decision, not an M9 implementation.

### D4 — Helper unavailability is a refusal/recovery reason, not a retry loop

- `PowerHelperClient` already has a five-second timeout. M9 maps no connection, invalid reply
  and helper restart to `helperUnavailable`, and timeout to `helperTimeout`, in the projection.
- Do not add automatic retries or a new XPC operation.
- Do not add an in-helper watchdog. A helper that is hung cannot run its own watchdog, and a
  second privileged process would need its own journal/arbitration. That is out of scope.
- Document the residual failure class: helper hang may require reboot; no 30-second recovery
  guarantee is claimed.

### D5 — Re-arm is an explicit qualification, never a property read

- R0 was accepted on 2026-10-20, but this milestone still keeps the production default
  `rearmAllowed = false`; only an explicit qualification input may set it.
- Add `rearmBasis` to the status contract: `none`, `behaviouralLidCycle`, `reboot` or
  `explicitQualification`. Default is `none`; only the qualification path sets another value.
- `AppleClamshellCausesSleep` remains an advisory readiness indicator. Its value never sets
  `rearmAllowed` or `rearmBasis`.
- Cleanup-acknowledged is terminal for the session. It does not imply a new session is safe.

### D6 — GUI/CLI contract first; app wiring is G3

M9 changes the shared model/contract and fake tests. It does not wire a new control into the
shipping app. The contract gains:

- `foreignPolicy`: `clear | conflicted | unreadable | notObserved`;
- `recoveryReason` for pending enable/restore, previous boot and helper failure;
- `rearmBasis`;
- unchanged `protectionClaim: none` and `closedLidProtectionQualified: false`.

The G3 integration must consume the same contract. No app surface may render `Protected` or
`verified`.

### D7 — Tests before native evidence

All M9 tests use fakes. The native failure-class row for a foreign global policy is a G2 task
and needs a separate one-use approval. M9 can be complete without touching a real power policy.

## Implementation Map

| Area | Change | Notes |
|---|---|---|
| `NativeHelperEnvironment.swift` | Add read-only `globalSleepDisabled()` and reuse it in `lidOnlyBaselineAllowsAdmission()` | Preserve the `AppleClamshellCausesSleep` baseline check; no setter |
| `LeasePowerMechanism.swift` | Add `ForeignPolicyObservation` and a **required** `readForeignPolicy()`; implement in `LidOnlyLeaseMechanism` with an injected probe | `GlobalSleepMechanism` explicitly returns `.clear`; no silent omission |
| `PowerLeaseService.swift` | Check the probe in `poll()`; re-observe it on same-boot restart; stop with foreign/unreadable reasons; map final state after own clear | No global write; no retry |
| `BestEffortProductModel.swift` | Add journal intent, recovery reasons, `rearmBasis`, presentation copy, forbidden-string test hooks | Model-only; no app wiring |
| `LidSpecificMechanismTests.swift` | Fake probe clear/conflicted/unreadable; assert no global setter call; assert one own clear | Existing test style |
| `PowerServiceTests.swift` | Poll/stop/recovery mapping with fake clock/journal/safety | No real selector |
| `BestEffortProductModelTests.swift` | Pending enable/restore, previous boot, helper timeout, stale property, rearm refusal | Pure state tests |
| `contracts/status.md` | Exact JSON/status reason contract | GUI/CLI parity source |
| `quickstart.md` | Offline validation commands | No native commands |

## Phases and Sequencing

| Phase | Work | Gate |
|---|---|---|
| 0 — Decisions/audit | Confirm IORegistry observation semantics, reason mapping, helper-hang boundary, contract fields | No code; links and decisions recorded |
| 1 — Foreign-policy probe | D1/D2 implementation and tests | Fake tests pass; no global write |
| 2 — Recovery explainability | D3 model/reason/tests | Pending enable/restore cases all recovery-required |
| 3 — Helper/re-arm contract | D4/D5 mapping and tests | Helper timeout and stale property never produce ready/protected |
| 4 — Regression/handoff | Full Debug/Release offline suites, contract check, G2/G3 handoff | No native action; no app integration |
| 5 — Native/G3 (blocked) | G2 foreign-policy failure row; G3 UI/CLI wiring | Separate explicit approvals only |

Phases 1–3 can run in parallel after Phase 0, but the contract changes should land before the
final regression. No phase may install the helper or run a native policy action.

## Test Matrix

| Case | Expected |
|---|---|
| Policy clear at start and during active session | No foreign stop |
| Policy becomes disabled during active session | Stop; own clear once; foreign flag untouched; recovery reason |
| Policy unreadable during active session | Stop; `foreignPolicyUnreadable`; no healthy state |
| Policy disabled at start | Refuse with `globalSleepDisabled`; no mutation |
| Policy becomes clear after a conflict | Old session stopped; a new start passes normal gates |
| Same-boot helper restart with foreign conflict/unreadable | `recoveryRequired`; exactly one own-lid clear; no extra clear; pending journal reason still wins |
| Pending enable, current boot | `recoveryRequired`; no clear/retry |
| Pending restore, current boot | `recoveryRequired`; no clear/retry |
| Acknowledged enable, current boot | `recoveryRequired`; no clear/cleanup claim |
| Previous boot, normal baseline | May become ready; no verified claim |
| Previous boot, abnormal baseline | `recoveryRequired` |
| Helper timeout/unavailable/invalid reply/restart | Explicit refusal/recovery; no active or cleanup claim |
| Stale property true/false/unreadable after cleanup | No re-arm; no property-based qualification |
| GUI/CLI status projection | Same state/reason; no `Protected`/`verified` |
| Full offline suites, Debug and Release | Pass; no native action |

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| IORegistry observation is stale or missing | Fail closed; test unreadable/missing; never infer clear from absence |
| False stop on a transient read | Accept conservative stop; record reason; user can start again after normal checks |
| Another actor writes the same lid bit | Cannot detect; keep hidden-writer disclosure; do not claim ownership |
| Helper hang cannot be cleared by the helper | Document; no in-helper watchdog claim; reboot guidance; separate watchdog only in a future approved milestone |
| Pending write leaves override until reboot | Keep no-blind-clear; explicit recovery reason and reboot guidance; no auto re-arm |
| Scope creep into global `pmset` | Requirements forbid global writes and admin fallback; tests assert no setter |
| Property used as proof again | Tests assert stale true/false/unreadable never authorizes start/re-arm |
| Native evidence mistaken for offline pass | M9 exit is offline only; G2/G3 remain separate |

## Exit Gate and Handoff

M9 is complete when:

- all offline tasks are complete and the full helper/best-effort suites pass in Debug and
  Release;
- foreign clear/conflicted/unreadable cases and pending enable/restore cases have deterministic
  tests;
- no M9/lid-specific code path writes the global sleep policy, adds an admin fallback or
  adds a new watchdog;
- the GUI/CLI contract is documented and tested at the model level;
- no native action, helper install, app integration or shipping-gate change was performed;
- `qualifiedClosedLidProtection`, full-System-Sleep qualification and shared-bit restoration
  remain false.

Handoff:

- **G2** adds a native foreign-policy failure row (separate one-use approval); it does not
  inherit an M9 pass as hardware evidence.
- **G3** wires the contract into the app/CLI behind the experimental flag (separate approval).
- R0 was accepted on 2026-10-20. If G2 fails or the product track is stopped, M9 product work
  is parked; it does not create a new shipping path.

## Complexity Tracking

No new project, dependency or privileged component. The only new boundary is one read-only
observation method on the existing mechanism protocol; a second watchdog and a global-policy
setter are explicitly rejected.
