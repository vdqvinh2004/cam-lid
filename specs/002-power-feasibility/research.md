# Research: M1 Power and Detection Feasibility

**Current continuity-first scope:** owner revision and qualification defers panel-sleep proof and removes panel-only monitoring refusal. Historical decisions/evidence below remain unchanged; actual independent closed-lid work, mandatory safety/recovery, exact action authority and no-selected-backend status remain active. Older review/artifact pins do not qualify altered source.

**Decision**: Power backend candidates, initial agent lifecycle probes, exact support matrix and recovery topology.
**Rationale**: Backend/support matrix selected only after mandatory tests pass; persistent candidate demonstrates single-helper crash/hang recovery; otherwise STOP.
**Alternatives considered**: Keep all milestones in one feature (poor scope/dependency ownership);
copy every shared contract into every feature (drifting defaults); execute future work during
planning (outside authorization). Scoped features reference single shared product/limitation sources.

Inherited evidence: research decisions,
power sources, agent sources,
UX investigation. No new API/hardware behavior inferred by migration.

**Evidence still required**: Supervised reversible hardware matrix plus isolated fault simulation; no kernel freezing/overheating. L01–L12 and L17; every L01–L20 receives verified/conditional/residual/blocked disposition.
M0 is documentation completion; all future implementation/physical/quality/user-test evidence
remains unexecuted. Unknown backend/toolchain/provider versions are resolved by predecessor gate
or scoped validation task, never hidden as a runtime compatibility promise.

## Current backend decision — reconciled 2026-10-11 (initial 2026-10-05)

**Core closed-lid feature BLOCKED. No CamLid backend or support row selected.** Public idle assertions do not establish lid-close prevention. Persistent SleepDisabled is rejected as currently shippable; it lacks OS-owned expiry and exclusive ownership, and mandatory physical/manual-Sleep/independent-recovery evidence is absent. This is the explicit blocked outcome permitted by M1 T008, not M1 PASS. Preview-only development continues with zero power actuation.

Limited lab stages A/B/revised B/C later executed; reconciliation distinguishes initial B's terminal-unresolved result, revised B's open-lid Stop/API success and C's unqualified attempt. C has one closed-lid sample, panel awake and `lidPanelUnknownOrInconsistent`; no sustained continuity/internal-display-off or physical-restoration qualification. Current experimental source gate is false. No backend selection, milestone PASS or future action authority follows.

Decision evidence: backend comparison, recovery topology, all L01–L20 dispositions, and hardware protocol. Passive Closed samples from the user-managed LidRun session qualify neither a CamLid backend nor internal-display sleep. Future supervised candidate evidence may revise the decision; current code must not choose an alternate override.
