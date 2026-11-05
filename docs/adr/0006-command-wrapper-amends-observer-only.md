# ADR 0006: `camlid run` may keep the Mac awake for an explicit command (amends ADR 0002)

- **Status:** Accepted (owner decision Q2, 2026-11-05)
- **Affects:** `RunCommand`, `camlid run`, the admission IPC (`admitCommand`, `renewCommand`, `finishCommand`),
  `AppCoordinator`, Activity, spec 018
- **Amends:** [ADR 0002](0002-observer-only-agent-activity.md), Decision 1 (no wrappers). Agents are still observed and
  never wrapped; this ADR adds one explicit, user-started wrapper.

## Context

ADR 0002 keeps agent activity observer-only: CamLid installs nothing inside an agent, reads only external metadata,
and never treats a running process as proof of work. That rule stays.

Users also want a way to keep the Mac awake for one command they start themselves, without an agent. LidRun offers
this with its CLI. CamLid had `camlid run`, which only sent observation events, and the app refused it with
`externalObservationOnly`.

## Decision

1. `camlid run -- <command> [arguments]` may hold the Mac awake while that command runs. The hold is a session under
   the same safety policy as Auto and Timed: battery floor, thermal pressure, lid readings, and the time limit.
2. Agents stay observed-only. Nothing is installed in an agent or its configuration, and `run` is never applied to
   an agent implicitly. Only the command the user typed is wrapped.
3. The app must be running. Without it, `camlid run` exits 4 with `appUnavailable` and does not start the command.
   There is no unprotected fallback.
4. A safety stop or the time limit ends the hold, never the command. The CLI reports the end (`holdEnded` with its
   reason) and still returns the command's exit status.
5. Nothing is persisted from the command: no argv, environment, or output. Activity records the exit status, the
   duration, and whether the hold was active.
6. Admission: the owner is the CLI process (pid and user id). The CLI renews every 10 seconds; an admission without a
   renewal for 30 seconds ends. At most 20 admissions run at once. A receipt is valid for one admission only.
7. `camlid run` does not report task events to the app. Its admission is its only signal, so an external process
   cannot make an agent look like work.

## Consequences

- Closed-lid behaviour is unchanged. The helper path (ADR 0001, 0003) is used only when the closed-lid setting is on
  and the helper is healthy. Otherwise a `run` holds only while the lid is open, and the CLI says so.
- Users who expect LidRun's wrapper to work without CamLid running get an exit 4 instead. That is deliberate.
- ADR 0002 is otherwise in force.

## Implementation (2026-11-05)

- Admission reuses `CommandAdmissions` (receipts, uid and instance checks, 20 jobs, 10 s renewal, 30 s ownership) and
  `PolicyEngine.mayAdmitCommand` (Auto sessions only). An admitted command holds an Auto session through the policy's
  `lifetimeHoldReason`, as `"commandRunning"`.
- `camlid run` starts an Auto session when none runs. The saved mode is never changed.
- Refusals come back as replies with a reason, as `camlid start` replies do. The wire keeps only the denial class, so a
  thrown reason would reach the CLI as `controlDenied`.
- Renewal and finish are read before the options decode. Their payloads are not CLI options.

## Verification

Spec 018, User Story 2: exit status and standard streams pass through; the hold is visible while the command runs and
gone afterwards; app not running gives exit 4 without starting the command; a safety stop ends the hold and not the
command.
