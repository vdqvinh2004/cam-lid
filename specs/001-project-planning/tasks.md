# Tasks: M0 Project Planning

**Input**: spec.md, plan.md, research.md, data-model.md, relevant contracts.
**Status**: Complete: documentation only. Planning migration only; all M1–M7 tasks remain unchecked.
**Format**: Local T### IDs; [US#] refers to this milestone spec; [P] independent files after prerequisites.

## Phase 1: Setup prerequisites

Installed Spec Kit 1.0.7 and existing user requirements; completion recorded in planning story tasks.

## Phase 2: Foundational prerequisites

Shared constitution, product requirements and limitation register apply; dependent milestone gates must pass before scoped work.

## Phase 3: User Story 1 — Planning artifacts

**Independent Test**: All linked planning artifacts and eight prerequisite checks pass; no runtime claim.

- [x] T001 [US1] Initialize Spec Kit 1.0.7 and project governance in .specify/memory/constitution.md (DOC-001).
- [x] T002 [US1] Capture source research and shared product/architecture/limitation decisions in docs/planning/product-spec.md and docs/research/ (DOC-002).
- [x] T003 [US1] Define native UX direction in design-system/camlid/MASTER.md (DOC-002).
- [x] T004 [US1] Split M0–M7 into eight specs folders and validate migration/coverage in docs/planning/planning-review.md (DOC-001, DOC-SC-001).
## Dependencies & Execution Order

Prerequisites: None. Tasks in setup/foundation precede story work. Tasks inside each story stay ordered unless [P] explicitly marks separate files.
M2 safety story completes before live power tests in M2 power story; policy/simulator can run before physical arming.
M3 adapters [P] depend on shared evidence normalizer. M4 may overlap M3 on simulated policy; M5 needs both.
M6 consumes integrated M2–M5; only M6 PASS enables M7. No future gate is complete from document checks.

## Parallel Opportunities

Only tasks explicitly marked [P] may run concurrently after prerequisites; serialize shared power/journal mutations.
Independent story validation follows spec.md; multi-story milestone joins its stories at exit gate.

## Implementation Strategy

Documentation and milestone structure validated; no feasibility/runtime pass claimed.
Current authorization permits scoped preview implementation and QA; external publication remains unauthorized.
