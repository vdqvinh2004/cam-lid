# Tasks: M6 AI Quality Gate

**Input**: spec.md, plan.md, research.md, data-model.md, relevant contracts.
**Status**: Preview verification passes; T001 remains partial until integrated GUI/backend agreement is verified. T002–T005 remain open. M6 has not passed.
**Format**: Local T### IDs; [US#] refers to this milestone spec; [P] independent files after prerequisites.

## Phase 1: Setup prerequisites

Use prerequisite milestone evidence (M2, M3, M4, M5); no separate setup task is added for already-owned work.

## Phase 2: Foundational prerequisites

Shared constitution, product requirements and limitation register apply; dependent milestone gates must pass before scoped work.

## Phase 3: User Story 1 — Audit integrated quality

**Independent Test**: CLI/GUI contracts, safety/security/privacy/recovery, performance, native computer-use and physical evidence audited; zero critical/high defects.

- [~] T001 [US1] Add contract checks for schema, exit codes, revisions, invalid configs, trust/payload bounds, unavailable/recovery states and GUI agreement in Tests/Contracts/CLITests.swift (FR-017, SC-004). Implemented as Packages/CamLidCore/Tests/CamLidCLITests/CLITests.swift (runnable SwiftPM target covering the same contract surface). — **2026-11-03 cleanup:** Superseded (ADR 0004): the CLI contract is covered by the test suites.
- [~] T002 [P] [US1] Measure idle CPU/RSS and 30 dashboard opens, validate hidden-UI polling/log floods, record reference hardware in docs/qa/performance-report.md (SC-005). — **2026-11-03 cleanup:** Superseded: performance was observed during the trials (idle CPU about 0-1 percent of a core); no formal report is planned.
- [~] T003 [US1] Run independent AI contract/safety/recovery/privacy/security review and native computer-use walkthrough; audit integrated physical rows in docs/qa/ai-quality-report.md (FR-020, SC-006). — **2026-11-03 cleanup:** Superseded by the owner-attended trials and public source (ADR 0004).
- [~] T004 [US1] Audit all L01–L20 and update readiness/revoked approval/uninstall/version mismatch plus candidate recovery failure reruns in docs/qa/ai-quality-report.md; document joint/OS-hang residuals instead of solved claims (FR-022, FR-023, FR-024, SC-008). — **2026-11-03 cleanup:** Superseded (see T003).
- [~] T005 [US1] Resolve all critical/high findings, rerun affected checks and record PASS before user trial in docs/qa/ai-quality-report.md (SC-006). — **2026-11-03 cleanup:** Superseded (see T003).

## Dependencies & Execution Order

Prerequisites: M2, M3, M4, M5. Tasks in setup/foundation precede story work. Tasks inside each story stay ordered unless [P] explicitly marks separate files.
M2 safety story completes before live power tests in M2 power story; policy/simulator can run before physical arming.
M3 adapters [P] depend on shared evidence normalizer. M4 may overlap M3 on simulated policy; M5 needs both.
M6 consumes integrated M2–M5; only M6 PASS enables M7. No future gate is complete from document checks.

## Parallel Opportunities

Only tasks explicitly marked [P] may run concurrently after prerequisites; serialize shared power/journal mutations.
Independent story validation follows spec.md; multi-story milestone joins its stories at exit gate.

## Implementation Strategy

PASS report with no critical/high defects or failed mandatory limitation gate; otherwise M7 blocked.
Current authorization permits scoped preview implementation and QA; external publication remains unauthorized.

## Preview verification (2026-10-05)

T001 partial: library contracts plus real socket/app-state/CLI binary tests now exist; complete integrated GUI/backend agreement remains unverified. T002–T005 remain open: no physical/signing/accessibility/performance gate can be inferred from preview tests.

- [x] T006 Add scripts/verify-preview.py: isolated Swift tests/Debug/Release builds/actual CLI integration/read-only preflight, evidence logs and source hash manifest, explicit M1/M6-not-passed fields.

## Added M4a dependency (2026-10-05)

[Apple HIG UI/UX milestone](../009-apple-hig-ux/spec.md) is required before this milestone final approval. Preparation may overlap; the accepted candidate must include M4a evidence and no unresolved critical/high UX finding. M4a does not replace M1 physical recovery or other existing gates.
