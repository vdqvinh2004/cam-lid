# Awake Automation Interface Contract

**2026-10-13 owner-boundary update:** agent wrapping/producer admission is superseded by third-person observation. CLI `run`/`bridge`/`event` refuse with3/externalObservationOnly before IO/launch; app sync/async admission denies producer events/diagnostics/wrapper commands before decode. Wire denial intentionally exposes only controlDenied. Protected-command clauses below are historical, not a release prerequisite. CamLid-only diagnosis/config/history and guarded Sleep policy remain; no physical power acceptance implied.

**Status**: M8 partial implementation: status/diagnosis, Preview sleep decision/refusal, protected-run denial, alert/login settings, revision-aware `watch` editing and Preview lifetime matching/holds are implemented. Verified protection leases and physical sleep remain deferred. Native notification delivery and signed login acceptance remain open. Reuse existing CLI error/exit conventions and additive versioned JSON fields. Existing IPC authenticates peer UID and enforces <=64 KiB frames; new operations remain allowlisted, never shell/privileged command payloads.

## Status and diagnostics (US1)

`camlid status --json` adds configuredMode, activeSessionMode (null if inactive), protection and restoration. Existing saved `mode` field remains compatible and explicitly documented as configured mode; it is not proof of an active session. Capability `powerActuation=false` always precludes verified protection.

`camlid diagnose [--json]` requests one bounded read-only snapshot through existing app service. No session activation, host writes, killing blockers or notifications. App unavailable => existing transport failure with actionable message; does not auto-launch it. GUI Refresh/Cmd-R and CLI share collection/schema. Global/system/display/user-activity categories remain distinct. Aggregate or kernel flags without process attribution never invent an owner. Unknown/assertion-free does not promise physical sleep.

Snapshot schema: schemaVersion, observedAt, coverage, errors, configuredMode, activeSessionMode, protection, restoration, blockers. Coverage/truncation/errors are present even on partial success; zero usable coverage returns an existing nonzero diagnostics failure. Redacted by default in JSON/export. GUI may show local owner name/PID for explanation, without persistence.

## Display preference (US2)

Existing Configuration.allowDisplaySleep optional Boolean: missing means true. GUI preference updates through the current revision-aware per-field flow. Runtime changes update owned display assertion only, never reset finite timer/Auto delay or claim capability from an accepted config write. Lid closed => display hold off; unknown lid => requested display hold unavailable with reason. System prevention and closed-lid backend requirements remain M1/M2-owned.

## Protected commands (US3)

`camlid run --keep-awake -- <executable> [args...]` adds required safety-governed admission to existing run. Existing `camlid run -- <...>` behavior unchanged. Require running app, explicit Auto session, current safety approval, available capacity and verified backend admission **before child launch**. Timed/inactive/Preview/unsupported returns existing structured failure and launches no child.

IPC operations: admitCommand, renewCommand, finishCommand. Opaque admission identity scoped to authenticated UID + boot + Auto generation; no arbitrary duration, command string, env or stdout in payload. Job metadata contains executable display label only. Renew10s/expire30s, max20 jobs; stale/reordered/wrong-session events rejected. On revoke, CLI warns via stderr; child continues unprotected with its own eventual exit code. On pre-launch fail, nonzero CLI failure. Signal/exit/stdin/stdout/direct argv semantics remain existing RunCommand semantics; user explicitly invokes a shell for shell expressions. Completion releases only the job's contribution; no sleep inferred from detached descendants. Stop/safety generation invalidation prevents delayed re-arm.

## Lifetime rules (US4)

`camlid watch list [--json]`
`camlid watch add --executable <absolute-path> [--label <label>]`
`camlid watch add --bundle-id <installed-bundle-id> [--label <label>]`
`camlid watch remove <rule-id>`

Editing/listing rules uses existing atomic revision-aware config protocol; no new unbounded rule request endpoint. Add accepts exactly one selector kind. Bound/validation in [data model](../data-model.md). CLI returns persistent rule ID and revision or existing conflict/error. Settings has a separate Watched Programs section, preserving agent rows as CLI detection only. Dashboard adds a lifetime reason only while relevant. Bundle IDs resolve through Launch Services at add time; executable paths must exist and be executable.
During an explicitly active Auto session, the bounded native scan reads same-user process identity, exact executable path, and enclosing app bundle ID. At most 4,096 processes are examined; errors, truncation, missing paths, and stale scans remain unknown. Absence needs two complete observations at least five seconds apart. Unknown holds use the existing wait retention; a current lifetime epoch cannot prove task completion or initiate completion sleep. Stop clears the active session, and saved rules never start a new one. Preview performs no power actuation.

## Sleep (US5)

`camlid sleep --dry-run [--json]`: collect fresh inputs, return eligible plus all stable reasons; changes nothing. Allowed dry-run exits success; blocked/unknown uses existing policy-failure convention plus structured decision.
`camlid sleep [--json]`: revalidate same inputs, require verified restoration, then request through qualified M2 backend. Display and recent-input observations each carry their own monotonic sample time; either sample older than five seconds or from the future blocks admission. Preview always fails actual admission. No --force. Stable reasons include trackedWorkActive, workUnknown, inUse, displayAwake, displayUnknown, telemetryStale, displayStale, inputStale, inputUnknown, restorationUnverified, previewOnly, backendUnsupported. Another app's assertion remains an external blocker; do not release it or claim observed sleep. Actual sleep suspends command execution; report requested acknowledgement before suspension; observed outcome goes into subsequent status/history only with independent evidence.

Blocked actual requests append an existing V1 `stateTransition` history record with `sleepBlocked` followed by the exact decision blockers. No new history category or schema field is introduced. Dry-run and rejected command options append no history. Requested/observed records remain gated by qualified backend execution and independent evidence.

## App preferences (US6/7)

Notifications and launchAtLogin use existing per-field revision-aware Settings/config path; OS status is read-only supplemental state, never fake successful preference read-back. User notification authorization requested only from explicit UI enable; CLI may store intent but cannot cause a surprise permission dialog. A CLI request needing approval returns approval-required guidance; delivery stays off until actual authorization. Login registration may similarly need OS approval.

Defaults remain off for alerts/login. Startup performs existing owned recovery but does not restore active sessions. Notification copy describes policy/safety transitions, requested sleep and verified recovery accurately in Preview/live. Settings owns persistent options; Dashboard owns active mode, time and Sleep when done.

## Regression guarantees

No Start/Off/Manual buttons return. Active mode click stops. Infinite safety retained. Timer edit starts new duration now. Auto never shows Timed countdown. Mode icon remains readable in light/dark. Existing read-only diagnostics, CLI child behavior, history redaction, agent detection Settings and whole-row disclosures remain intact. See [quickstart](../quickstart.md).
