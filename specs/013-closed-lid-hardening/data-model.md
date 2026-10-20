# Data Model: Closed-Lid Best-Effort Hardening

**Feature:** `013-closed-lid-hardening`
**Boundary:** Design-level model only; no production state is changed by this document.

## 1. Foreign policy observation

```text
ForeignPolicyObservation
├── clear        global SleepDisabled is definitely false
├── conflicted   global SleepDisabled is definitely true
└── unreadable   missing, wrong type, stale or read failure
```

Rules:

- `clear` does not mean the shared lid bit is clear; it only means the global policy is not an
  observable conflict.
- `conflicted` is a foreign-policy signal for the lid-specific mechanism. CamLid must not
  write the global policy.
- `unreadable` fails closed during an active session.
- The observation carries no ownership or restoration claim.

## 2. Journal intent

The real helper journal already records intent. The offline best-effort projection gains the
same distinction:

```text
BestEffortJournalIntent
├── enableLidOverride
└── restoreLidPolicy
```

`BestEffortJournalEntry`:

| Field | Meaning |
|---|---|
| `recordID` | Journal record identity |
| `bootID` | Boot that created the record |
| `intent` | Enable or restore |
| `disposition` | pending / acknowledged / unknown |

The projection uses `intent + disposition + bootID` to produce a recovery reason. It does not
use the public clamshell property to infer intent.

## 3. Recovery reasons

Add stable reasons to the best-effort projection:

| Reason | Meaning |
|---|---|
| `pendingCurrentBootEnable` | This boot has an enable whose outcome is not acknowledged |
| `pendingCurrentBootRestore` | This boot has a restore whose outcome is not acknowledged |
| `currentBootEnableAcknowledged` | This boot has an acknowledged enable but no observed restore |
| `previousBootAbnormalBaseline` | An old journal exists and the current public baseline is not normal |
| `previousBootSuperseded` | An old journal is superseded by a normal post-boot baseline |
| `foreignGlobalSleepDisabled` | Another actor disabled global sleep during the session |
| `foreignPolicyUnreadable` | The global policy observation failed during the session |
| `helperUnavailable` | No helper connection, invalid reply or helper restart |
| `helperTimeout` | The helper did not reply within the client bound |
| `globalSleepDisabled` | The global policy was already disabled at readiness (existing) |
| `globalSleepStateUnknown` | The global policy was unreadable at readiness (existing) |

Reason values are part of the GUI/CLI contract and must remain stable.

## 4. Session state

M9 does not add a new session state. The projection uses the existing states:

```text
off
ready
active
cleanupAcknowledged
recoveryRequired
```

Transitions for M9:

| From | Event | To | Reason |
|---|---|---|---|
| ready | start accepted | active | active |
| active | global policy becomes disabled | recoveryRequired | foreignGlobalSleepDisabled |
| active | global policy becomes unreadable | recoveryRequired | foreignPolicyUnreadable |
| active | no observation (`notObserved`) | recoveryRequired | foreignPolicyUnreadable |
| restart | pending current-boot enable | recoveryRequired | pendingCurrentBootEnable |
| restart | pending current-boot restore | recoveryRequired | pendingCurrentBootRestore |
| recoveryRequired | explicit qualification + normal readiness | active | normal start |
| cleanupAcknowledged | start without qualification | cleanupAcknowledged | rearmNotQualified |
| active | helper no connection/invalid reply/restart | recoveryRequired | helperUnavailable |
| active | helper timeout | recoveryRequired | helperTimeout |
| boot/restart | foreign policy conflicted and journal otherwise ready | recoveryRequired | foreignGlobalSleepDisabled |
| boot/restart | foreign policy unreadable and journal otherwise ready | recoveryRequired | foreignPolicyUnreadable |

`cleanupAcknowledged` means CamLid's own calls were acknowledged; it never means verified
restoration. A foreign global policy that remains after a stop takes precedence and maps to
`recoveryRequired`. A current-boot acknowledged enable also maps to `recoveryRequired` because
no restore was observed.

Precedence in the helper poll: cap/deadline, then safety, then own-read failure
(`monitorFailed`), then foreign conflict/unreadable, then an own applied-state mismatch. The
foreign observation wins the stop reason over an own mismatch; an own clear failure is more
severe and remains `restorationFailed`.

On a same-boot restart, an acknowledged enable or restore is re-checked against the read-only
foreign policy. An acknowledged enable still gets exactly one own-lid clear; the final state is
recovery-required when the policy is conflicted or unreadable. A pending/abnormal journal
recovery reason wins over the foreign reason; an otherwise ready/cleanup projection is upgraded
to recovery.

## 5. Re-arm basis

```text
BestEffortRearmBasis
├── none
├── behaviouralLidCycle
├── reboot
└── explicitQualification
```

Rules:

- Default `none`.
- `AppleClamshellCausesSleep` never changes this value.
- A `cleanupAcknowledged` state with `none` refuses a new start.
- `behaviouralLidCycle` requires the G1/R0 evidence; `explicitQualification` requires a
  separately recorded gate decision.
- A new start still re-checks AC, battery, thermal, lid, external displays, helper, journal and
  consent.

## 6. Status contract

The shared status object gains:

| Field | Values | Notes |
|---|---|---|
| `foreignPolicy` | clear / conflicted / unreadable / notObserved | Observation, not ownership |
| `recoveryReason` | stable reason or null | Set for recovery-required states |
| `rearmBasis` | none / behaviouralLidCycle / reboot / explicitQualification | Default none |
| `protectionClaim` | always `none` | Unchanged |
| `closedLidProtectionQualified` | always `false` | Unchanged |

Invariants:

1. `protectionClaim` is never `verified` or `protected`.
2. `closedLidProtectionQualified` is never true for this backend.
3. A foreign-policy stop never clears the global policy.
4. A pending journal never produces `ready` or `verified`.
5. GUI and CLI serialize the same state/reason/rearm values.

## 7. Helper failure mapping

| Fake-client outcome | Refusal / recovery reason | Active-session result |
|---|---|---|
| no connection | `helperUnavailable` | `recoveryRequired`, clear unknown |
| timeout | `helperTimeout` | `recoveryRequired`, clear unknown |
| invalid reply | `helperUnavailable` | `recoveryRequired`, clear unknown |
| helper restart | `helperUnavailable` | `recoveryRequired`, clear unknown |

No outcome is retried, and none can produce `active` or `cleanupAcknowledged`.

## 8. Receipts

| Receipt | Meaning |
|---|---|
| Selector return code | The own lid-bit call returned a code; not proof of restoration |
| Service release code | The root-domain service release returned a code |
| Connection close code | The IOKit connection closed |
| Idle release code | The owned assertion release returned a code |
| Foreign policy observation | What the global policy looked like at stop; not ownership |

Receipts may be retained for a recovery state. A complete own-clear receipt does not override a
remaining foreign global policy.
