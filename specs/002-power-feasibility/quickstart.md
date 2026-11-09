# Validation Quickstart: M1 Power and Detection Feasibility

**Current availability**: Planning documents only. No application targets/CLI/hardware harness
exist yet. Future commands and test paths are proposed until scoped implementation occurs.

1. Verify prerequisites: M0; review their recorded gate evidence.
2. Read [spec](spec.md), [plan](plan.md), [tasks](tasks.md), shared limitations.
3. Execute authorized scoped work only after prerequisites. Validation: Supervised reversible hardware matrix plus isolated fault simulation; no kernel freezing/overheating.
4. Check independent story outcomes in spec.md; record expected/actual, source, environment and
   failure-class timing. No simulator result establishes lid/display behavior.
5. Exit only when Backend/support matrix selected only after mandatory tests pass; persistent candidate demonstrates single-helper crash/hang recovery; otherwise STOP.

Future CLI usage and supervised end-to-end sequence: shared guide.
Use explicit feature context from repository root when invoking Spec Kit:
```
SPECIFY_FEATURE_DIRECTORY=specs/002-power-feasibility rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
This check resolves documents only. M6 and M7 remain separate quality/user gates.
