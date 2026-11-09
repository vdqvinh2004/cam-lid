# Feature Specification: Closed-Lid Best-Effort Mode (experimental product track)

> **SUPERSEDED for product deployment (2026-10-30):** the exclusive-create / no-adoption / one-use admission requirements in this document are replaced by the persistent-helper model of [spec 014](../014-persistent-helper/spec.md) and [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md). The mechanism described here remains as the experimental **Strict** mode, frozen. Evidence and dated records below are kept as history; per-episode approval is now an owner QA discipline, not a product requirement. No gate passed by this change.


**Feature context:** `012-closed-lid-best-effort`; documentation/design only, no branch created.
**Created:** 2026-10-19
**Status:** Design + offline model implemented (T002–T007); gated by **R0** (behavioural
same-boot clear effectiveness, native, separate approval). No app integration, native power
action, shipping-gate change or qualification is authorized by this document.
**Input:** Owner decision A — best-effort product track;
best-effort proposal §5/§7C;
v9 lab evidence.

## User Scenarios & Testing

### User Story 1 — Start a best-effort closed-lid session (Priority: P1)

A developer at an attended desk wants to keep a finite task running with the lid closed,
knowing the mode is best-effort. They attach AC, open the app, read the risk, and start the
session manually.

**Why this priority:** it is the product behaviour the lab evidence supports, and only in the
narrow attended scope.
**Independent Test:** on a qualified row with the experimental flag on, start a session on AC
with the lid open; observe `Best effort active` (never `Protected`), the finite countdown and
the risk banner; close the lid and confirm the session continues; stop and confirm the
acknowledged state.
**Acceptance Scenarios:**

1. **Given** AC, ≥20 % battery, lid open, no external display, no known foreign lid override,
   helper trusted/available, journal ready and a qualified row, **When** the user starts the
   mode, **Then** exactly one acquisition occurs, the finite cap starts, and the UI shows the
   best-effort risk state.
2. **Given** any precondition fails, **When** the user tries to start, **Then** the start is
   refused with the exact reason and no mutation/assertion is attempted.
3. **Given** a running session, **When** the user closes the lid, **Then** the session keeps
   the system awake only as long as the lease and cap allow, and the UI does not claim
   verified protection.
4. **Given** Auto or Timed is selected, **When** the user looks for this mode, **Then** it is
   not available there; no background, login-start or battery path can start it.

### User Story 2 — See the honest state at all times (Priority: P1)

The user can always distinguish "best effort active", "cleanup acknowledged (restoration
unverified)", "recovery required" and "off". No surface uses the word "Protected" or a green
shield for this backend.

**Why this priority:** the proposal's core safety rule is that acknowledgement is never mapped
to verified restoration.
**Independent Test:** walk every surface and CLI state; search for `Protected`/verified claims;
verify the warning persists for the whole active session.
**Acceptance Scenarios:**

1. **Given** an active best-effort session, **When** any UI surface or CLI status is read,
   **Then** it shows the mode name, remaining cap, unverified-restoration disclosure and the
   recovery instructions.
2. **Given** cleanup completed, **When** status is read, **Then** the state is
   `Best effort — cleanup acknowledged`, explicitly not `Verified`, not `Protected`.
3. **Given** a state with unknown clear outcome, **When** status is read, **Then** it is
   `Recovery required` and the user is told to reopen the lid and restart/reboot before
   relying on lid-close sleep.
4. **Given** a hypothetical "everything green" fake state, **When** the projection runs,
   **Then** `ProtectionEffectiveState.protected` is still unreachable for this backend.

### User Story 3 — Stop, quit and recover without silent risk (Priority: P1)

The user stops the session, quits the app, or recovers from a crash. The app records receipts,
releases what it owns, and tells the truth about what is still uncertain.

**Why this priority:** crash/cleanup failure is the accepted residual risk; the product must
make it visible and actionable.
**Independent Test:** with fakes, exercise Stop, quit, app crash, helper crash, journal write
failure and unknown clear receipt; verify states and guidance.
**Acceptance Scenarios:**

