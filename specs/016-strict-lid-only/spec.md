# Feature Specification: Strict mode, lid-only, on the persistent helper

**Feature context:** `016-strict-lid-only`; draft, no code yet.
**Created:** 2026-10-31
**Decision:** [ADR 0003](../../docs/adr/0003-strict-mode-lid-only-on-the-persistent-helper.md) (accepted 2026-10-31).
Evidence: attended experiments E1–E4 and E6 on Mac17,3 / 26A434, summarised in ADR 0003.

## Problem
Standard keeps a closed Mac awake by writing the global `SleepDisabled` preference. It blocks every kind of sleep,
survives a restart if a restore is missed (trial 7), and does not sleep a closed Mac when restored (trial 8). Strict
blocks only lid-close sleep through a kernel bit that a restart clears and whose clearing sleeps a closed Mac by
itself. Strict has existed only as frozen code behind an admission path that cannot run.

## Approach
The helper that Standard installs once gains a second mechanism. Each session's lease names the mechanism. The
Strict mechanism sets the root-domain clamshell bit (selector `kPMSetClamshellSleepState`) and holds a
`PreventUserIdleSystemSleep` assertion with an OS timeout; it re-sets the bit at every renewal and clears both at the
end. The journal records the mechanism, so the helper and the recovery job know what to undo.

## User Scenarios & Testing

### User Story 1 — Choose Strict and keep a closed Mac awake (Priority: P1)
1. On a Mac with a qualified Strict row and the helper installed, Settings › Safety lets the owner choose
   Strict (experimental). On any other Mac, Strict shows as unavailable with the reason.
2. A Timed or Auto session in Strict keeps the Mac awake with the lid closed. `SleepDisabled` stays 0 throughout.
3. When the session ends with the lid closed, the Mac sleeps (through the kernel's clamshell path).
4. Apple menu › Sleep still sleeps the Mac during a Strict session.

### User Story 2 — Failures leave a Mac that can sleep (Priority: P1)
1. If the app quits, crashes or hangs, the helper clears the bit within the lease time (30 s).
2. If the helper dies, the recovery job clears the bit for an orphaned Strict record within its interval.
3. After a restart, nothing of a Strict session remains and no recovery is needed.

### User Story 3 — An interruption is explained (Priority: P2)
If macOS clears the bit during a session (for example powerd after a display change) and the closed Mac sleeps, the
session stops with "Interrupted by the system" instead of ending silently.

### Edge cases
- Battery power without battery sessions allowed (or below the stop level), external display at start, or lid
  closed at start: Strict refuses to start, with a reason. On battery, it stops by itself below the stop level.
- An external display connected during a session: the kernel keeps a docked Mac awake on its own; the session goes on.
- Switching mode while a lease or an unresolved journal entry exists: refused (existing rule).
- A macOS update: the build no longer matches the Strict row, so Strict becomes unavailable until requalified.
- No read-back exists: a failed set shows up only as the Mac sleeping on lid close (fails safe).

## Requirements
- **FR-001** `PowerRequest` carries the mechanism (`standard` | `strict`); a request without it means `standard`
  (old clients keep working).
- **FR-002** The helper holds at most one lease of either mechanism; the journal records the mechanism of every
  enable and restore.
- **FR-003** Strict apply: create the idle assertion (timeout = lease + 6 s, release on timeout), then set the bit.
  Renewal: set the bit again and extend the assertion. Clear: clear the bit, release the assertion. Clearing is
  unconditional and idempotent.
- **FR-004** Strict admission: the charger, or battery above the stop level when battery sessions are allowed
  (amendment 2026-11-01), no external display, lid open, the existing battery/thermal/CPU guards, and
  no foreign `SleepDisabled`.
- **FR-005** The recovery job clears the bit for an orphaned Strict record (lease expired, owner gone) and journals
  the restore. A Strict record from a previous boot is acknowledged as restored without a write.
- **FR-006** The helper observes system sleep during a Strict lease and ends it with reason `systemSleptWhileHeld`.
- **FR-007** After a Strict restore the helper does not send its own sleep request (the kernel sleeps a closed Mac).
- **FR-008** Qualified support rows are kept per mechanism. Strict has no "untested configuration" acceptance.
- **FR-009** Settings › Safety offers Strict only when available, labelled experimental, with text naming its limits.
  The Dashboard shows the active mode.
- **FR-010** The frozen `--lid-specific-*` arguments, `LidSpecificMechanism` admission path and the
  `CamLidPowerHelperLidSpecific` storage stay untouched; the product path does not use them.

## Success Criteria
- **SC-001** Unit tests cover FR-001 to FR-008 with fakes; the full suites pass.
- **SC-002** Attended trials on Mac17,3 / 26A434 in Strict: Auto with a real agent and the lid closed (as trial 8),
  app kill, helper kill, restart during a session; each leaves `SleepDisabled` 0 and the Mac able to sleep.
- **SC-003** E5 (powerd interference) is recorded as an observation, not a gate.

## Out of scope
Untested-Mac acceptance for Strict, removing the frozen code, Developer ID signing.
