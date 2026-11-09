# Feature Specification: Closed-Lid Best-Effort Hardening

> **SUPERSEDED for product deployment (2026-10-30):** the exclusive-create / no-adoption / one-use admission requirements in this document are replaced by the persistent-helper model of [spec 014](../014-persistent-helper/spec.md) and [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md). The mechanism described here remains as the experimental **Strict** mode, frozen. Evidence and dated records below are kept as history; per-episode approval is now an owner QA discipline, not a product requirement. No gate passed by this change.


**Feature context:** `013-closed-lid-hardening`; offline implementation complete. No branch
created.
**Created:** 2026-10-20
**Status:** Original offline hardening (16/18) plus reproducibility/install-packet follow-up T601–T605
complete; 22/23 current tasks checked. T501's native foreign-policy row PASS includes explicit
operator attestation; T502 remains blocked. The owner completed the separately approved
auth-only install/inspect and native retry. No app integration, entitlement change or
shipping-gate change was performed. This is not a qualification. Evidence:
offline QA note.
**Input:** Owner request following the LidRun REA review; closed-lid product path;
[012 spec](../012-closed-lid-best-effort/spec.md); [012 plan](../012-closed-lid-best-effort/plan.md).

## Reproducibility follow-up — 2026-10-21

Owner authorized safe preparation through the next human gate. Additional tasks T601–T605
cover committed regression fixtures, new candidate identity/staging, read-only QA readiness,
fake G2 harness tests and allowlisted root-journal inspection preparation. These do not change
FR-013's helper policy, actuator or shipping contract. T501 now has a row PASS
with operator attestation; full G2/G3 remain incomplete. The earlier
16/18 count describes the original task set. Current evidence/handoff.

## User Scenarios & Testing

### User Story 1 — See a foreign global sleep policy while a session is active (Priority: P1)

A user starts an experimental best-effort closed-lid session. Another utility or a manual
command changes the system-wide sleep-disable policy while the session is running. CamLid
stops its own session, does not claim that normal sleep is restored, and does not clear the
other actor's policy.

**Why this priority:** the current path only checks the global policy before a session. A
foreign change during a session can otherwise make the UI look healthy while the machine's
sleep behavior has changed.

**Independent Test:** with a fake policy observer, start a session, change the observed global
policy to disabled, and verify that CamLid stops, attempts its own lid-policy clear once, leaves
the foreign policy untouched, and reports a recovery/conflict reason.

**Acceptance Scenarios:**

1. **Given** an active best-effort session with the global policy clear, **When** the policy
   becomes disabled, **Then** CamLid stops the session, releases its own resources, records the
   conflict and does not write the global policy.
2. **Given** an active session, **When** the global policy observation becomes unreadable,
   **Then** CamLid fails closed with an explicit unknown/conflict reason instead of reporting a
   healthy session.
3. **Given** a conflict has stopped the session, **When** the user opens the app or CLI,
   **Then** the UI/CLI explains that another actor disabled system sleep and that CamLid did
   not clear it.
4. **Given** the global policy becomes clear again, **When** the user wants to continue,
   **Then** a new start still passes the normal readiness and qualification checks; the old
   session never silently resumes.

---

### User Story 2 — Recover honestly from an interrupted cleanup (Priority: P1)

CamLid or its helper crashes or is killed while an enable or clear is pending. On restart the
user can tell that recovery is required, is told to reboot before relying on lid-close sleep,
and sees no automatic blind clear or silent "ready" state.

**Why this priority:** the shared lid-sleep bit has no trustworthy getter. A pending write is
not proof of ownership or restoration; inventing a clean state is worse than requiring a
reboot.

**Independent Test:** with fake journal snapshots, exercise current-boot pending enable,
current-boot pending restore, previous-boot abnormal baseline and a completed clear. Verify the
state, reason and guidance in every case.

**Acceptance Scenarios:**

1. **Given** a current-boot journal with an enable that is still pending, **When** CamLid
   starts, **Then** the state is recovery-required, no clear is attempted, and the guidance says
   to reboot before relying on lid sleep.
2. **Given** a current-boot journal with a restore that is still pending, **When** CamLid
   starts, **Then** the state is recovery-required, no retry clear is attempted, and the same
   reboot guidance is shown.