1. **Given** a running session, **When** the user stops it, **Then** the journal intent is
   written before the clear, the idle assertion is released, exactly one clear is attempted,
   receipts are stored, and the final state is acknowledged (not verified).
2. **Given** the app dies, **When** the lease expires, **Then** the helper terminates the
   session on the qualified path; on next launch the app reports the actual state and never
   auto-re-arms.
3. **Given** the clear outcome is unknown, **When** the app cannot prove the outcome, **Then**
   the state is `Recovery required`; the UI explains that closing the lid may not sleep the
   machine until a reboot, and offers no blind reset.
4. **Given** the user quits during a session, **When** quit completes, **Then** Stop semantics
   run; a failed quit path surfaces recovery on next launch.

### User Story 4 — Consent before first use (Priority: P1)

Before the first session the user reads and accepts the exact residual risks; consent is
recorded with a version.

**Why this priority:** the owner accepted these risks for the product track; every user must
see them explicitly.
**Independent Test:** fresh install; attempt to start without consent; verify refusal; accept
and verify the recorded version and the persistent banner.
**Acceptance Scenarios:**

1. **Given** no recorded consent, **When** the user starts the mode, **Then** a blocking
   consent sheet lists crash/indefinite-override, unverified restoration and hidden-writer
   risks; no start occurs without an explicit accept.
2. **Given** accepted consent, **When** a later session starts, **Then** the banner still shows
   the risks; consent is revocable in Settings.
3. **Given** a consent text/version change, **When** the app updates, **Then** consent is
   required again before the next start.

### User Story 5 — Inspect and audit the mode through the CLI (Priority: P2)

A technical user can read the same honest state, receipts and cap from the CLI.

**Independent Test:** start/stop with the GUI and read matching JSON from the CLI; verify no
`protected`/`verified` fields for this backend.
**Acceptance Scenarios:**

1. **Given** any best-effort state, **When** `status --json` runs, **Then** the mode, cap,
   receipts and residual-risk fields match the GUI.
2. **Given** the experimental flag is off, **When** the CLI is asked to start the mode,
   **Then** it refuses with the same reason as the GUI.

### Edge Cases

- Lid state unknown, external display attached, battery below floor, AC lost, thermal
  pressure non-nominal, `SleepDisabled` true/unknown, or a known foreign override → refuse or
  stop; never guess. A false/unreadable `AppleClamshellCausesSleep` is not proof of a foreign
  override (it may be stale after sleep/wake); it requires acknowledgement, not a silent pass.
- A normal sleep/wake can leave `AppleClamshellCausesSleep` false with no suppression; do not
  map that alone to `recoveryRequired` — use the journal and behaviour.
- Manual Apple-menu Sleep during a session → never veto; session terminates and does not
  resume; a qualified full-Sleep observation is required for the mode's gate.
- Reboot with a pending journal → `Recovery required`; no auto-clear, no auto-re-arm.
- Journal corruption / permission error / disk full → refuse before mutation; preserve the
  record.
- App update or uninstall with a pending journal → recovery guidance; no silent orphan.
- System time jumps or monotonic clock discontinuity → invalidate the observation; do not
  extend the cap.

## Requirements

### Functional Requirements

- **FR-012-001** The mode is experimental and off by default; it starts only from an explicit
  manual action. Auto, Timed, background, login-start and battery paths cannot start it.
- **FR-012-002** Preconditions: AC attached, battery ≥20 %, lid open, no external display,
  `SleepDisabled = false` (true/unknown refuses), helper trusted and available, recovery
  journal ready, qualified support row, recorded consent. `AppleClamshellCausesSleep` is an
  indicator, not a gate: false or unreadable requires an explicit "baseline unverified"
  acknowledgement (stale publication and a foreign writer cannot be distinguished). Any hard
  failure refuses with a stable reason code.
