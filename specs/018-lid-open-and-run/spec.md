# Feature Specification: v0.2 — keep awake with the lid open, command wrapper, shortcut

**Status:** Included in v0.1.0 (owner decision, 2026-11-06). Open items are in tasks.md.
**Needs:** [ADR 0006](../../docs/adr/0006-command-wrapper-amends-observer-only.md), to be written before the code for User Story 2. It amends [ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md).

## Problem

- Auto and Timed hold the Mac awake only when the closed-lid opt-in is on **and** the helper is installed (`holdDesired`, AppCoordinator around line 567). `closedLidOptIn` defaults to false (`Configuration.swift`). A new user who starts Auto gets no hold, while the README promises "Auto keeps the Mac awake while the agents you selected are working".
- LidRun Free and LidWalk keep the Mac awake with the lid open without root, through ordinary power assertions.
- `camlid run` returns `externalObservationOnly` (`Commands.swift` around line 226). `RunCommand` and its `EnrollmentSet` (max 20) exist but are not wired. Admit, renew and finish are refused with `backendPendingM1` (around line 1559).
- There is no global shortcut. LidWalk has ⌃⌥⌘K.

## Owner decisions (2026-11-05)

- **Q1 — Does this add a mode?** No new user-visible mode. The Dashboard keeps Auto, Timed and Off. Settings › Closed Lid keeps Standard and Strict. The lid-open hold is a mechanism used inside Auto and Timed. A third visible mode would add a Dashboard choice, a readiness path and a Settings pane, and would duplicate Auto and Timed.
- **Q2 — Command wrapper?** Yes. ADR 0006 amends ADR 0002: agents stay observed, with no hooks and no wrappers inside agents. The wrapper holds only for a command the user starts explicitly.

## What changes in the app

| Area | Change | Risk and handling |
|---|---|---|
| Hold logic (`holdDesired`) | Lid open → assertion; lid closed → helper path (unchanged) | Users with closed-lid off now get holds. Release note required |
| Untested-Mac gate (`closedLidAllowed`) | Applies to closed-lid holds only | None for lid open |
| Settings › Closed Lid | Label "Keep awake with the lid closed" kept; it now controls only the helper path. Help text states what happens when the lid closes without it | Copy review |
| Dashboard | Notice "Closing the lid sleeps this Mac" when a session runs without closed-lid | Copy review |
| Readiness | New evidence `assertionVerified`; lid-open protected does not require closed-lid intent | Precedence tests updated |
| Sleep diagnostics | CamLid's own assertion labelled "CamLid" and not counted as "another app" | Test |
| `camlid sleep` decision | Inputs unchanged (display state, idle time); the own assertion is not a blocker | Test |
| Configuration | No new field; `closedLidOptIn` keeps its stored meaning | No migration |
| CLI | `run` wired; admit, renew, finish implemented; `start` shows the lid-open hold | Additive contract |

## User Scenarios & Testing

### User Story 1 — Auto keeps a lid-open Mac awake without root (P1)

1. Lid open, helper not installed, closed-lid off. Start Auto with an agent working. `pmset -g assertions` lists a CamLid `PreventUserIdleSystemSleep` while work runs.
2. Work ends; after the sleep delay the assertion is gone and the Mac may sleep.
3. `kill -9` on the app: the assertion is gone within 5 seconds.
4. `SleepDisabled` stays 0 throughout.

### User Story 2 — A wrapped command keeps the Mac awake and behaves like the command (P1)

1. `camlid run -- sh -c 'exit 7'` exits 7; stdin, stdout and stderr pass through.
2. The hold is visible while the command runs and gone after it.
3. App not running: exit 4, reason `appUnavailable`, command not started.
4. A safety stop during the command: the command keeps running, the hold ends, and the CLI reports `holdEnded: safety`.

### User Story 3 — One shortcut starts and stops Auto (P2)

⌃⌥⌘K starts Auto when stopped and stops it when running, with another app in front, with no permission prompt.

### User Story 4 — Agent detection is calibrated (P2)

One recorded calibration run per agent (Claude Code, Codex, OpenCode) in the QA addendum. Thresholds change only with a recorded run. A fixture records the rule that a CPU-busy process which is not a recognised agent is not Working (ADR 0002).

## Requirements

- **FR-001** Auto and Timed create `PreventUserIdleSystemSleep` while the lid is open. No helper, no administrator prompt, `SleepDisabled` untouched. The display assertion is not included.
- **FR-002** Read the assertion back with `IOPMCopyAssertionsByProcess` for CamLid's process before reporting protected. A failed read is *unverified*, never protected.
- **FR-003** Release at session end, at a safety stop, at app quit, and at process death (the OS releases a process's assertions).
- **FR-004** Closed lid: the helper path is unchanged; the untested-Mac gate applies there only.
- **FR-005** `camlid run -- <command>` holds the Mac awake while the child runs. It passes stdin, stdout, stderr and the exit code through, forwards SIGINT and SIGTERM to the child, and stores no argv or output. Activity records exit status, duration and whether the hold was active.
- **FR-006** App not running → exit 4, reason `appUnavailable`, command not started. No unprotected fallback. LidRun's wrapper works without the app; this difference is deliberate.
- **FR-007** Safety stops end the hold, never the child process.
- **FR-008** Admit, renew and finish over the existing IPC commands. Owner = CLI process id and user id. Renewal every 10 s, expiry 30 s, at most 20 concurrent admissions, one-use receipts (`AutomationModels`).
- **FR-009** ⌃⌥⌘K toggles Auto. Carbon hot key; no Accessibility permission; fixed binding in this version.
- **FR-010** Calibration as in User Story 4.

## Success Criteria

- **SC-001** User Story 1 passes on the installed build with no helper installed.
- **SC-002** User Story 2 passes; exit codes preserved in five sample commands.
- **SC-003** Closed-lid trials S1–S4 repeated with no regression.
- **SC-004** ADR 0006 accepted before the code for FR-005.

## Open questions

- **Q-C — `camlid run` with the lid closed. Decided 2026-11-05: yes, with the default.** Allowed only when the closed-lid helper path is enabled and healthy. Otherwise the hold is lid-open only, and the CLI says so.
- **Q-D — Display sleep. Decided 2026-11-05: default.** Not in v0.2; the display assertion stays off, as today.

## Out of scope

- Audio holds (see 019, research first). Configurable shortcut. Fan control. Webhooks. Smart Rules.
