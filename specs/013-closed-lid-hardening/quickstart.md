# Quickstart: Closed-Lid Best-Effort Hardening

**Feature:** `013-closed-lid-hardening`
**Scope:** Offline validation only. Do not install the helper, run a power command, or change a
real sleep policy for these steps.

## Prerequisites

- macOS with the repository checked out.
- Swift 6.0 toolchain and Xcode command-line tools available.
- No CamLid helper installation or live best-effort session is required.
- No native power action is authorized by this quickstart.

## 1. Helper package tests

```bash
swift test --package-path Packages/CamLidPowerHelper
swift test -c release --package-path Packages/CamLidPowerHelper
```

Expected:

- All existing helper tests pass.
- New fake tests cover policy clear/conflicted/unreadable, no global write, one own clear,
  same-boot restart re-observation and pending enable/restore recovery.
- No test writes a real policy or launches the helper.

## 2. Best-effort model tests

```bash
swift test --package-path Tests/Experiments/BestEffortLidSession
swift test -c release --package-path Tests/Experiments/BestEffortLidSession
```

Expected:

- All existing tests still pass (the offline suite grew from 51 to 62 tests).
- New tests cover `foreignPolicy`, boot foreign observation, `recoveryReason`, `rearmBasis`,
  stale-property refusal, pending/acknowledged journal reasons and helper failure outcomes.
- No `Protected`/`verified` projection is reachable.

## 3. Static contract check

Review [contracts/status.md](contracts/status.md) and verify:

- `protectionClaim` is always `none`.
- `closedLidProtectionQualified` is always `false`.
- `rearmBasis` defaults to `none`.
- A stale `AppleClamshellCausesSleep` value never authorizes a start.
- A foreign global policy is never cleared by CamLid.

## 4. What is intentionally not run

- No `pmset`, selector call, helper command, assertion creation or session acquisition.
- No helper install/uninstall.
- No app integration or signed build.
- No G2 native foreign-policy row. That row needs a separate one-use approval and is outside
  M9's offline exit gate.

## 5. M9 completion evidence

Record:

- command, toolchain, date and pass/fail counts;
- the new reason/contract tests;
- confirmation that no native action or install occurred;
- links to the updated spec/plan/tasks and roadmap.