- **FR-012-003** A session is finite (default and v1 maximum 900 s), uses the frozen
  best-effort model (24 s leases, 10 s heartbeats, ≤30 s assertions) and never extends its cap.
- **FR-012-004** The app must expose an acknowledgement-aware state model — at minimum
  `Off/Ready`, `BestEffortActive`, `BestEffortCleanupAcknowledged`, `BestEffortRecoveryRequired`
  — and must never produce `RestoreState.verified` or `ProtectionEffectiveState.protected` for
  this backend.
- **FR-012-005** Stop/quit/safety path: journal intent before clear; one clear attempt; release
  owned assertion; store receipts; final state acknowledged or recovery-required.
- **FR-012-006** Manual Sleep is never vetoed or cancelled. A qualified sleep-related event
  terminates the session, cancels renewals and does not resume after wake.
- **FR-012-007** Completion sleep (FR-005), programmatic Sleep requests and "Sleep when done"
  are not offered in this mode.
- **FR-012-008** Consent: a blocking, versioned risk acceptance before the first start, with
  the exact residual risks; revocable; re-required after text changes.
- **FR-012-009** UI and CLI must show the same states, reasons and receipts; no surface may
  claim protection, safety or verified restoration.
- **FR-012-010** Repeated sessions on one boot are allowed **only after G1/R0 proves the
  same-boot clear behaviourally effective**. If the property republishes `true` after a lid
  cycle, normal start checks apply; if it stays stale `false`, re-arm requires a behavioural
  lid-cycle proof (the machine slept on the last close, recorded from the OS sleep log) or a
  reboot. The property alone never authorizes re-arm. Boot-time reconciliation must not require
  a root reset packet per use.
- **FR-012-011** Failure handling: app crash, helper crash/hang, journal failure, AC loss,
  thermal stop and foreign override each map to a defined state and user guidance; no silent
  ready state.
- **FR-012-012** Logs record receipts, reasons and timestamps without secrets or user content;
  retention follows the existing app policy.
- **FR-012-013** Update/uninstall must not leave an unmanaged journal; the designed path
  surfaces recovery before removal.

### Key Entities

- **Best-effort session:** one bounded acquisition with a lease token, cap, receipts and
  terminal state.
- **Acknowledgement receipt:** per-call result for clear/release; evidence, not restoration.
- **Residual-risk consent:** versioned acceptance record.
- **Recovery record:** journal state after unknown cleanup; blocks re-arm until reconciled.

## Success Criteria

- **SC-012-001** Static and test checks prove no UI/CLI path renders `Protected` or `verified`
  for this backend.
- **SC-012-002** 100 % of start paths require recorded consent and pass all preconditions in
  fake tests.
- **SC-012-003** 100 % of Stop/quit fake scenarios produce either acknowledged or
  recovery-required, with journal-before-clear and exactly one clear.
- **SC-012-004** 100 % of crash/journal-failure fake scenarios produce recovery-required and
  no auto-re-arm.
- **SC-012-005** Native G2 evidence: full system Sleep repeats (proposed ≥3 across ≥2 boots)
  with clean termination and zero unexplained darkwakes; sustained attended closed-lid
  sessions with independent progress; failure-class rows; target hardware row recorded. Failure
  of the full-Sleep criterion rejects the backend.
- **SC-012-006** GUI/CLI state parity for every state, including recovery.
- **SC-012-007** No Auto/Timed/battery/background path can start the mode (tested).

## Assumptions and Non-Goals

- **Assumption:** the shared-bit clear may be ineffective on the same boot; R0 decides whether
  the product track continues. The public property is derived policy, not a getter; behavioural
  evidence is required.
- **Assumption:** the target MacBook Air is the first support row; additional rows need their
  own evidence.
- **Non-goal:** verified restoration, green "Protected" state, Auto/Timed, battery, background
  or login start, completion sleep, bag/sleeve operation, Intel or multi-display rows.
- **Non-goal:** changing the existing preview or the shipping gate; this is a separate
  experimental mode until G3/G4 approvals.
