# CamLid Milestone Specs

One scoped Spec Kit feature folder per milestone; requested project convention. Spec Kit uses
feature folders and one selected feature context; it does not itself require milestones as folders.
[Shared roadmap](../docs/planning/roadmap.md) defines cross-feature gates and detailed procedures.

- [M0: Project Planning](001-project-planning/spec.md) — Complete: documentation only.
- [M1: Power and Detection Feasibility](002-power-feasibility/spec.md) — Planned; next active milestone.
- [M2: Native Foundation and Safety](003-native-foundation/spec.md) — Preview components implemented; live backend gate awaits M1.
- [M3: Agents and Orca Integration](004-agent-integration/spec.md) — Parser/runtime preview in progress; installed lifecycle/bridge evidence pending.
- [M4: Native UX and Activity History](005-native-ux/spec.md) — Hosted preview/history implemented; native walkthrough/integration workflow pending.
- [M4a: Apple HIG UI/UX Refinement](009-apple-hig-ux/spec.md) — New planned milestone; refines M4 before M5/M6 approval.
- [M4b: QA-driven UX and truthful telemetry](010-qa-ux-sensors/spec.md) — Preview increments implemented; 54-task backlog, latest [diagnostics QA](../docs/qa/sleep-diagnostics-2026-10-08.md); native/physical/full-quality gates remain open.
- [M5: Signed Beta and Updates](006-signed-beta/spec.md) — Planned; blocked on integrated candidate.
- [M6: AI Quality Gate](007-ai-quality-gate/spec.md) — Preview QA in progress; full gate not passed.
- [M7: Supervised Real User Testing](008-user-testing/spec.md) — Planned; blocked on M6 PASS.
- [M8: Awake Automation & Diagnostics](011-awake-automation/spec.md) — Partial implementation: 18/43 tasks complete; shared diagnostics, alert/login adapters and Preview guards, [LidRun gap comparison](011-awake-automation/lidrun-comparison.md); live extensions consume qualified M1/M2 backend.

Experimental feature spec (not a milestone; no gate change):

- [Closed-lid best-effort mode (012)](012-closed-lid-best-effort/spec.md) — Design only after the owner selected the best-effort product track; gated by R0 (same-boot clear effectiveness) and the full-Sleep/qualification plan. M1 remains blocked; no app integration or native action is authorized by the spec.

Every folder contains spec.md, plan.md, tasks.md, research.md, data-model.md, quickstart.md and
checklists/requirements.md. Base runtime contracts reside with M2/M3; M8 adds scoped automation extensions while consuming the existing policy/transport/backend contracts.
Shared [product spec](../docs/planning/product-spec.md), [architecture](../docs/planning/architecture.md),
[limitations](../docs/planning/limitations.md) and [domain model](../docs/planning/domain-model.md)
are sources of truth, shared references rather than additional milestone features. Local task IDs restart; [migration map](../docs/planning/task-migration.md)
preserves all 60 future tasks once. M0's four completed tasks are document work only.

## Feature Selection
Current .specify/feature.json selects specs/011-awake-automation for implementation scope; user authorized implementation on 2026-10-08. Selection alone passes no release gate. Use explicit feature context for active scoped work.
Run Spec Kit against a single folder from repository root, for example:
```
SPECIFY_FEATURE_DIRECTORY=specs/002-power-feasibility rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
Set same feature context when using `$speckit-plan`, `$speckit-tasks`, `$speckit-analyze` or later
`$speckit-implement`; in fresh session confirm .specify/feature.json selection before running skills.
Current setup-plan preserves an existing plan; still use read-only prerequisite inspection to inspect context.
Prerequisite check resolves documents only, not milestone PASS. Preview implementation/QA authorized by subsequent user instructions; live actuation still gated.
