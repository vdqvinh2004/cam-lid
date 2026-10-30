# Feature Specification: Persistent Helper (Standard Mode)

**Feature context:** `014-persistent-helper`; planned, no code yet.
**Created:** 2026-10-30
**Status:** Draft. Decision: [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md).
**Supersedes for product deployment:** the admission / one-use sections of specs 012 and 013. Their evidence stays as history. This spec grants no authority to install, run root code, change power state or perform a physical episode; each native action still needs the owner's go-ahead at the time.

## Summary

Replace the blocked exclusive-create / one-use admission with a root LaunchDaemon installed once through local administrator authentication and kept installed (Standard mode). The existing lease, journal, safety and caller-authentication code is reused. The current mechanism stays as an opt-in experimental Strict mode. Only one mode may write the sleep policy at a time.

## User Scenarios & Testing

### User Story 1 — Install the helper once (Priority: P1)
A user installs the helper with one administrator authentication and does not repeat it per session.

**Acceptance**
1. Given no helper, `camlid helper install` (or the app's install action) asks for administrator rights once and ends with status `installed`, version and pinned identity shown.
2. Given a helper already installed with a different pin, install is refused with the reason; `camlid helper trust` re-authorizes after a rebuild.
3. Given a non-administrator, install is refused without changing anything.

### User Story 2 — Run a closed-lid session safely (Priority: P1)
A user starts Auto, Timed or Infinite; the Mac stays awake with the lid closed under the safety guards.

**Acceptance**
1. Start acquires a lease; the app renews it every 10 s; the helper restores if renewal stops for 30 s.
2. After every write the helper reads `SleepDisabled` back; an unreadable or unexpected value is `Unknown`, reported, never treated as `Off`.
3. Battery, thermal, AC and CPU guards stop the session and restore the policy; missing data refuses start.
4. If `SleepDisabled` is already set by something else, CamLid does not start, does not modify it and reports the owner as foreign.

### User Story 3 — Recover when the app, helper or Mac fails (Priority: P1)
**Acceptance**
1. Killing the app: the helper restores within the lease window.
2. Killing or restarting the helper: after launchd restarts it, it reads the journal and restores an expired or orphaned owned policy before accepting new work.
3. Helper hang (process alive, not responding): an independent recovery path restores the policy by the persisted deadline without the helper's cooperation.
4. Reboot with an owned record present: the policy is restored or reported `needsAttention`; it is never silently left disabled.

### User Story 4 — Uninstall cleanly (Priority: P2)
`camlid helper uninstall` stops the daemon, restores the default sleep policy if CamLid owns it, removes the plist, binary and socket, and reports what was left (journal, logs).

### User Story 5 — Choose the mode (Priority: P2)
Settings shows Standard (default) and, under an advanced section marked experimental, Strict. The Dashboard shows the active mode.

**Acceptance**
1. Switching is refused while either mode holds a lease or has an unresolved journal entry.
2. Strict being unavailable (no admitted helper) is shown as a state, not an error.

### Edge Cases
- Two CamLid clients start at once: the second is refused with a busy reason.
- Clock change or sleep during a session: deadlines use a monotonic source; wall-clock changes cannot extend a session.
- Helper binary replaced while running: pinned identity no longer matches; helper refuses commands and reports `needs re-authorization`.
- Socket reachable by other local users: connections from an untrusted peer are rejected before any parsing.
- Corrupt journal: new sessions are blocked and `needsAttention` is shown; no blind clear.

## Requirements

### Functional Requirements
- **FR-001** Install, uninstall and trust through a fixed administrator command. No arbitrary command, path or shell input.
- **FR-002** The helper authenticates every peer by code signature and pinned identity (cdhash or team requirement). UID-only trust is not accepted.
- **FR-003** Fixed operation set: `ping`, `inspect`, `acquire`, `renew`, `release`, and mode-scoped equivalents. Unknown operations are rejected.
- **FR-004** Lease 30 s, renewal 10 s, persisted deadline, monotonic time.
- **FR-005** Read-back after every write; `Unknown` is distinct from `Off`.
- **FR-006** Ownership record: CamLid restores only a policy it set. A foreign `SleepDisabled` blocks start and stops an active session.
- **FR-007** Guards: battery floor, thermal pressure, AC/battery state, CPU; fail closed on missing or stale data.
- **FR-008** Durable journal readable after restart; an unresolved entry blocks new sessions.
- **FR-009** Independent recovery path for helper hang or death, separate from the helper process.
- **FR-010** Mutual exclusion between Standard and Strict across helpers, journals and storage directories (kept separate).
- **FR-011** Uninstall restores the default policy when owned and removes installed files.
- **FR-012** User-facing text states that Standard changes the global sleep policy and is less strict than Strict.
- **FR-013** Auto, Timed and Manual drive the helper through one reconciler after the shared policy evaluation; no mode talks to the helper directly.
- **FR-014** The UI shows Protected only while the helper lease is held and read back; otherwise it shows why closed lid is unavailable.
- **FR-015** A helper refusal or stop ends the session as a safety stop or recovery conflict; the app never retries around it. Closed-lid sessions never exceed the helper's 4 h maximum and are not extended by fresh work.

### Key Entities
Helper installation (version, pin, status) · Lease (owner, expiry, renewals) · Ownership record (owned flag, enabled-at, deadline) · Journal entry · Mode (Standard | Strict) · Guard settings.

## Success Criteria
- **SC-001** Install, run, stop, uninstall completes on a clean test Mac with one authentication.
- **SC-002** Each scenario in User Story 3 restores the policy within its stated bound, measured on hardware.
- **SC-003** All guard, ownership and read-back cases pass as unit tests with injected fakes.
- **SC-004** No path leaves `SleepDisabled` set without a record and a recovery route.

## Assumptions and Non-Goals
- macOS 14 minimum, as today. Local administrator authentication is acceptable; Apple-side registration, notarization and `SMAppService` are out of scope.
- Non-goals: removing Strict code, Developer ID signing, auto-update, fan control, App Store distribution.
- Passing tests or a successful install does not pass G2/G3 or any shipping gate.
