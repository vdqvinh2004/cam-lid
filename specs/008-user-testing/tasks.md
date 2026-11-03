# Tasks: M7 Supervised Real User Testing

**Input**: spec.md, plan.md, research.md, data-model.md, relevant contracts.
**Status**: In progress; T001 test-plan draft complete in docs/qa/user-test-plan.md. T002–T003 blocked on M6 PASS; no users recruited, no trials run.
**Format**: Local T### IDs; [US#] refers to this milestone spec; [P] independent files after prerequisites.

## Phase 1: Setup prerequisites

Use prerequisite milestone evidence (M6); no separate setup task is added for already-owned work.

## Phase 2: Foundational prerequisites

Shared constitution, product requirements and limitation register apply; dependent milestone gates must pass before scoped work.

## Phase 3: User Story 1 — Validate real coding workflows

**Independent Test**: Five consenting users; at least 4/5 identify reason/change mode unaided within 60s; all complete supported-agent/Orca session; faults triaged.

- [x] T001 [US1] Prepare five-user anonymized script, supported per-device checks and emergency Stop/rollback procedure in docs/qa/user-test-plan.md (FR-021, SC-007). Plan draft only; execution awaits M6 PASS.
- [~] T002 [US1] Run supervised supported-agent/Orca trials; measure unaided reason/mode comprehension within 60s and end-to-end completion in docs/qa/user-test-report.md (SC-007). — **2026-11-03 cleanup:** Superseded: user testing happens through GitHub issues on the pre-release (ADR 0004).
- [~] T003 [US1] Triage findings, stop on safety/recovery faults and require relevant M6 regression rerun before wider release; record release recommendation in docs/qa/user-test-report.md (SC-006, SC-007). — **2026-11-03 cleanup:** Superseded (see T002).

## Dependencies & Execution Order

Prerequisites: M6. Tasks in setup/foundation precede story work. Tasks inside each story stay ordered unless [P] explicitly marks separate files.
M2 safety story completes before live power tests in M2 power story; policy/simulator can run before physical arming.
M3 adapters [P] depend on shared evidence normalizer. M4 may overlap M3 on simulated policy; M5 needs both.
M6 consumes integrated M2–M5; only M6 PASS enables M7. No future gate is complete from document checks.

## Parallel Opportunities

Only tasks explicitly marked [P] may run concurrently after prerequisites; serialize shared power/journal mutations.
Independent story validation follows spec.md; multi-story milestone joins its stories at exit gate.

## Implementation Strategy

User metrics recorded; no unexplained safety/restore failure; any fix requires relevant M6 rerun before wider trial.
Current authorization permits scoped preview implementation and QA; external publication remains unauthorized.
