# Validation Quickstart: M0 Project Planning

**Current availability**: Planning documents only. No application targets/CLI/hardware harness
exist yet. Future commands and test paths are proposed until scoped implementation occurs.

1. Verify prerequisites: None; review their recorded gate evidence.
2. Read [spec](spec.md), [plan](plan.md), [tasks](tasks.md), shared [limitations](../../docs/planning/limitations.md).
3. Execute authorized scoped work only after prerequisites. Validation: All required planning documents resolve, no unresolved template fields, no app implementation.
4. Check independent story outcomes in spec.md; record expected/actual, source, environment and
   failure-class timing. No simulator result establishes lid/display behavior.
5. Exit only when Documentation and milestone structure validated; no feasibility/runtime pass claimed.

Current M0 review checks documents/links/templates/metadata only; no host changes.
Use explicit feature context from repository root when invoking Spec Kit:
```
SPECIFY_FEATURE_DIRECTORY=specs/001-project-planning rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
This check resolves documents only. M6 and M7 remain separate quality/user gates.
