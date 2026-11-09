# Validation Quickstart: M6 AI Quality Gate

**Current availability**: Planning documents only. No application targets/CLI/hardware harness
exist yet. Future commands and test paths are proposed until scoped implementation occurs.

1. Verify prerequisites: M2, M3, M4, M5; review their recorded gate evidence.
2. Read [spec](spec.md), [plan](plan.md), [tasks](tasks.md), shared limitations.
3. Execute authorized scoped work only after prerequisites. Validation: Independent AI review, deterministic CLI scenarios, native computer-use and supervised physical evidence; simulated/hardware results distinct.
4. Check independent story outcomes in spec.md; record expected/actual, source, environment and
   failure-class timing. No simulator result establishes lid/display behavior.
5. Exit only when PASS report with no critical/high defects or failed mandatory limitation gate; otherwise M7 blocked.

Future CLI usage and supervised end-to-end sequence: shared guide.
Use explicit feature context from repository root when invoking Spec Kit:
```
SPECIFY_FEATURE_DIRECTORY=specs/007-ai-quality-gate rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
This check resolves documents only. M6 and M7 remain separate quality/user gates.