3. **Given** a previous-boot journal and an abnormal public baseline, **When** CamLid starts,
   **Then** the state remains recovery-required; it is not promoted to ready by the reboot
   alone.
4. **Given** an acknowledged clear with a normal baseline, **When** CamLid starts, **Then** the
   state may be cleanup-acknowledged, never verified or protected.
5. **Given** a current-boot enable that is acknowledged but has no observed restore, **When**
   CamLid starts, **Then** the state is recovery-required, no clear is attempted, and CamLid
   does not claim cleanup.

---

### User Story 3 — Understand helper unavailability without a false recovery promise (Priority: P2)

The helper is stopped, unavailable or unresponsive when the user tries to start or stop a
session. CamLid reports the condition and recovery guidance; it does not spin, retry writes, or
claim that cleanup completed.

**Why this priority:** the helper is the only actor that can clear the lid bit. A hung helper
cannot be repaired by an in-helper watchdog, and a timeout is not proof of restoration.

**Independent Test:** with a fake client that times out or refuses a connection, verify the
same refusal/recovery reason in the product projection and CLI contract; verify no mutation is
started and no automatic retry is scheduled.

**Acceptance Scenarios:**

1. **Given** no helper connection, **When** the user starts a session, **Then** the start is
   refused with helper-unavailable guidance and no application mutation occurs.
2. **Given** an active session and a helper timeout, **When** the app cannot obtain a reply,
   **Then** it does not claim active/cleanup success; it shows recovery guidance and stops
   renewing.
3. **Given** a helper restart after an interrupted operation, **When** CamLid reconciles, **Then** the
   actual journal state controls the result; the app does not assume the restart fixed it.

---

### User Story 4 — Never re-arm from a stale public property (Priority: P2)

After cleanup, the public clamshell policy indicator may remain stale. The user cannot start
another native session merely because that property later reads true, or because a previous
session said "cleanup acknowledged."

**Why this priority:** the property is derived/stale policy, not a getter, and the accepted
risk is that restoration is unverified.

**Independent Test:** supply true, false and unreadable property values after a cleanup and
verify that none of them authorizes re-arm; only an explicit qualification/reboot path does.

**Acceptance Scenarios:**

1. **Given** a cleanup-acknowledged session and a stale false property, **When** the user tries
   to start again, **Then** the start is refused with `rearmNotQualified`.
2. **Given** the same state and a true property, **When** the user tries to start again,
   **Then** the property alone does not authorize re-arm.
3. **Given** an explicit re-arm qualification, **When** the user starts again, **Then** the
   normal readiness checks still apply and no prior consent or safety gate is skipped.

### Edge Cases

- The global policy is already disabled before start → refuse with `globalSleepDisabled`.
- The global policy becomes disabled during an active session → stop; do not clear it.
- The global policy is unreadable at start or during a session → fail closed with an explicit
  unknown/conflict reason; never report healthy.
- An active session has no policy observation (`notObserved`) → treat it as unreadable and stop;
  never treat absence as clear.
- The global policy returns to clear after a conflict → the old session stays stopped; a new
  start must pass all gates.
- Another actor writes the same shared lid bit → undetectable by design; the existing
  hidden-writer risk remains disclosed, not solved.
- `AppleClamshellCausesSleep` is false after a wake or cleanup → never proof of a foreign
  writer, failed clear or successful restore.
- Helper timeout, crash or restart at any point → journal/recovery state wins; no blind retry.
- Current-boot pending enable or pending restore → recovery-required; reboot guidance.
- Previous-boot unresolved journal with abnormal baseline → recovery-required.
- Manual Apple-menu Sleep → never vetoed; session terminates; no resume.
- R0 fails or is not accepted → M9 offline work is parked; no product integration is implied.
- Journal unreadable/corrupt or baseline unknown → refuse or recovery-required before mutation.

## Requirements

### Functional Requirements

- **FR-013-001** During an active best-effort session, the system MUST observe the system-wide
  sleep-disable policy read-only at a bounded cadence.
- **FR-013-002** If that observation changes from clear to disabled, the system MUST stop the
  session, attempt its own lid-policy clear at most once, release owned resources, and MUST NOT
  write or clear the global policy.
