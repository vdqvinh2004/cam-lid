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

## 5. Reproducibility follow-up (2026-10-21)

```sh
python3 -m unittest discover -s Tests/Hardware -p 'test_*.py' -v
python3 Tests/Hardware/g2-foreign-policy-row.py --self-test
python3 Tests/Hardware/audit-m9-host-readonly.py --self-test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 scripts/verify-preview.py --output docs/qa/preview-evidence/my-new-preview-run
```

The hardware Python tests use fakes/owned PTYs only. Canonical Preview verification also
performs read-only hardware preflight, but never installs/starts a helper or actuates power.
The 40-run private archive is an explicitly opted-in historical test, not a mandatory fixture
or current product-source qualification. See the committed fixture README for its invocation.

For candidate staging, use the existing `Packages/CamLidPowerHelper/Support/stage-local-candidate.py`
with newly compiled helper/client paths under `.pi/qa-builds` and `--lid-specific-best-effort`.
It signs locally and never installs or registers the bundle. Every rebuild requires a new
review/freeze; do not update pins automatically or reuse a prior approval.
The current exact freeze, source manifest and human-only read-only root-journal gate are in
the handoff. `--prepare-readonly` requires
that exact staging; `--run-approved` remains blocked with no approved boot pin.

The owner-confirmed lock-only profile has a separate
auth-only installation packet.
Its `python3 Tests/Hardware/install-m9-lock-only-qa.py --self-test` only verifies staging;
it never installs or contacts the helper. Do not run its approval flag/launcher as part of
software verification. Root install/bootstrap/one-inspect consent is a separate human gate, now completed per the
owner-returned receipts. Do not rerun that consumed launcher as a verification step. Native
G2 still requires its own exact approval; software tests/metadata do not contact the helper.

The next G2 packet includes a
pure `review-m9-postboot-audit.py --review <saved-owner-JSON>` tool. A matching report only
supports review; it never grants recovery, journal deletion, IPC or native execution.
Postboot owner audit now matches the old G2 acknowledged journal. The separate disarmed
archival/restart packet is the next decision; its native flags are not software-test commands. Do not substitute an old
v9 Sleep recorder or reset packet.

## 6. M9 completion evidence

Record:

- command, toolchain, date and pass/fail counts;
- the new reason/contract tests;
- confirmation that no native action or install occurred;
- links to the updated spec/plan/tasks and roadmap.
