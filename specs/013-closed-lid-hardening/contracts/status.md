# Status Contract: Closed-Lid Best-Effort Hardening

**Feature:** `013-closed-lid-hardening`
**Boundary:** Contract design only. The actual app/CLI wiring is G3 and needs a separate
approval.

## Scope

This contract defines the shared status projection for the experimental best-effort
closed-lid mode. It does not add a new actuator, helper operation or shipping capability.

## JSON Shape

The existing best-effort status fields remain. M9 adds three fields:

```json
{
  "mode": "bestEffort",
  "state": "recoveryRequired",
  "reason": "foreignGlobalSleepDisabled",
  "foreignPolicy": "conflicted",
  "recoveryReason": "foreignGlobalSleepDisabled",
  "rearmBasis": "none",
  "capSeconds": 900,
  "remainingSeconds": null,
  "leaseSeconds": 24,
  "clearEvidence": "callsAcknowledgedOnly",
  "receipt": {
    "selectorCode": 0,
    "serviceReleaseCode": 0,
    "connectionCloseCode": 0,
    "idleReleaseCode": 0
  },
  "consentVersion": "2026-10-19-v1",
  "warnings": [],
  "protectionClaim": "none",
  "closedLidProtectionQualified": false
}
```

Exact encoder key ordering is not significant. Values and types are.

## Fields

| Field | Type | Rules |
|---|---|---|
| `mode` | string | `bestEffort` |
| `state` | enum | `off`, `ready`, `active`, `cleanupAcknowledged`, `recoveryRequired` |
| `reason` | string | Stable reason; may equal `recoveryReason` |
| `foreignPolicy` | enum | `clear`, `conflicted`, `unreadable`, `notObserved` |
| `recoveryReason` | string or null | Required when state is `recoveryRequired` |
| `rearmBasis` | enum | `none`, `behaviouralLidCycle`, `reboot`, `explicitQualification` |
| `clearEvidence` | enum | `none`, `callsAcknowledgedOnly`, `unknown` |
| `receipt` | object or null | Per-call codes; never proof of restoration |
| `protectionClaim` | string | Always `none` for this backend |
| `closedLidProtectionQualified` | boolean | Always `false` |

## Reason Codes

| Code | State | Meaning |
|---|---|---|
| `globalSleepDisabled` | ready/refused | Global policy was already disabled |
| `globalSleepStateUnknown` | ready/refused | Global policy unreadable at readiness |
| `foreignGlobalSleepDisabled` | recoveryRequired | Foreign global policy appeared during the session |
| `foreignPolicyUnreadable` | recoveryRequired | Global policy became unreadable during the session |
| `pendingCurrentBootEnable` | recoveryRequired | Current-boot enable outcome is pending |
| `pendingCurrentBootRestore` | recoveryRequired | Current-boot restore outcome is pending |
| `currentBootEnableAcknowledged` | recoveryRequired | Current-boot enable was acknowledged but no restore was observed |
| `previousBootAbnormalBaseline` | recoveryRequired | Prior journal plus abnormal baseline |
| `helperUnavailable` | refused/recoveryRequired | No helper connection, invalid reply or helper restart |
| `helperTimeout` | refused/recoveryRequired | Helper reply timed out |
| `rearmNotQualified` | refused/cleanupAcknowledged | Re-arm has no qualification basis |

## Helper Failure Mapping

| Fake-client outcome | Refusal at readiness | Active-session recovery reason |
|---|---|---|
| no connection | `helperUnavailable` | `helperUnavailable` |
| timeout | `helperTimeout` | `helperTimeout` |
| invalid reply | `helperUnavailable` | `helperUnavailable` |
| helper restart | `helperUnavailable` | `helperUnavailable` |

No retry, no new XPC operation and no active/cleanup claim is permitted.

## Invariants

1. `protectionClaim` is always `none`.
2. `closedLidProtectionQualified` is always `false`.
3. A `foreignGlobalSleepDisabled` result never reports `globalSleepDisabled` as cleared.
4. A pending enable/restore never reports `ready`, `cleanupAcknowledged` or `verified`.
5. `rearmBasis != none` is required before a start after `cleanupAcknowledged`.
6. A stale `AppleClamshellCausesSleep` value cannot change `rearmBasis`.
7. GUI and CLI must emit the same `state`, `reason`, `foreignPolicy`, `recoveryReason` and
   `rearmBasis` for the same fake facts.
8. During an active session, `foreignPolicy=notObserved` is unknown and must map to
   `foreignPolicyUnreadable`; it is never treated as clear.
9. No field or reason may imply physical closed-lid protection or verified restoration.
10. A same-boot restart must re-observe the foreign policy before reporting cleanup; an
    acknowledged enable still gets one own-lid clear and remains recovery-required when the
    policy is conflicted or unreadable. A pending journal reason wins over the foreign reason.

## Compatibility

- Existing 012 fields keep their meanings.
- Adding fields is backward-compatible for readers that ignore unknown keys.
- Any consumer that treated `cleanupAcknowledged` as permission to start must also check
  `rearmBasis`; this was already required by 012, and M9 makes it explicit.
