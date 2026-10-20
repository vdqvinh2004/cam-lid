# Implementation Plan: QA-driven UX and truthful telemetry

**Branch**: None (feature context010-qa-ux-sensors) | **Date**: 2026-10-05 | **Spec**: [spec.md](spec.md)
**Input**: QA refinement specification. Preview increment implemented;21/45 tasks checked, remainder partial/blocked. Tasks/evidence records are authoritative; full milestone unpassed.

## Summary

M4b addresses all reported interactions and exposes truthful sensors/capability. Deliver native dashboard fixes, direct revision-safe preferences/presets, read-only lid and qualified temperature presentation, then provider badges and protection readiness. Real closed-lid backend remains M1/M2-owned and blocked until independent hardware/recovery evidence exists.

## Technical Context

**Language/Version**: Existing Swift6 package; Xcode27/Swift6.4 local toolchain.
**Primary Dependencies**: AppKit/SwiftUI/Foundation/IOKit/CoreGraphics; existing Sparkle2.10.0 retained. No new temperature dependency selected.
**Storage**: Existing atomic ConfigurationStore/app revision authority and rotated private JSONL history; no new preference DB.
**Testing**: Swift component/integration/simulator contracts, canonical verifier, native CUA, actual keyboard and supervised hardware observations. Current baseline187 Swift tests +5 packaging tests/7 verifier checks is historical and must be rerun after implementation.
**Target Platform**: macOS14+; Apple Silicon first, per-model/build support; Intel/other display rows only when tested.
**Project Type**: Native menu-bar app/core/CLI.
**Performance Goals**: Existing shared SC-005: idle mean<1% of one core over10 min, RSS<100 MiB, dashboard ready p95<200 ms over30 opens. New dismissal250 ms, healthy preference status1 s, awake lid update2 s.
**Constraints**: No UI-thread hardware I/O; no fabricated degrees/sleep; critical thermal uncached; caps not renewed by preference changes; no host override before M1; local private metadata only.
**Scale/Scope**: Four providers/four numeric settings; existing20-task bound. No cloud, fan/charging control, global hotkey remapping, automatic agent installation or dependency on LidRun Pro.

## Constitution Check

Pre-research and post-design: PASS for the design. Safety precedence/verified restoration retained; activity evidence independent of enrollment; native semantics/accessibility retained; GUI/CLI share typed authority; logs private/bounded. No governance exception. This is design compliance, not runtime/M1/M4b PASS. An undocumented sensor/backend may not bypass Platform Constraints; candidate rejection is a valid research outcome, not feature completion.

## Project Structure

Documentation: `specs/010-qa-ux-sensors/{spec,plan,research,data-model,quickstart,lidrun-comparison,tasks}.md`, `contracts/{interaction,status}.md`, `checklists/requirements.md`; primary sources in `docs/planning/qa-refinement-research.md`.

Existing implementation seams (future edits only):

- `Packages/CamLidCore/Sources/CamLidApp/`: DashboardView.swift, MenuBarController.swift, AppCoordinator.swift, SettingsView.swift, SettingsEditor.swift, LiveSensors.swift, UpdateController.swift, Accessibility.swift.
- `Packages/CamLidCore/Sources/CamLidCore/`: Configuration.swift, HealthMonitor.swift, Models.swift, ActivityStore.swift, adapters/control/history. Locate actual sensor/status types with graph before changing; proposed new TemperatureReader.swift/LidStateReader.swift/AgentBadgeView.swift are app-layer files, not new subsystems.
- `Packages/CamLidCore/Sources/CamLidCLI/`: existing status/config serialization; additive projection only.
- `Packages/CamLidCore/Tests/{CamLidCoreTests,CamLidCLITests,CamLidAppTests}/`; `Tests/UI/`, `Tests/Contracts/`, `docs/qa/`.

Structure decision: deepen existing app coordinator/editor/sensor seams; keep pure validation/projection tests and bounded platform reads. No generic sensor plugin framework or new helper for temperature.

## Phase 0: Evidence and feasibility decisions

Baseline every user finding with build/OS/input/actual, source reference and severity. User outside-dismiss report remains a defect to reproduce; current transient code alone is not proof of correct behavior. Installed LidRun liveCLI reviewed; native GUI comparison blocked by unresolved exact surface, follow-up bounded navigation required. Website examples remain labeled illustrative.

Temperature spike: identify physical sensor meaning (CPU/SoC versus battery/chassis), stable source API/model/build, units/freshness, precision/aggregation, permissions/sandbox/signing implications and source overhead. Prefer public/model-documented sources. Investigate SMC only as read-only candidate with internal-API caveats; never import fan writes. Set accuracy criterion before integration: source unit decoding exact; same named source readback within source resolution; independently identified reference across normal idle and ordinary coding workload within max(2°C, documented resolution) with synchronized≤2 s readings. If reference measures a different physical sensor, record mismatch and do not claim accuracy. No forced overheating/stress or broad “Mac temperature”. Candidate manifest and evidence precede numerical UI. Unsupported outcome leaves numerical feature open on that row.

Lid spike: IOPMrootDomain Boolean via IOKit; verify type, actual physical change and wake refresh. This Mac instant read confirms candidate only; do not close lid unattended for this task. Distinguish absent laptop signal from established desktop no-lid. Release IOKit objects; bound read failures/timeouts; notifications if reliable, low-rate polling fallback.

## Phase 1: Design artifacts

