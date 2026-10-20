# Implementation Plan: M5 Signed Beta and Updates

**Branch**: None | **Date**: 2026-10-04 | **Spec**: [spec.md](spec.md)
**Input**: specs/006-signed-beta/spec.md
**Status**: Preparation implemented; preview checks running. Final integrated signed-candidate approval remains gated.

## Summary
Sparkle update integration, signing/notarization, helper lifecycle, migrations and supported build revalidation. Distribution trust and owned-state cleanup verified before external test; unresolved recovery prevents installer/removal success claims.

## Technical Context
**Language/Version and Primary Dependencies**: Xcode signing/notarization and Sparkle 2.10.0 pinned exactly in SwiftPM/XcodeGen; conditional helper lifecycle.
**Storage**: Shared policy/configuration/history/journal definitions in [domain model](../../docs/planning/domain-model.md); evidence artifacts scoped by tasks.md.
**Testing**: Fresh signed installation, denied approval, upgrade/remove and tamper cases.
**Target Platform**: Proposed macOS 14+, Apple Silicon first; exact hardware/OS/backend rows require M1 evidence.
**Project Type**: Native macOS utility or its scoped feasibility/quality validation feature.
**Performance Goals**: Inherit product SC-005 where applicable; measurement performed M6.
**Constraints**: Preview implementation authorized; live actuation gated by M1; safety before live protection, no transcript collection,
30s lease deadline distinct from restoration, OS/joint failure remains residual.
**Scale/Scope**: Sparkle update integration, signing/notarization, helper lifecycle, migrations and supported build revalidation. No downstream feature absorbed into this task list.

## Constitution Check
[Constitution](../../.specify/memory/constitution.md) applies. Pre-research and post-design checks:
safety/recovery limits, evidence confidence, native accessibility, shared GUI/CLI policy and privacy
preserved by scoped contracts and dependencies. No exceptions. Document migration does not pass
hardware or runtime gates. Shared [architecture](../../docs/planning/architecture.md) governs seams.

## Project Structure
Feature docs: spec.md, plan.md, research.md, data-model.md, quickstart.md, tasks.md, checklists/.
Relevant implementation and validation paths:
- `Packages/CamLidCore/Sources/CamLidApp/UpdateController.swift`
- `Packages/CamLidCore/Sources/CamLidApp/UpdatesView.swift`
- `Config/Beta.xcconfig`
- `scripts/package-beta.py`
- `CamLid.xcodeproj/project.pbxproj`
- `docs/qa/packaging-report.md`

## Phase 0: Research Decisions
See [research.md](research.md). Inherited primary-source findings and product decisions remain
in [shared research](../../docs/planning/research-decisions.md). Future evidence choices tracked
as mandatory tasks; unverified backend/provider compatibility is not a resolved physical fact.

## Phase 1: Design and Contracts
[Model](data-model.md) defines relevant entities/evidence; [quickstart](quickstart.md) defines
validation sequence and expected results. Runtime contract owners are M2 (CLI/helper) and M3
(agent events); later milestones consume those contracts without copying implementation.

This milestone has no new runtime protocol; evidence/output expectations below and shared contracts govern validation.

## Dependencies and Exit Gate
Prerequisites: M2, M3, M4. Each prerequisite must meet its documented gate; planned docs do not
satisfy that prerequisite. Distribution trust and owned-state cleanup verified before external test; unresolved recovery prevents installer/removal success claims. M3 and M4 may overlap after M2; M5 joins both; M6 PASS
must precede M7. Failed core feasibility does not become fulfilled idle-only fallback.

## Complexity Tracking
No new runtime architecture/dependency introduced by splitting specs. Conditional privileged/
independent recovery services require M1 need/evidence decision; no speculative service created.

## Added M4a dependency (2026-10-05)

[Apple HIG UI/UX milestone](../009-apple-hig-ux/spec.md) is required before this milestone final approval. Preparation may overlap; the accepted candidate must include M4a evidence and no unresolved critical/high UX finding. M4a does not replace M1 physical recovery or other existing gates.

## Preparation decisions

Update code lives in the existing CamLidApp package so GUI/CLI share authoritative status. Native menu opens one Updates window; signed distribution metadata is read from the bundle, not preferences. Sparkle standard controller is created only after eligibility and safety checks; only information-probe check type is allowed. Automatic checks/installation and profile collection are disabled, with an empty profile-key allowlist. No install command exists in this preparation.

Local packaging audits require executable/framework metadata and conservative update defaults. Preview archives have betaEligible:false. Beta audit additionally checks Developer ID/team, hardened runtime, signature integrity, notarization staple, Gatekeeper and complete current-source predecessor evidence. It never signs, notarizes, installs or publishes. No speculative power helper or uninstall mutation is introduced before M1 selects the backend.

## M4b QA refinement dependency (2026-10-05)

[010 plan](../010-qa-ux-sensors/plan.md) adds engineering acceptance SC-001–006 before final M5/M6 approval; SC-007 user outcome follows M6 in M7. Pending/invalid/conflict/failed automatic preference edits replace the old dirty-draft concept for update deferral. Existing certificates/feed/notarization, hardware/provider and quality gates remain unchanged. Historical component evidence does not validate these future edits.

### M4b preview handoff,2026-10-05

Feature010 now implements direct revision-aware settings, presets/Custom input, agent toggle badges, typed read-only lid telemetry and explicit preview blockers.213 Swift tests and five packaging tests; seven preview checks PASS. [Current evidence and remaining gates](../../docs/qa/qa-refinement-report.md). Bounded off-main preference/sensor work, full native/VoiceOver/performance and independent review remain open. No backend/signing/user predecessor is checked by this increment.


## M8 login ownership integration — 2026-10-08

Explicit login preference changes now call SMAppService.mainApp register/unregister; Settings reads actual OS state and errors. Preserve login intent on ordinary Quit. Update must preserve signed identity and reconcile registration at the final installed path, without re-arming a session. Uninstall must disable and verify this app's owned registration before final removal; uncertain registration or power restoration prevents a cleanup-success claim. Follow the [signed isolated lifecycle procedure](quickstart.md#m8-login-registration-regression--implementation-added-2026-10-08). Native/signed acceptance remains NOT RUN; no privileged helper or arbitrary LaunchAgent is added.
