# CamLid Milestone Specs

One scoped Spec Kit feature folder per milestone; requested project convention. Spec Kit uses
feature folders and one selected feature context; it does not itself require milestones as folders.
[Shared roadmap](../docs/planning/roadmap.md) defines cross-feature gates and detailed procedures.

- [M0: Project Planning](001-project-planning/spec.md) — Complete: documentation only.
- [M1: Power and Detection Feasibility](002-power-feasibility/spec.md) — Blocked; historical R0 accepted, but G2 qualification and support rows remain unpassed. **Review 2026-10-31:** Standard backend qualified on one Mac by the 014 G2 trial; only T002 (agent lifecycle, now an M3 concern) remains.
- [M2: Native Foundation and Safety](003-native-foundation/spec.md) — Preview components implemented; live backend gate awaits M1. **Review 2026-10-31:** helper backend, lease, journal and recovery done through spec 014; open: T009 qualification, T014, T019 storage faults, T022 (Quit, manual Sleep, external assertions), T023 `camlid start`, T024 recovery CLI.
- [M3: Agents and Orca Integration](004-agent-integration/spec.md) — Third-person external observation; source accuracy/freshness/coverage qualification open. Legacy hook/bridge/wrapper ingress is disabled, not a product prerequisite.
- [M4: Native UX and Activity History](005-native-ux/spec.md) — Hosted preview/history implemented; native walkthrough/integration workflow pending.
- [M4a: Apple HIG UI/UX Refinement](009-apple-hig-ux/spec.md) — Preview refinement implemented; complete native acceptance remains open before M5/M6 approval.
- [M4b: QA-driven UX and truthful telemetry](010-qa-ux-sensors/spec.md) — Preview increments implemented; 54-task backlog, latest [diagnostics QA](../docs/qa/sleep-diagnostics-2026-10-08.md); native/physical/full-quality gates remain open.
- [M5: Signed Beta and Updates](006-signed-beta/spec.md) — Planned; blocked on integrated candidate.
- [M6: AI Quality Gate](007-ai-quality-gate/spec.md) — Preview QA in progress; full gate not passed.
- [M7: Supervised Real User Testing](008-user-testing/spec.md) — Planned; blocked on M6 PASS.
- [M8: Awake Automation & Diagnostics](011-awake-automation/spec.md) — Partial implementation: 33/43 tasks checked (not gate acceptance); shared diagnostics, alert/login adapters and Preview guards, [LidRun gap comparison](011-awake-automation/lidrun-comparison.md); live extensions consume qualified M1/M2 backend.

Experimental feature spec (not a milestone; no gate change):

- [Closed-lid best-effort mode (012)](012-closed-lid-best-effort/spec.md) — Offline model implemented; R0 accepted historically. Full-Sleep/continuity/failure-class G2 qualification and separately approved G3 integration remain open. Manual, finite, attended, AC-only scope; no verified-restoration claim. **Review 2026-10-31:** all remaining tasks closed as superseded by spec 014 or moved to M5/M6/M7.

- [M9: Closed-Lid Best-Effort Hardening (013)](013-closed-lid-hardening/spec.md) — Original offline scope plus reproducibility follow-up complete (22/23 current tasks checked, including auth-only install-packet preparation and T501 foreign-policy row PASS with operator attestation); overall G2 and G3 T502 remain blocked. [Current reproducibility/handoff work](../docs/qa/reproducible-m9-handoff-2026-10-21.md) preserves those gates. **Review 2026-10-31:** T502 closed as superseded by spec 014 (sign-off is 014 T601).

- [Persistent Helper, Standard mode (014)](014-persistent-helper/spec.md) — Draft, 0/20 tasks. Replaces the blocked exclusive-create/one-use admission with a root LaunchDaemon installed once through administrator authentication ([ADR 0001](../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md)). The 012/013 mechanism stays as the experimental, frozen **Strict** mode. No gate passed; native actions still need explicit owner approval.

Each folder contains its scoped spec/plan/tasks; supporting research/model/quickstart/checklists
exist where applicable (012 uses the linked decision memo and runbooks). Base runtime contracts reside with M2/M3; M8 adds scoped automation extensions while consuming the existing policy/transport/backend contracts.
Shared [product spec](../docs/planning/product-spec.md), [architecture](../docs/planning/architecture.md),
[limitations](../docs/planning/limitations.md) and [domain model](../docs/planning/domain-model.md)
are sources of truth, shared references rather than additional milestone features. Local task IDs restart; [migration map](../docs/planning/task-migration.md)
preserves all 60 future tasks once. M0's four completed tasks are document work only.

## Feature Selection
This checkout has no `.specify/feature.json`. Use explicit feature context; current offline
current work is scoped to `SPECIFY_FEATURE_DIRECTORY=specs/014-persistent-helper`.
Selection alone passes no release gate or native-action permission.
Run Spec Kit against a single folder from repository root, for example:
```
SPECIFY_FEATURE_DIRECTORY=specs/002-power-feasibility rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
Set same feature context when using `$speckit-plan`, `$speckit-tasks`, `$speckit-analyze` or later
`$speckit-implement`; in a fresh session inspect any local selection and prefer explicit context before running skills.
Current setup-plan preserves an existing plan; still use read-only prerequisite inspection to inspect context.
Prerequisite check resolves documents only, not milestone PASS. Preview implementation/QA authorized by subsequent user instructions; live actuation still gated.
