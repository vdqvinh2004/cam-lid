# Implementation Plan: M4a Apple HIG UI/UX Refinement

**Branch**: None | **Date**: 2026-10-05 | **Spec**: [spec.md](spec.md)
**Input**: specs/009-apple-hig-ux/spec.md
**Status**: Planned; no source changes authorized by this milestone request.

## Summary

Refine existing native preview surfaces around clear protection state, familiar controls and accessible interaction. Apply Apple HIG with explicit source-to-case traceability. Complete before M5 release readiness and full M6 approval; preserve all M1 limitations.

## Technical Context

**Language/Version**: Existing Swift 6 project; canonical verification uses Xcode Swift 6.4.
**Primary Dependencies**: Existing SwiftUI/AppKit, system fonts/colors, SF Symbols; no new UI framework.
**Storage**: Existing configuration/revisions and private JSONL history; no schema migration planned.
**Testing**: Presentation regressions where meaningful, GUI/CLI contract comparison, CUA native walkthrough, keyboard and manual VoiceOver checks; evidence labeled by method.
**Target Platform**: Existing macOS deployment target; current runtime evidence on Mac16,12 / macOS 27.0.1 only. Use availability fallbacks; new visual APIs must not silently raise minimum support.
**Project Type**: Native menu bar utility.
**Performance Goals**: Existing product SC-005; reuse M6 measurements, no timer/polling growth from visual refresh.
**Constraints**: No power mutation or backend support claims; native semantics and accessible text before effects; no prompts/code in screenshots or exports.
**Scale/Scope**: Menu item, dashboard, options, Settings, Activity and onboarding; up to 20 enrolled tasks.

## Constitution Check

Before research: PASS design constraints. I/II: unavailable capability and uncertain activity remain explicit; no safety changes. III: native controls, keyboard/VoiceOver and system preferences mandatory. IV: consume existing policy/config, no second policy in views. V: preserve opt-in configuration and log redaction.
After design: PASS planning consistency; no added privileges/dependencies. Runtime/HIG compliance is unverified until tasks execute. No exceptions or physical gate waiver.

## Project Structure

Feature artifacts: spec.md, plan.md, research.md, data-model.md, quickstart.md, contracts/interaction.md, tasks.md, checklists/requirements.md.

Existing source to refine: `Packages/CamLidCore/Sources/CamLidApp/{DashboardView,SettingsView,ActivityLogView,OnboardingView,MenuBarController,Accessibility,AppCoordinator}.swift`.
Validation: `Packages/CamLidCore/Tests/CamLidAppTests/`, `Tests/UI/HIGValidation.md`, `docs/qa/hig-review.md`; reused preview verifier and M6 performance report.

## Phase 0: Research Decisions

[research.md](research.md) records Apple source guidance, chosen approach and alternatives. Audit current screenshots/accessibility before choosing final geometry. Apple recommendations are not invented numerical requirements. State-first compact hierarchy and named Settings sections are CamLid decisions.

## Phase 1: Design and Contracts

[data-model.md](data-model.md) defines presentation/draft/evidence seams; [interaction contract](contracts/interaction.md) defines action and state acceptance; [quickstart.md](quickstart.md) defines validation. No new CLI/helper wire protocol. Draft state stays local until validated revision-aware save. Initial designs include all unavailable/error states, not only ideal protection.

## Dependencies and Exit Gate

Design and preview refinement can proceed against existing M2/M4 components; final gate needs integrated M3/M4 behavior and accessible desktop. M4a sits between M4 and M5 release approval despite append-only folder 009. M5 final packaging candidate consumes M4a; M6 consumes both; M7 still requires full M6 PASS. No circular dependency on M7 usability results; later trial findings feed M4a fixes and M6 rerun.

Exit: every UX-SC passes with evidence and zero critical/high UX defects. Blocked native tests remain blocked, never inferred from snapshots or unit tests. This gate does not establish M1 hardware support.

## Complexity Tracking

No constitution violations. Reuse existing hosts; prefer system popover/window behavior over custom chrome. Retain AppKit routing for requested two-click behavior unless a simpler native solution preserves its accessibility and semantics.