Canonical edit/sensor/badge/capability entities: [data-model.md](data-model.md). Native controls/dismissal/AX rules: [interaction](contracts/interaction.md). Additive GUI/CLI status and revision contract: [status](contracts/status.md). Validation steps: [quickstart](quickstart.md). All design choices resolved; hardware facts remain qualification gates, not missing product decisions.

## Phase 2: Implementation sequencing after authorization

1. Baseline/support manifests and existing authority seam audit.
2. US1 dashboard removal/dismissal lifecycle first (small usable preview increment).
3. US2 presets/autosave: per-field typed mutation through existing ConfigPatch → validate resulting config → atomic persist → revision acknowledgement → policy reevaluation → private transition log. UI reflects persisted value, not optimistic success. Preserve unrelated CLI edits/new keys; same-field compare-and-swap conflict explicit. Retire Save/draft guards only after pending-edit settlement and UpdateController safety regression pass.
4. US3 temperature/lid source validation and independent freshness → immutable health → GUI/CLI. Critical pressure paths bypass caches unchanged. Temperature advisory only; keep current thermal stops. No rewrite of provider parsers or policy thresholds.
5. US5 capability explanation and conflict readiness. Branch for live integration only after existing M1/M2 proof; no persistent backend coding in this feature before selection.
6. US4 badges connect existing enrollment/evidence; no task state created by click; disabled discovery handles old active rows conservatively.
7. Full source-set verifier/native/performance/privacy/AI review. Fix/rerun affected checks; only then supervised users on qualified hardware.

## Closed-lid limitation resolution (US5 / M1 dependency)

Step A: read-only inventory exact model/chip/macOS/power/display, current global state/assertions and competing utility ownership. LidRun Pro remains untouched; matching SleepDisabled value does not prove owner. On ambiguous state fail closed and explain conflict.
Step B: supervised M1 candidate comparison in existing002 folder: ordinary assertions as negative/control, supported external-display topology separately, OS-expiring candidate if compatible, then persistent SleepDisabled only if independent executor/journal/recovery acceptable. Vendor implementation informs candidate, not selection.
Step C: durable write-before-mutate owned baseline/generation, authenticated narrow helper, bounded lease and independently running recovery; compare-before-restore and actual readback. App/helper crash/hang/joint failure/OS power failure have separate guarantees and residual risks. No blanket30-second recovery or rescue that blindly sets0.
Step D: three30-minute runs per supported row with workload continuity, physical internal-screen-off observation, completion grace/restoration/system sleep, Stop/Quit/manual Sleep, AC removal, timer expiry, crash/restart/logout/reboot, journal write/corruption/storage failure and external writer races. Fault simulation cannot prove actual hardware recovery; dangerous joint/OS failures documented, not deliberately induced.
Step E: M1 verdict exactrow supported/unsupported/blocked, then integrate in M2 with safety and owned-only recovery. M4b consumes verdict and verifies readiness/Protected only on live qualified row. Preview still cannot actuate. If no candidate meets manual Sleep/recovery requirements, core feature blocked; do not weaken requirement or depend on LidRun mode commands to manufacture success.

## QA coverage and residuals

All user items map to FR/task coverage in tasks.md. Existing L01–L20 retained: platform APIs/support (L01–L04), ownership/recovery/deadlines/journal (remaining recovery rows), provider evidence/CPU/sensor/IPC/privacy/distribution constraints all audited through original limitation inventory, without inventing reordered IDs. Final AI QA report must cite each original row explicitly and preserve existing blocked dispositions.

Cross-feature conflicts: M4a interaction “Options”, explicit Save/draft acceptance and checkbox/raw-input choices are superseded only when M4b implements; old screenshots/tests remain historical. Shared product keyboard options now refers to native menu, not required dashboard button. M5 update unsavedSettings maps to new edit state; signing/feed/install gates stay blocked. M6 requires M4b before user trials. M1 task ownership stays in002; M4b acceptance task links it rather than duplicate checked backend work.

## Estimates and stop conditions

UI/autosave/badges4–7 engineering days; read-only lid qualification1–2 days; temperature feasibility1–3 days plus additional hardware/reference access; native/accessibility/performance/AI QA2–4 days. M1 original5–10 days remains separate and may block indefinitely. Estimates are effort, not dates. Stop numerical rollout on unqualified source; stop live arming on unsupported/recovery/conflict state; stop M7 on any critical/high issue or missing physical row. Planned QA screenshot/evidence routes use isolated preview root and app-only captures.

## Acceptance boundary

M4b engineering approval before M5/M6 covers SC-001–006 (qualified advertised rows only), with T044/SC-007 explicitly deferred to M7 after M6 PASS. T045 records separate engineering and follow-up user dispositions; no dependency cycle. Preview component work can be accepted individually while T032 remains blocked, but full closed-lid product/release approval cannot pass without original M1/M2 evidence.

## Authorized simplicity increment

Implement UX01-18 through T046-T054: contracts first, meaningful projection/history/action tests, then DashboardView/AgentBadgeView/SettingsView and a narrow native SettingsToolbar, AppCoordinator history/size/action wiring, Activity event presentation. Native CUA plus canonical verification follows settled changes. No power backend, provider setup mutation or release-gate bypass. Taste audit informs restraint; Apple native APIs remain the implementation foundation.

Current user scope: VoiceOver acceptance excluded. Passive observation requires no bridge/hook/provider setup; provider badges select sleep relevance. Latest evidence: docs/qa/passive-supervision-report.md. Earlier checkpoints above retain their historical scope.
