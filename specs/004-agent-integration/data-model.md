# Data Model: M3 Agents and Orca Integration

Relevant entities: AgentTask/run generation, normalized evidence sequence/host/provider, integration enrollment/config diff and compatibility row.
Runtime fields, ranges, retention, identity, configuration and transitions are inherited from
[shared domain model](../../docs/planning/domain-model.md); scope does not redefine them.
Evidence has version/timestamp/environment, expected vs actual, source and known/unknown state.
Simulation never occupies hardware-observation field. Gate reports retain failed/blocked cases;
M7 evidence pseudonymizes users and avoids transcripts. Lease expiration never implies verified
restoration. Failure semantics follow [limitations](../../docs/planning/limitations.md).
