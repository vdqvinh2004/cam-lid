# Data Model: M8

Extend existing Configuration, status and NormalizedEvent conventions. No database or new generic event bus. All durations use continuous elapsed time; wall time is presentation only.

## DiagnosticSnapshot / DiagnosticBlocker (US1)

Snapshot: schemaVersion, observedAt, coverage per category (complete/partial/unavailable), structured errors, configuredMode, activeSessionMode (nullable), protection (preview/unsupported/requested/verified/restoring/failed), restoration, and blockers.
Blocker: assertion type, effect (systemIdle/displayIdle/userActivity/global/kernel/unknown), source, optional owner executable name/PID, safe explanation code. Arbitrary assertion labels/output are not persisted/exported; owner names/PIDs redacted by default. Missing owner remains unknown. Unknown effects are not classified as harmless.

Validation: **5-second total deadline; 64 KiB combined subprocess output; at most 256 owner rows; one in-flight collection**. Bounds exceeded => partial coverage plus reason. IPC diagnostics response remains <=64 KiB including encoded overhead; trim rows to fit and mark truncation. Raw output stays ephemeral and is discarded after parsing. No argv/environment/window titles or prompt/output capture.

## CommandAdmission (US3)

Fields: opaque admissionID, explicit Auto sessionID/generation, bootID, authenticated UID, receipt sequence, last renewal/deadline, direct-child identity if launched, state/revocationReason. CLI transport owner is already same-user authenticated; no new global token service.

Validation: **at most 20 concurrent admitted jobs; renewal every 10 seconds; 30-second ownership expiry**; sequence strictly increasing within matching boot/session/generation. Expired/revoked admissions cannot renew or finish another job; a new command invocation requires fresh admission. Tokens never logged/exported. No arbitrary client-supplied lease duration.

Transitions: requested -> denied OR admitted -> childRunning -> childExited -> released. Any admitted state -> revoked/expired -> released. Failed spawn releases admission. Timed/no session rejects admission; no auto mode activation or preference edits. Safety/Stop/owner loss revokes all affected admissions but never terminates child processes. Crash cleanup delegates to M2.

## LifetimeRule / LifetimeMatch (US4)

Rule: ID, enabled, selectorKind (exactExecutablePath/applicationBundleID), selectorValue and user-visible label. Validation: **at most 20 rules; selectorValue 1–1024 UTF-8 bytes; label 1–80 characters; duplicates by kind/value rejected**. Executable selector must be absolute, normalized and not a root/directory; app selection must resolve to an installed bundle identity. Reject wildcards, regex and generic OS/system targets; no regex parser. Path changes yield unknown/unavailable, never loose basename fallback. Import/edit validates metadata again; no symlink-only trust for ownership. Same UID matches only.

Match identity: PID + processStartTime + UID, matched selector, observedAt and presence (present/absent/unknown). **At most 4096 processes per observation; two complete absent observations at least 5 seconds apart** establish absence. Truncation/error/staleness -> unknown. Unknown hold bound reuses existing waiting policy; reaching its bound releases its contribution without requesting completion sleep. Active lifetime contribution suppresses Auto completion sleep for its current work epoch, including after absence; a distinct epoch with exact task evidence can later become eligible. AI task events remain separate.

Persistence: optional rules field; missing => empty. Disabled rule keeps its saved selector without creating a hold. Existing atomic revision checks resolve concurrent GUI/CLI edits. Persistent editing does not arm Auto.

## SleepDecision (US5)

Fields: evaluatedAt, dryRun, blockers[] (stable reason codes), lid/display/input/work coverage and age, restoration, backendCapability, eligible, outcome (notRequested/requested/observed/blocked/unknown).

Validation: **all admission inputs at most 5 seconds old; no user input for at least 60 seconds**. Closed lid OR all connected displays confirmed asleep; zero active/waiting/unknown task or lifetime contributors; verified restoration; qualified backend. Zero displays without qualified lid/physical evidence is unknown, not asleep. Revalidate immediately before request; dry-run permission cannot be reused as a token for later sleep. Backend acknowledgement is requested, not observed.

## NotificationPreferences / DeliveryIdentity (US6)

Optional enabled categories: completion/failure/safety/restoration; missing => all off. Actual permission (notDetermined/authorized/denied/provisional/unknown) is queried, not persisted as authoritative. Delivery key: sessionID + eventID + category + reason. Non-session errors use a bounded event generation; restart must not replay old Activity records as new alerts.

Validation: **at most 5 ordinary alerts per rolling 10 minutes; first critical safety/restoration alert per distinct reason/session bypasses ordinary budget; replay duplicates suppressed**. Dedup retention bounded to current/recent session window using existing bounded history identifiers; no unbounded process cache. Payloads use fixed reason templates with no argv, transcripts, identifiers or command output.

## LoginRegistration (US7)

Existing launchAtLogin Boolean remains intent; missing => false. Actual state: enabled/requiresApproval/notRegistered/notFound/error, refreshed from OS. No persisted active session or backend ownership derived from this preference. Register/unregister failure retains explicit unsatisfied intent/error. Uninstall removes owned registration via M5 flow; never edits OS state belonging to another app.
