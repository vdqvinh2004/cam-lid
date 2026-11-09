# Data Model: M4 Native UX and Activity History

Relevant entities: Dashboard snapshot with effective state/confidence/freshness, validated settings patch, ActivityEvent and redacted export.
Runtime fields, ranges, retention, identity, configuration and transitions are inherited from
shared domain model; scope does not redefine them.
Evidence has version/timestamp/environment, expected vs actual, source and known/unknown state.
Simulation never occupies hardware-observation field. Gate reports retain failed/blocked cases;
M7 evidence pseudonymizes users and avoids transcripts. Lease expiration never implies verified
restoration. Failure semantics follow limitations.
