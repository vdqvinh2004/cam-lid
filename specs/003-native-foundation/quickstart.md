# Validation Quickstart: M2 Native Foundation and Safety

**Current availability**: Preview code exists: policy/config/safety, native read-only telemetry, same-user CLI transport, simulator and tests. No live power backend/helper; lid remains unknown.

Core verify (works now): `cd Packages/CamLidCore && swift test`
Fixtures: Tests/Contracts/Fixtures

1. Verify prerequisites: M1; review their recorded gate evidence.
2. Read [spec](spec.md), [plan](plan.md), [tasks](tasks.md), shared limitations.
3. Execute authorized scoped work only after prerequisites. Validation: Shared policy/contract simulator and supervised physical backend tests; safety complete before any live protected demo.
4. Check independent story outcomes in spec.md; record expected/actual, source, environment and
   failure-class timing. No simulator result establishes lid/display behavior.
5. Exit only when Safety, journal, recovery and CLI foundation verified; no unsafe live protection; full native dashboard parity deferred to M6.

Future CLI usage and supervised end-to-end sequence: shared guide.
Use explicit feature context from repository root when invoking Spec Kit:
```
SPECIFY_FEATURE_DIRECTORY=specs/003-native-foundation rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
This check resolves documents only. M6 and M7 remain separate quality/user gates.
