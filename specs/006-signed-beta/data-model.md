# Data Model: M5 Signed Beta and Updates

Relevant entities: ReleaseCandidate (build/signatures/support rows), UpdateState (current/available/offline/error/deferred), install/upgrade/remove outcome and recovery evidence.
Runtime fields, ranges, retention, identity, configuration and transitions are inherited from
shared domain model; scope does not redefine them.
Evidence has version/timestamp/environment, expected vs actual, source and known/unknown state.
Simulation never occupies hardware-observation field. Gate reports retain failed/blocked cases;
M7 evidence pseudonymizes users and avoids transcripts. Lease expiration never implies verified
restoration. Failure semantics follow limitations.
