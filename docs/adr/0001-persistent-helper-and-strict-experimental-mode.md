# ADR 0001: Persistent helper as the default; Strict mode kept as experimental

- **Status:** Accepted (owner direction, 2026-10-30)
- **Supersedes:** the owner "preserve invariants" decision of 2026-10-27 (exclusive-create / no-adoption and independently bound one-use admission as product deployment requirements)
- **Affects:** specs 002, 003, 012, 013; new spec 014 (planned)

## Context

CamLid keeps a Mac awake with the lid closed while AI agents work. Changing the system sleep policy needs a root helper. Since 2026-10-27 the project required the helper to be admitted through exclusive-create, no-adoption and independently bound one-use grants. Investigation (docs/research, local) found no macOS mechanism that satisfies those requirements without Apple-side registration:

- Installer packages give no exclusive-create primitive and no one-use grant.
- `SMAppService` LaunchDaemons need notarization, which the owner excludes.
- `authopen` opens one file; it is not a complete bootstrap.

The result is that the helper cannot be installed, and no closed-lid run has been possible. Meanwhile an independent implementation on the same machine (LidWalk, `cam-lid-v2`) installs a root LaunchDaemon once with administrator authentication, authenticates callers by code signature and CDHash pin, owns a persisted deadline, restores after restart and runs.

## Decision

1. **Default mode ("Standard"):** a root LaunchDaemon installed once through local administrator authentication and kept installed. No per-install or per-session one-use grant, no exclusive-create bootstrap, no Apple-side dependency (no Developer Program, notarization or `SMAppService`).
2. **Strict mode is kept as an experimental, opt-in mode.** It keeps the current mechanism (lid-only IOKit control, exclusive-create/one-use admission, per-episode approval, short attended AC-only sessions). It is frozen: no further QA investment until an admission mechanism exists. It is labelled experimental and is hidden from the default settings.
3. **Only one mode may write the shared sleep policy at a time.** Switching is refused while either mode holds a lease or an unresolved journal entry.
4. **Per-episode approval becomes a QA discipline of the owner**, not a product requirement. Existing evidence and consumed-scope records are preserved as history.

## Invariants that stay in both modes

- Caller authentication: only a validly signed CamLid app or CLI may command the helper (existing pinned XPC identity; no UID-only trust).
- Lease with heartbeat (30 s lease, 10 s renewal) and a persisted deadline; the helper restores an expired or orphaned session after its own restart.
- Read-back after every write; `Unknown` is never treated as `Off`.
- Never modify a policy CamLid does not own; detect a foreign `SleepDisabled` and stop.
- Battery, thermal, AC and CPU guards fail closed; missing data is Unknown and refuses start.
- Durable journal; an unresolved journal blocks new sessions.
- A fixed, small operation set (inspect, acquire, renew, release). No arbitrary command, path or shell input.
- A one-command uninstall that restores the default sleep policy.

## Consequences

**Positive**

- A runnable path to closed-lid use without Apple dependency.
- The admission research and the macos-auth-v3 / baseline-ack-v2 work are no longer on the critical path and can be archived.
- Installation, update and removal become ordinary, testable flows.

**Negative / risks**

- A persistent root daemon is a larger attack surface; caller authentication must be correct and tested (rejected peers, invalid signature, replaced binary).
- Standard mode writes the global `SleepDisabled` flag. If the helper and app both fail the Mac may stay awake in a bag. Mitigation is the independent recovery path below; it is not yet built.
- Without a Developer ID, trust is a locally pinned CDHash: every rebuild needs re-authorization (`helper trust`). This is awkward for contributors building from source.
- Unsigned downloads are blocked by Gatekeeper; distribution is source install or user-bypassed binaries until the owner decides otherwise.
- Replacing the safety model changes the project's stated posture; user-facing text must say plainly that Standard mode is less strict than Strict.

## Required follow-up (becomes spec 014)

1. Independent recovery when the helper hangs or dies (separate worker or scheduled job). Highest-priority safety item; neither mode has it today.
2. Installer: `helper install`, `uninstall`, `trust`; fixed-command admin prompt in the app; clean removal.
3. Restart recovery from the persisted record, matching the LidWalk behaviour.
4. Mode selection and mutual exclusion in the app coordinator and Settings; current mode visible on the Dashboard.
5. Fix the production reference plist: it has no explicit `ProgramArguments` for a lid-specific mode, and `main.swift` picks the global pmset backend on empty argv.
6. Controlled physical qualification (G2) for Standard mode: sustained closed-lid progress, manual Sleep, helper kill / app kill / reboot with a record present, low battery, thermal pressure.
7. Mark specs 012 and 013 admission and one-use sections as superseded; keep their evidence.

## Open questions

- How contributors building from source pin identity without a Developer ID (ad-hoc plus CDHash with a re-authorization command, or a locally generated key).
- Whether the historical 012/013 specs, which link to QA files that are no longer on GitHub, stay in the public repository.
- Whether Strict keeps its dedicated helper binary arguments (`--lid-specific-v1`, `--lid-specific-best-effort-v1`) or is removed from the shipped helper.

## Resolved defaults (2026-10-30, owner may override)

- **Identity without a Developer ID:** ad-hoc signing with the exact cdhash pinned at install time; `camlid helper trust` re-pins after a rebuild.
- **Historical 012/013 specs:** stay in the repository with a superseded notice; their links to local-only QA files are expected to be dead on GitHub.
- **Strict arguments:** stay in the shipped helper (`--lid-specific-*`), selected only by an explicit argument. Because both modes share one label and Mach service, only one mode's daemon is installed at a time.

## Amendment (2026-10-31): untested Macs
Owner decision (spec 014 plan D8, option D): a Mac without a qualified support row may run Standard mode after the user
explicitly accepts "untested configuration" for its exact model and macOS build; a qualified row needs no such step. The
acceptance is a user preference, never a default, and is voided by a macOS update or another Mac. All other invariants
above are unchanged. Known conflicting helpers (LidRun) are detected read-only and reported, never modified.

## Not decided here

This ADR grants no authority to install anything, run root code, change power state or perform a physical lid episode. Each native action still needs the owner's explicit go-ahead at the time. Passing unit tests or a successful install does not pass any gate.