- **FR-013-003** If the observation is unreadable or unknown during an active session, the
  system MUST fail closed with an explicit reason; it MUST NOT report the session as healthy.
- **FR-013-004** A foreign-policy stop MUST be distinguishable from a user Stop, a safety stop,
  a heartbeat expiry and a clear failure in status, logs and user guidance.
- **FR-013-005** A current-boot pending enable or pending restore MUST map to
  recovery-required; the system MUST NOT attempt a blind clear or a repeat clear.
- **FR-013-006** A previous-boot unresolved journal MUST be promoted to ready only when the
  current public baseline is normal; otherwise it stays recovery-required.
- **FR-013-007** Helper unavailability, timeout or restart MUST map to an explicit refusal or
  recovery reason; the system MUST NOT claim active or cleanup success from a missing reply.
- **FR-013-008** Re-arm MUST require an explicit qualification/reboot decision. A stale or
  changing `AppleClamshellCausesSleep` value MUST NOT authorize re-arm.
- **FR-013-009** GUI and CLI MUST expose the same state, reason, receipts and guidance; no
  surface may render `Protected` or `verified` for this backend.
- **FR-013-010** Receipts and logs MUST record the reason and timing of a foreign-policy stop
  or recovery state without secrets, prompts or user content.
- **FR-013-011** All M9 verification MUST be fake-only or static. No native policy read that
  changes state, helper command, power action, app integration or shipping-gate change is part
  of this milestone.
- **FR-013-012** The M9 work MUST NOT change the actuator, add a global sleep setter, add an
  administrator-script fallback, add a second privileged watchdog or broaden the accepted
  best-effort scope.

### Key Entities

- **Foreign-policy observation:** a bounded, read-only observation of whether the global
  sleep-disable policy is clear, conflicted or unknown; not an ownership token.
- **Recovery reason:** a stable code distinguishing pending enable, pending restore, previous
  boot, helper unavailable, foreign policy and unknown state.
- **Best-effort status:** the shared GUI/CLI projection of state, reason, receipts, warnings,
  re-arm status and the always-false protection claim.
- **Re-arm qualification:** an explicit decision/evidence record, not a public-property
  reading; it can authorize a new start only after normal readiness checks.

## Success Criteria

### Measurable Outcomes

- **SC-013-001** 100 % of fake tests for clear → disabled, disabled at start, unreadable during
  a session, and clear again produce the defined stop/refusal reason; no test observes a global
  policy write by CamLid.
- **SC-013-002** 100 % of current-boot pending-enable and pending-restore cases produce
  recovery-required and reboot guidance; zero blind clear/retry calls are observed.
- **SC-013-003** 100 % of helper-unavailable/timeout fake cases produce an explicit refusal or
  recovery reason; zero cases report active or cleanup success.
- **SC-013-004** 100 % of stale-property and cleanup-acknowledged cases refuse re-arm unless
  the explicit qualification path is present.
- **SC-013-005** GUI/CLI contract tests show identical state and reasons, and a source/static
  check finds no `Protected`/`verified` claim for this backend.
- **SC-013-006** The full offline helper and best-effort test suites pass in Debug and Release,
  and no native action, install or app integration is performed by M9.

## Assumptions and Non-Goals

- **Assumption:** the read-only global policy source is the same root-domain policy already
  read at admission; its refresh behavior must be verified offline before relying on it.
- **Assumption:** R0 was accepted on 2026-10-20; M9 offline work uses that decision, while
  re-arm remains an explicit qualification input and G2/G3 still need separate approvals.
- **Assumption:** `recoveryRequired` is the correct conservative state for a foreign global
  policy that remains after CamLid's own clear; no new user-facing state is assumed unless
  tests show ambiguity.
- **Non-goal:** changing the actuator, using `pmset disablesleep`, adding an administrator
  fallback, adding a global-policy clear, or adding a separate watchdog.
- **Non-goal:** app integration (G3), native qualification (G2), shipping-gate changes, M1
  promotion, Auto/Timed/battery/background start, completion sleep, bag/sleeve use or verified
  restoration.
- **Non-goal:** detecting a foreign writer of the same shared lid bit. The hidden-writer risk
  remains disclosed.
