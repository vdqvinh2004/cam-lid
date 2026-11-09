# Conditional Power Helper Contract v1

Create only if M1 proves privileged backend necessary and recoverable. Signed SMAppService helper;
authenticated XPC clients allowlisted by designated requirement, protocol version, and user/session.
Requests: inspectCapabilities, acquireLease, renewLease, releaseLease, inspectRecovery.
No command string, arbitrary file path, arbitrary pmset key, or sensor spoofing accepted.

Lease renewal every 10 seconds; deadline ≤30 seconds after last accepted renewal.
limitations.md defines failure classes: healthy executor starts release
within 2 seconds of expiry detection, verified restoration target ≤35 seconds from last renewal;
helper crash/hang/restart or OS/power-service failures have no inherited deadline guarantee. Helper validates session epoch, cap, approved
policy limits and independently performs required health enforcement or expires on monitor loss.
Reads protected journal before arming. It rejects pre-existing global sleep override, cross-user
sessions/conflicts, unsupported version, stale telemetry, invalid ownership, or restore failure.

For global mutation: journal original state before write; verify write; bounded lease; compare
owned expected state before restore; verify restoration; mark outcome. Global OS setting offers
no atomic ownership primitive: same-value outside writes are ambiguous. M1 must document that
limitation and establish conflict refusal/recovery behavior before shipment. GUI exit cannot be
sole cleanup mechanism. Helper restart/reboot recovers old journal before new lease; update/removal
releases lease and verifies cleanup. Failed cleanup means recoveryRequired and no new protection.
Sleep request follows restoration, never bypasses unrelated assertions. Preserve user Sleep;
if selected mechanism makes this impossible and no validated workaround exists, backend fails M1.


## Required Recovery Refinement
M1 compares OS-managed expiration with persistent global state. For persistent candidate,
independently scheduled recovery must cover single-helper crash/hang; launchd restart alone
has unbounded latency and is not evidence of a 30s guarantee. Any recovery component uses
same authenticated journal and fixed restore operation; define serialization/epoch/read-back
before adoption. Suspended owner cannot indefinitely lock out cleanup. Common OS/actuator
failure still defeats all local executors. Bound IPC waits, reject unsupported protocol/build,
and require recovery readiness before mutation. No durable journal means no global write.

Restricted recoverOwnedState(dryRun/apply) available to authenticated CLI when app is unavailable;
original ownership must validate; uncertain state returns conflict/unknown, never guessed reset.
No fresh lease on recoveryRequired. Return leaseDeadline, lastRenewal, executorHealth,
releaseInitiatedAt, restoreVerifiedAt, failureClass, recoveryOutcome and reason codes as known;
null/unknown when unavailable, never fabricated timestamps. OS-update/reboot journal audit
precedes any new support check or lease. Startup cleanup latency is recorded, not promised.
