# Research and decisions

**Date**: 2026-10-05. Planning evidence, not feature acceptance.
Primary-source investigation: [QA research note](../../docs/planning/qa-refinement-research.md). Exact local probes and comparison: [LidRun comparison](lidrun-comparison.md). Apple HIG is authoritative; UIUX Pro Max is not installed in the available skill catalog, so no claim of using it.

Latest user UI review: [UI simplicity investigation](ui-simplicity-review.md), with six live app captures, UX01-18 findings, compact metrics/badges, quiet autosave and a proposed implementation/acceptance sequence. Investigation only. Its proposed removal of visible On/Off captions refines R6 presentation while preserving enrollment/readiness/activity data; spec/contract/task changes must be synchronized before that implementation. Existing checked tasks remain historical, not acceptance of this new design.

## R1 Native dashboard dismissal

Decision: retain transient NSPopover and diagnose its event/focus/close lifecycle before adding scoped mouse/deactivation monitors. Remove duplicate Options callback/button. Rationale: existing code already sets transient; user defect and prior inconclusive cycles require actual visibility evidence. Alternatives: custom floating window/global keyboard hook rejected for unnecessary complexity/permissions. Event monitors only if native behavior demonstrably insufficient, scoped to open lifetime; nested owned menus and reopen races must pass.

## R2 Direct preference application

Decision: atomic per-field patches through current app authority, revision-aware serialization, valid custom debounce/commit, explicit failures/conflicts. Rationale: user removes Save; current whole-draft editor cannot safely autosave unchanged fields from an old snapshot. Alternative: write every text character or recreate whole Configuration from defaults rejected because invalid text/concurrent keys can be lost. Discrete edits immediate; debounce is product behavior, not an Apple HIG mandate.

## R3 Presets then Custom

Decision: four existing numerical fields only, bounds/defaults unchanged, canonical table in data-model.md. Native picker labels include units and meaningful zero choices. Alternative: always-visible text fields/steppers rejected by QA; arbitrary “Unlimited” rejected by mandatory caps. Speculative preset examples in shared research are superseded by this feature's canonical table.

## R4 Real read-only lid source

Decision: bounded IOKit root-domain Boolean candidate, explicit supported-row/freshness/type checks and Unknown fallback. This Mac read-only probe returned AppleClamshellState=false and AppleClamshellCausesSleep=true; current LiveSensorProvider hardcodes unknown. Rationale: real source exists locally; temperature/power backend need not block sensor presentation. Alternative: deriving lid from display list or clamshellActive rejected (the latter is utility override state). Apple open-source internal/deprecated-header caveat prevents broad compatibility promises. Physical close transition remains untested; no host power mutation today.

## R5 Temperature feasibility before integration

Decision: pressure remains separate public safety input. Research a named read-only temperature source, per-model source manifest and independent reference tolerance before integration. None qualified today. Investigate documented model-specific sources first; an SMC/other undocumented candidate requires security/API/distribution/units validation and failure fallback, never privileged helper solely for temperature. If no defensible source, numerical temperature requirement remains unsupported on that row, with explicit label. Alternative: pressure→degrees conversion, relabeled battery temperature, fan-RPM proxy rejected. Numerical temperature remains advisory and cannot suppress critical pressure stops. Apple's thermalState gives categories, not Celsius.

## R6 Badges represent two different states

Decision: native toggle-button badges express Detection On/Off, with separate Active/Waiting/Inactive/Unknown source evidence; missing setup says so. Rationale: configured watch patterns can coexist with zero tasks; enabled is not active work. Alternatives: decorative pills with click handlers/no AX semantics or process-only Active rejected. Enrollment does not modify provider files; existing adapters/Orca bounded identity policy stays intact.

## R7 Closed-lid resolution remains M1-owned

Decision: improve readiness explanation now; qualify backend in M1, integrate only after its support/recovery gate. LidRun documents global SleepDisabled plus helper/watchdog; this is feasibility evidence, not proof of crash restoration/manual Sleep. Existing L01–L20 govern independent recovery, durable owned journal, bounded leases/readbacks and conflicts. Alternative: delegate production control to user's LidRun CLI rejected for v1: its exposed commands affect shared app mode, have no CamLid ownership lease contract, and user holds could be overwritten. No licensing changes/private socket integration. Apple external-display clamshell is a distinct qualified topology, not fulfillment of no-monitor use.

## R8 Quality and dependency order

Decision: M4b after M4a preview, before M5 final acceptance/M6/M7; read-only improvements can proceed independently of power feasibility. Tests specified in spec.md acceptance and tasks include meaningful invalid/concurrency/sensor/interaction regressions, not cosmetic snapshots alone. Actual VoiceOver and physical observation remain separate from CUA AX checks. New preview work never marks original milestone gates passed. No source/build/package changes in planning.
