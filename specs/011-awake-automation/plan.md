# Implementation Plan: M8 Awake Automation & Diagnostics

**Feature context**: `011-awake-automation` | **Date**: 2026-10-08 | **Spec**: [spec.md](spec.md)
**Branch**: Existing checkout retained; feature context is independent of Git branch.
**Input**: [Comparison](lidrun-comparison.md) and user-requested milestone planning.

## Summary

Deliver seven incremental workflows using existing core policy, IPC, wrapper, diagnostics and native Settings. First ship a read-only shared diagnosis increment in Preview. Apply display preferences, protected commands, lifetime holds and actual sleep only through the accepted M1/M2 power backend. Local alerts and native login registration do not require that backend. Read-only MVP and independent alert/login adapters implemented; live protection and native/signed acceptance remain gated.

## Technical Context

**Language/Version**: Existing Swift package/toolchain; installed Swift6.4/Xcode27; deployment macOS14+.
**Primary Dependencies**: Existing SwiftUI/AppKit, Foundation, IOKit, Darwin, ServiceManagement, UserNotifications. No new third-party packages.
**Storage**: Existing private revision-aware atomic preferences and bounded history; add optional rule/notification fields with safe migration defaults.
**Testing**: Existing Swift Testing suites in CamLidCoreTests, CamLidCLITests, CamLidAppTests; policy simulation; native walkthrough and supervised physical gate.
**Target Platform**: macOS14+; exact closed-lid support rows determined by M1, not assumed from SDK or chip family.
**Project Type**: Native menu-bar app plus shared Swift package/CLI; utility UI process and app coordinator remain existing ownership boundaries.
**Performance Goals**: Diagnostics <=5-second completion/partial response, one in-flight request, 64 KiB collection, 256 owner rows; no periodic subprocess. Rule polling reuses existing process sampling, bounded at20 rules/4096 observed processes.
**Constraints**: Same-user local authentication, no transcripts/argv collection, no foreign resource release, no force sleep; stale/unknown inputs fail closed. Infinite excludes session deadline but not renewable ownership expiry.
**Scale/Scope**: Seven stories, one local user; no general automation engine, server, account or new process architecture.

## Constitution Check

Pre-research and post-design review: **PASS for planning**; physical gates remain open.

| Principle | Design evidence |
| --- | --- |
| Safety overrides holds | FR-005–010/014–015; central policy, expiring ownership, no force bypass, verified restoration |
| Activity requires evidence | FR-011–013; lifetime presence separate from AI work, no completion inferred from process absence/low CPU |
| Native/minimal | FR-019–020; extend existing surfaces; SMAppService/UserNotifications; no duplicate launcher or mode controls |
| One policy / simulator | Shared coordinator handles every mutating command; simulation cannot actuate; physical verification separate |
| Private/explainable | FR-004/009/021; bounded read-only collection, no argv/output capture, redacted exports |
| Platform/delivery constraints | M1/M2 own backend; fan/charging excluded; M5/M6/M7 remain required |

Lease guarantees are limited to healthy executor timing. Joint app/helper failure, OS hangs and foreign global setting conflicts retain L01–L20 limitations.

## Project Structure

### Documentation

```text
specs/011-awake-automation/
  spec.md, plan.md, tasks.md, research.md, data-model.md, quickstart.md
  lidrun-comparison.md
  contracts/awake-automation.md
  evidence/lidrun-cli-2026-10-08.md
  checklists/requirements.md
```

### Source Code (planned edits, not generated)

```text
Packages/CamLidCore/
  Sources/CamLidCore/   Configuration, PolicyEngine, PowerController, IPC,
                      LocalControlTransport; new AutomationModels.swift,
                      LifetimeRule.swift and SleepDecision.swift
  Sources/CamLidCLI/   Commands.swift, RunCommand.swift
  Sources/CamLidApp/   AppCoordinator.swift, ControlService.swift, LiveSensors.swift,
                      SleepDiagnostics.swift, SleepDiagnosticsView.swift,
                      NativeProcessList.swift, SettingsView.swift, SettingsEditor.swift,
                      UtilityUICoordinator.swift; new OutcomeNotifications.swift,
                      LoginItemController.swift
  Tests/               existing Core/CLI/App test directories
```

**Structure Decision**: Reuse concrete components. Core owns portable typed contracts/policy; App owns platform collection and actual services; CLI requests typed operations. Do not import App into CLI or add a diagnostics daemon. Share DTO via Core and collect on the app's existing service; utility UI renders returned snapshot. Retain offline diagnosis behavior only if already supported, explicitly labeling absent app ownership. Extract the bounded subprocess helper only if both existing Orca and diagnostics truly need it.

## Scope amendment and existing milestone ownership

The user's 2026-10-08 display setting request supersedes historical blanket “no display-awake assertion” wording in product scenario1, architecture requirement, and M2 T015 **only for explicit lid-open display preference**. Default remains display sleep allowed; closed-lid FR-003 still requires internal display off. Task T001 records this amendment in those shared docs before implementation. M1/M2 still own backend choice, safe actuation, executor/helper and recovery; M8 owns preference binding and additional admission/UX contracts.

Already implemented baseline: Auto/Timed/Infinite and active pickers, runtime/default separation, battery/thermal/CPU policy, read-only assertion diagnostics, private history, icon/tooltip/disclosure work. Do not relabel them as new M8 tasks. Current login/display preferences are stored intent only. Actual power/sleep remains missing.

## Delivery stages and gates

1. **Read-only MVP**: Foundation + US1; no need to pass M1 merely to inspect blockers. Native/CLI/security validation required.
2. **Independent app preferences**: US6 local alerts and US7 login; permission/registration errors and login-no-session tested.
3. **Live extensions**: US2/3/4/5 integrate accepted M1/M2 backend. Before that, typed contracts and simulator tests may proceed; actual power acceptance waits.
4. **Integration**: Add affected rows to M5 install/update/uninstall and M6 QA; M7 user outcomes evaluated only after M6 PASS. No second release track.

M8 estimate: 8–14 engineering days after reusable policy/contracts, excluding M1 hardware/backend effort and permission/signing delays; effort is a rough planning range, not a delivery date.

## Complexity Tracking

No constitution exception or new third-party dependency proposed. Additional bounds and rules are specific to the seven stories; no generic workflow framework.


## Implementation disposition — 2026-10-08

Evidence records 31 of 43 tasks complete and 12 open. T030–031 remain partial pending an accepted sleep backend and requested/observed evidence; T041 remains open for keyboard-focus, hover, diagnostic loading/error, and full menu/icon coverage. US1 read-only MVP is implemented; US6/7 adapters and settings exist with native permission and signed login acceptance pending. T011–014 and T018–020 still depend on an accepted M1/M2 backend. No duplicate backend, helper, or arbitrary automation framework is introduced. Requirement checklists remain unchanged; integrated M8/M5/M6 acceptance is open.
