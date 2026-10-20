# Research: Closed-Lid Best-Effort Hardening

**Feature:** `013-closed-lid-hardening`
**Date:** 2026-10-20
**Boundary:** Source/documentation analysis only. No native policy read that changes state, no
helper command, no power action, no install and no app integration.

## Inputs

- [012 spec](../012-closed-lid-best-effort/spec.md) and
  [012 plan](../012-closed-lid-best-effort/plan.md).
- [Closed-lid product path](../../docs/planning/closed-lid-product-path-2026-10-19.md).
- `LidSpecificMechanism.swift`, `LeasePowerMechanism.swift`, `PowerLeaseService.swift`,
  `NativeHelperEnvironment.swift`.
- `BestEffortProductModel.swift` and its fake tests.
- LidRun REA report in `cam-lid-v2` (external reference, not vendored
  and not copied into CamLid).
- R0 attempts #1–#3 and the T001 clear-path audit.

## Decisions

### D1 — Use the existing root-domain property, not a `pmset` subprocess

**Decision:** Observe the global sleep-disable policy through the same read-only
`IOPMrootDomain` property used at admission (`SleepDisabled`), via a small injected closure.

**Rationale:** no subprocess on the helper's serial queue, no shell/parser path, and the
admission check already trusts this property. A subprocess would add latency, output parsing
and a new timeout failure mode.

**Refresh and failure behavior:** the observation is read on every active-session poll, not
cached from admission. The source must be a `CFBoolean`; a missing property, wrong type, I/O
failure or timeout maps to `.unreadable`, never `.clear`. The absence of a getter is not
evidence that a shared lid bit is clear.

**Alternatives considered:**

- `/usr/bin/pmset -g` + strict parser: real readback, but heavier and still only reports the
  global flag, not the shared lid bit. Rejected for the one-second helper poll.
- `AppleClamshellCausesSleep`: rejected as a conflict signal. The T001 audit and R0 show it is
  derived/stale after wake and cleanup; false does not prove a foreign writer or a failed
  clear.

### D2 — Fail closed on an unreadable observation

**Decision:** `.unreadable` during an active session stops the session with
`foreignPolicyUnreadable`. `.notObserved` during an active session is also unknown and stops
with the same reason. Neither is treated as clear, and neither silently continues.

**Rationale:** the session's safety case depends on a known policy baseline. An unknown
outside policy is not evidence of safety. A conservative stop can be retried by the user after
normal readiness checks. A definite `.conflicted` stops with `foreignGlobalSleepDisabled`; a
same-boot restart re-observes the policy before treating an acknowledged enable or restore as
cleanup; an acknowledged enable still gets one own-lid clear, and a pending journal reason
remains more specific.

**Alternatives considered:**

- Continue with a warning: lower false-stop rate, but can leave the UI claiming a healthy
  session while the outside policy is unknown. Rejected for this experimental mode.

### D3 — Reuse `recoveryRequired`; do not add a new state yet

**Decision:** A foreign-policy stop that leaves the global policy disabled ends in
`recoveryRequired` with a specific reason. A completed own clear is still recorded as a
receipt, but not as verified restoration. No new session state is introduced in M9.

**Rationale:** `recoveryRequired` already means "do not rely on lid-close sleep." The UI can
explain that the cause is another actor's global policy. Adding a new state would expand the
GUI/CLI contract before UX evidence shows it is needed.

A current-boot **acknowledged enable** is also recovery-required
(`currentBootEnableAcknowledged`), not `cleanupAcknowledged`: the projection has not observed a
restore. A same-boot helper restart may repair it, but the app must not assume that happened.

**Alternatives considered:**

- `foreignPolicyConflict` as a new state: clearer label, but more state-machine and parity
  work; defer until the model tests show ambiguity.
- `cleanupAcknowledged` + warning: risks implying normal sleep is restored while the foreign
  global policy remains. Rejected.

### D4 — Keep the no-blind-clear recovery policy

**Decision:** Do not add a guarded same-boot clear in M9. Current-boot pending enable/restore
stays `recoveryRequired`; the user is told to reboot before relying on lid sleep.

**Rationale:** without a trustworthy shared-bit getter, a pending journal cannot prove whether
the write landed or whether a foreign writer set the bit. A blind clear can erase another
actor's policy. The owner already accepted the residual "until reboot" risk.

**Alternatives considered:**

- Clear on helper restart when the baseline was clear: reduces the stranded-override window,
  but can clear a foreign same-bit writer and needs a separate risk decision plus native fault
  evidence. Not M9.
- Repeat clear until a reply: rejected; it is a write-retry loop with no proof.

### D5 — No in-helper watchdog and no admin fallback

**Decision:** Document the helper-hang gap; do not add a watchdog process or administrator
AppleScript fallback in M9.

**Rationale:** an in-helper watchdog cannot run when the helper is hung. A separate watchdog is
a new privileged component that needs its own journal, arbitration and approval. The LidRun
fallback is a weaker, broader write path and is explicitly rejected by the product constraints.
The offline projection maps a missing connection, invalid reply or helper restart to
`helperUnavailable`, and a timeout to `helperTimeout`; it never retries the clear or claims an
active/cleanup state from a missing reply. Reboot guidance remains the fallback for a hang.

**Alternatives considered:**

- Copy LidRun's helper watchdog: not a hard OS lease; helper hang/kill defeats it. Rejected.
- Copy the AppleScript fallback: no post-fallback readback, broad global write, extra auth UX.
  Rejected.

### D6 — Re-arm is qualification, not a property read

**Decision:** Keep `rearmAllowed` false by default; add a `rearmBasis` field for traceability.
Only an explicit qualification path sets a non-`none` basis. `AppleClamshellCausesSleep` never
authorizes re-arm.

**Rationale:** R0 shows the property can be stale after wake. A true value is not proof that a
new native session is safe, and a false value is not proof of a foreign writer.

### D7 — Contract/model first; app wiring remains G3

**Decision:** M9 changes the offline model, helper tests and status contract. It does not wire a
new app control or install the helper.

**Rationale:** app integration needs its own explicit approval. The contract can be tested
without touching the shipping app or native policy.

## Open Questions Resolved

| Question | Resolution |
|---|---|
| Read `SleepDisabled` every poll or only at start? | Every active-session poll, via IORegistry; no subprocess. |
| Stop or warn on unreadable? | Stop/fail closed with `foreignPolicyUnreadable`. |
| Add a new state for foreign conflict? | No; reuse `recoveryRequired` with a specific reason. |
| Clear the foreign global flag? | Never. Only CamLid's own lid bit is cleared. |
| Add a watchdog for helper hang? | No; document and defer to a separately approved future milestone. |
| Can a stale true property re-arm? | No; explicit qualification only. |
| Does M9 qualify anything? | No; it is offline hardening. M1, G2 and G3 remain separate. |
