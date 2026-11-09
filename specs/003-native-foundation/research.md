# Research: M2 Native Foundation and Safety

**Decision**: Native targets, shared policy/entities/configuration, telemetry, conditional power/recovery helper, CLI/simulator.
**Rationale**: Safety, journal, recovery and CLI foundation verified; no unsafe live protection; full native dashboard parity deferred to M6.
**Alternatives considered**: Keep all milestones in one feature (poor scope/dependency ownership);
copy every shared contract into every feature (drifting defaults); execute future work during
planning (outside authorization). Scoped features reference single shared product/limitation sources.

Inherited evidence: research decisions,
power sources, agent sources,
UX investigation. No new API/hardware behavior inferred by migration.

**Evidence still required**: Shared policy/contract simulator and supervised physical backend tests; safety complete before any live protected demo. L02–L09, L11–L14, L16–L19; OS/joint failures remain residual.
M0 is documentation completion; all future implementation/physical/quality/user-test evidence
remains unexecuted. Unknown backend/toolchain/provider versions are resolved by predecessor gate
or scoped validation task, never hidden as a runtime compatibility promise.
