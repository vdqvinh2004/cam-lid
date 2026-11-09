# Agent Evidence Contract v1

Normalized event: schemaVersion, provider, host optional, sessionID, runID, parentRunID optional,
sequence, kind (runStarted/working/waitingForUser/idle/completed/failed/heartbeat), sourceTime,
PID/startTime optional, evidenceKind, confidence. No prompt, tool args, transcript, environment,
raw command line, or workspace text payload accepted. Limits/validation: shared domain model.

Only authenticated same-user integrations enter ingestion. Client-authentication verifies sender,
not truth of user-supplied activity; events cannot alter safety policy. Provider adapters map
versioned documented events into contract. Completion applies only to its run identity, never
all sessions. Stop hook does not imply detached work ended. Parent completion waits for tracked
children; unknown orphaned child becomes bounded unknown, not forever active.

Duplicate/reordered sequence rejected per run. Closed runs ignore stale working events; a new
run ID starts another turn. Liveness reconciles process start time/adapter session status.
Heartbeat only renews valid producer liveness; it does not turn idle into working. Lost evidence
becomes unknown, bounded per FR-008. Process-only discovery stays inferred/unknown and cannot
claim semantic completion. Network wait keeps working if lifecycle evidence and liveness valid.

Installations show config diff and preserve unrelated hooks/plugins. Never overwrite Orca-managed
hooks. M3 chooses coexistence bridge/native host signal only after source and installed-version
validation. No private Orca local API assumed to exist.

## OpenCode preview snapshot counters

The optional row `sequence` is a monotonic provider snapshot counter within a session epoch, used for deterministic duplicate-row resolution and regression rejection. It is not the CamLid normalized event sequence. Stream and reconciled snapshot emissions share one contiguous per-run CamLid counter starting at zero. A snapshot containing a regressing counter is rejected before deriving child/parent state; reconnect clears snapshot counters and last snapshot state and starts a new normalized epoch. Installed OpenCode schemas and reconnect behavior must be qualified before production integration; sources without a documented monotonic row counter must omit that optional field.

Runtime retirement refuses a run with pending out-of-order events. Capacity exhaustion rejects new enrollment rather than discarding buffered work. Policy freshness deadlines still apply while gaps remain unresolved; a buffer is not proof of current work.

OpenCode preview metadata retains at most64 session identities and64 run counters, including child/parent references. Admission fails closed before snapshot mutations when either bound would be exceeded; existing identities remain usable. Explicit `forgetSession` is owner-controlled cleanup at a confirmed lifecycle boundary, not automatic eviction or proof of idle. Installed integration must expose capacity rejection and coordinate cleanup with runtime replay history.
