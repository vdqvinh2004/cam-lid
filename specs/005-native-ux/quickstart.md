# Validation Quickstart: M4 Native UX and Activity History

**Current availability**: Native menu/dashboard/settings/onboarding/activity windows and durable history exist. Interactive/accessibility/performance walkthrough remains pending.

1. Verify prerequisites: M2; review their recorded gate evidence.
2. Read [spec](spec.md), [plan](plan.md), [tasks](tasks.md), shared [limitations](../../docs/planning/limitations.md).
3. Execute authorized scoped work only after prerequisites. Validation: State fixtures permit UI testing independently of live agents; integrated agent rows required before M6.
4. Check independent story outcomes in spec.md; record expected/actual, source, environment and
   failure-class timing. No simulator result establishes lid/display behavior.
5. Exit only when Native control/history accessibility and privacy pass; status never claims restoration from expired lease alone.

Future CLI usage and supervised end-to-end sequence: [shared guide](../../docs/planning/end-to-end-validation.md).
Use explicit feature context from repository root when invoking Spec Kit:
```
SPECIFY_FEATURE_DIRECTORY=specs/005-native-ux rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
This check resolves documents only. M6 and M7 remain separate quality/user gates.
