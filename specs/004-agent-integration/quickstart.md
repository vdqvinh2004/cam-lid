# Validation Quickstart: M3 Agents and Orca Integration

**Current availability**: Parsers and runtime normalized ingestion exist. Orca 1.4.220 read-only poller is opt-in; provider lifecycle acceptance and bridge setup remain pending.

1. Verify prerequisites: M2; review their recorded gate evidence.
2. Read [spec](spec.md), [plan](plan.md), [tasks](tasks.md), shared limitations.
3. Execute authorized scoped work only after prerequisites. Validation: Version-pinned provider/Orca event fixtures and installed-agent runs.
4. Check independent story outcomes in spec.md; record expected/actual, source, environment and
   failure-class timing. No simulator result establishes lid/display behavior.
5. Exit only when Exact/inferred tiers honest, opt-in configuration preserved, installed-version lifecycle and concurrency cases pass.

Future CLI usage and supervised end-to-end sequence: shared guide.
Use explicit feature context from repository root when invoking Spec Kit:
```
SPECIFY_FEATURE_DIRECTORY=specs/004-agent-integration rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
This check resolves documents only. M6 and M7 remain separate quality/user gates.
