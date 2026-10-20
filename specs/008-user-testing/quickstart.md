# Validation Quickstart: M7 Supervised Real User Testing

**Current availability**: Planning documents only. No application targets/CLI/hardware harness
exist yet. Future commands and test paths are proposed until scoped implementation occurs.

1. Verify prerequisites: M6; review their recorded gate evidence.
2. Read [spec](spec.md), [plan](plan.md), [tasks](tasks.md), shared [limitations](../../docs/planning/limitations.md).
3. Execute authorized scoped work only after prerequisites. Validation: Per-device physical eligibility and emergency Stop/rollback check before supervised ventilated-desk session.
4. Check independent story outcomes in spec.md; record expected/actual, source, environment and
   failure-class timing. No simulator result establishes lid/display behavior.
5. Exit only when User metrics recorded; no unexplained safety/restore failure; any fix requires relevant M6 rerun before wider trial.

Future CLI usage and supervised end-to-end sequence: [shared guide](../../docs/planning/end-to-end-validation.md).
Use explicit feature context from repository root when invoking Spec Kit:
```
SPECIFY_FEATURE_DIRECTORY=specs/008-user-testing rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
This check resolves documents only. M6 and M7 remain separate quality/user gates.
