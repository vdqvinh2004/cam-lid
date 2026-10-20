# Tasks: M5 Signed Beta and Updates

**Input**: spec.md, plan.md, research.md, data-model.md, relevant contracts.
**Status**: Preparation implemented; T001/T002 remain open until signed/integrated acceptance. Component work tracked below.
**Format**: Local T### IDs; [US#] refers to this milestone spec; [P] independent files after prerequisites.

## Phase 1: Setup prerequisites

Use prerequisite milestone evidence (M2, M3, M4); no separate setup task is added for already-owned work.

## Phase 2: Foundational prerequisites

Shared constitution, product requirements and limitation register apply; dependent milestone gates must pass before scoped work.

## Phase 3: User Story 1 — Check and defer updates

**Independent Test**: Current/available/offline/error states; active protection defers update installation.

- [ ] T001 [US1] Implement update status and safe deferral via Sparkle in Packages/CamLidCore/Sources/CamLidApp/UpdateController.swift; pin dependency in CamLid.xcodeproj/project.pbxproj (FR-019).

## Phase 4: User Story 2 — Install and remove safely

**Independent Test**: Fresh signed/notarized install, denial, migration, helper mismatch, OS build change, tampered update rejection and uninstall cleanup verified.

- [ ] T002 [US2] Configure signed/notarized beta and optional helper install/remove/migration; document tampered update rejection and fresh install/denial/upgrade/uninstall in docs/qa/packaging-report.md (FR-013, FR-019).

## Dependencies & Execution Order

Prerequisites: M2, M3, M4. Tasks in setup/foundation precede story work. Tasks inside each story stay ordered unless [P] explicitly marks separate files.
M2 safety story completes before live power tests in M2 power story; policy/simulator can run before physical arming.
M3 adapters [P] depend on shared evidence normalizer. M4 may overlap M3 on simulated policy; M5 needs both.
M6 consumes integrated M2–M5; only M6 PASS enables M7. No future gate is complete from document checks.

## Parallel Opportunities

Only tasks explicitly marked [P] may run concurrently after prerequisites; serialize shared power/journal mutations.
Independent story validation follows spec.md; multi-story milestone joins its stories at exit gate.

## Implementation Strategy

Distribution trust and owned-state cleanup verified before external test; unresolved recovery prevents installer/removal success claims.
Current authorization permits scoped preview implementation and QA; external publication remains unauthorized.

## Added M4a dependency (2026-10-05)

[Apple HIG UI/UX milestone](../009-apple-hig-ux/spec.md) is required before this milestone final approval. Preparation may overlap; the accepted candidate must include M4a evidence and no unresolved critical/high UX finding. M4a does not replace M1 physical recovery or other existing gates.

## Authorized preparation components (2026-10-05)

These tasks decompose T001/T002 preparation; checking them does not close the parent acceptance tasks.

- [x] T003 Implement and pin Sparkle 2.10.0 information-only driver, eligibility/safety/state controller, native Updates window/menu and shared CLI status; verify component deferral/retry/late-result/no-trust cases (T001 preparation).
- [x] T004 Add signed-candidate xcconfig, safe local bundle audit/archive tool and meaningful packaging regressions; prove preview cannot become beta and output overwrite refuses (T002 preparation).
- [x] T005 Verify fresh native Updates unavailable state, GUI/CLI agreement, framework embedding and source-hashed Debug/Release builds; record actual versus stub/blocked cases in docs/qa/packaging-report.md.

T001 pending: actual signed current/available/offline/error feeds and integrated protected-work install deferral. T002 pending: real Developer ID/notarization/feed key, tampered signed update, fresh install/denial/upgrade/uninstall/migration and conditional selected-helper lifecycle. M1/M4a prerequisites remain open; no external publication authorized.

Preparation evidence: 187 Swift tests (121 Core/42 CLI/24 App), five Python packaging tests, seven verifier checks, stable source hashes, Debug/Release metadata and embedded Sparkle checks; native unavailable window plus actual CLI agreement; local preview ZIP integrity and overwrite refusal. No real update feed contacted, installed update, notarization, selected power helper or signed beta acceptance. T001/T002 intentionally remain open.
