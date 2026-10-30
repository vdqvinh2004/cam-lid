# Proposed CLI Contract v1

Preview commands are implemented where documented in README; live power/helper operations remain gated. CLI uses running app's shared policy;
reads do not launch protection or modify power. JSON stdout, diagnostics stderr, schemaVersion 1.

| Command | Behavior |
| --- | --- |
| `camlid status --json` | Mode, effective state/reason, revision, tasks, health/freshness, lease/cleanup, deadlines, support row |
| `camlid agents list --json` | Enrolled sessions, host/provider, activity, confidence, freshness |
| `camlid config get --json` | Validated preferences and active schema |
| `camlid config validate --file config.json` | Pure validation, no writes |
| `camlid config set --file config.json --dry-run` | Validate partial patch, show effective diff |
| `camlid config set --file config.json` | Atomic validated partial patch; report new revision |
| `camlid start --mode auto|timed|manual --duration 30m --closed-lid` | Explicit session; enforce cap/safety/capability; duration required for timed, optional cap for others |
| `camlid quit` | Preview-app shutdown; no owned power resources. Future backend must confirm restoration before exit. |
| `camlid stop` | Release own protection, persist reason, report cleanup |
| `camlid logs export --redacted --output events.json` | Bounded redacted export, refuse overwrite unless explicit flag |
| `camlid recover --owned-only --dry-run --json` | Restricted helper diagnosis independent of app; dry-run default |
| `camlid recover --owned-only --apply --json` | Explicit authenticated owned-journal restoration; reject uncertain ownership |
| `camlid doctor --json` | Read-only permissions/backend/integration/restore/conflict diagnosis |
| `camlid simulate --scenario scenario.json --json` | Isolated fake clock/sensors/power; host cannot be mutated |
| `camlid event --stdin` | Excluded legacy integration; exit3/externalObservationOnly before stdin or IPC |
| `camlid run -- command args...` | Excluded legacy wrapper; exit3/externalObservationOnly, never launches |

Mutation replies include accepted, revision, effectiveState, reasonCodes, cleanupOutcome.
Read status distinguishes sleepRequested/sleepObserved/blockerUnknown. Machine codes stable;
human messages may change. Exit codes: 0 success, 2 input invalid, 3 policy/capability denied,
4 app/helper unavailable, 5 recovery needed. Wrapper returns child's exit status; launch failure
126/127. CLI never prints credentials or agent content. Optional IPC connect token remains local;
no TCP listener. Helper administration still uses OS authorization flow, never CLI password args.
Concurrent writes use expectedRevision optional; conflicts return rejected change, current revision.
Simulation reports simulated=true and full transition trace. Real test fixtures require explicit
hardware harness and cannot be selected accidentally by simulate command.

## Battery preference amendment — 2026-10-15

`config validate/set` accepts `batteryModeAllowed` (Bool, default false),
`batteryEntryPercent` (Int 20...80, default 40, strictly above battery floor), and
`batteryCapMinutes` (Int 15...240, default 60). Null/wrong types refuse atomically.
`chargingOnly` remains true by default and independent of battery opt-in. Missing legacy
keys never enable battery mode; absent entry defaults to max(40, floor+1).

The inert library start path checks battery entry and bounds even Infinite to
min(runCapMinutes, batteryCapMinutes). The actual Preview app still refuses CLI start
with `backendPendingM1`; this amendment enables no host power action. **Superseded 2026-10-31 (spec 014):** `start` now starts a session through the Dashboard path; it returns exit 0 with `mode`, `closedLidPermit` and `powerActuation` (true only once the helper lease is verified), or exit 3 with `reason` (`modeOff`, `closedLidNotPermitted`, a battery entry code, `sessionAlreadyActive`, `appUnavailable`, `applicationTerminating`) and exit 2 for an invalid `--mode` or `--duration`. `stop` reports `cleanupOutcome: releaseRequested` when a lease was held; `quit` reports `helperRestoresOnDisconnect`. App status adds
`batteryModeActive` as a display-only fact, never a qualified protection claim.

## Preview transport capacity and shutdown

Same-user `control.sock` wire framing stays unchanged. At most 32 connections
retain bounded frames; header and body share one three-second deadline.
Frame reception and response writes use nonblocking I/O, separate from handlers.
Status/stop/quit/doctor have two reserved handlers; ordinary commands have six,
and export has one. Retained encoded-response reservations total at most 64 MiB:
1 MiB reserved for priority replies and 63 MiB for other replies. These are
response-byte budgets, not a process RSS limit. Writes yield every 64 KiB.

A full connection table may drop an incomplete reader or a computed read-only
reply, including its encoding/queued-write phase; admitted mutations are never
preempted. A dropped read can be retried. Limits do not guarantee availability
under arbitrary same-user priority floods, scheduler starvation or stalled
handlers. An unavailable mutation response is not proof that a change failed;
read back configuration/revision when outcome is uncertain.

Server shutdown closes owned listener/client FDs and suppresses old-generation
replies. It does not cancel/drain admitted handlers. The app closes mutation
admission and settles settings/history before stopping the transport; forced
quit explicitly reports unconfirmed pending writes.

Recovery/timing fields follow [power helper](power-helper.md) and
[shared limitations](../../../docs/planning/limitations.md); the 30-second
lease deadline is never printed as guaranteed cleanup after helper/OS failure. recover returns
verified/conflict/unknown/error with evidence and exit code 5 for unresolved recovery, 3 for
unauthorized/conflicting application. Normal policy commands still require running app;
owned recovery calls restricted helper directly. dry-run does not mutate host power state.
