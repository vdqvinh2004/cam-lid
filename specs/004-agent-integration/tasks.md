# Tasks: M3 Agents and Orca Integration

**Input**: spec.md, plan.md, research.md, data-model.md, relevant contracts.
**Status**: Parser/normalizer components plus opt-in Orca poller and bounded runtime ingestion exist; real installed-provider lifecycle/bridge integration gates remain open.
**Format**: Local T### IDs; [US#] refers to this milestone spec; [P] independent files after prerequisites.

## Phase 1: Setup prerequisites

Use prerequisite milestone evidence (M2); no separate setup task is added for already-owned work.

## Phase 2: Foundational prerequisites

- [x] T001 Implement run identity/dedup/order/children/liveness normalization in Packages/CamLidCore/Sources/CamLidCore/AgentEvidence.swift (FR-007, FR-008).

## Phase 3: User Story 1 — Track supported local agent work

**Independent Test**: 20 runs/provider plus working/network/approval/idle/completion/crash/child/reconnect/race cases; two Orca tasks aggregate without premature completion.

- [x] T002 [P] [US1] Implement fresh version-gated local Orca status/worktree JSON adapter, restoredUnconfirmed rejection and provider dedup in Packages/CamLidCore/Sources/CamLidCore/Adapters/OrcaHostResolver.swift (FR-006).
- [x] T003 [P] [US1] Implement opt-in Claude lifecycle adapter with StopFailure/interrupt/background/subagent handling in Packages/CamLidCore/Sources/CamLidCore/Adapters/ClaudeAdapter.swift (FR-006, FR-007). — **Closed 2026-10-31 by [ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md):** CamLid installs no hooks, plugins, wrappers or integrations; directly run agents are observed from outside (spec 015).
- [x] T004 [P] [US1] Implement opt-in Codex CLI hooks/exec event adapter, turn IDs and explicit desktop limitation in Packages/CamLidCore/Sources/CamLidCore/Adapters/CodexAdapter.swift (FR-006, FR-007). — **Closed 2026-10-31 by [ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md):** CamLid installs no hooks, plugins, wrappers or integrations; directly run agents are observed from outside (spec 015).
- [x] T005 [P] [US1] Implement configured loopback/OpenCode plugin adapter with snapshot reconciliation, retry/permissions/children in Packages/CamLidCore/Sources/CamLidCore/Adapters/OpenCodeAdapter.swift (FR-006, FR-007). — **Closed 2026-10-31 by [ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md):** CamLid installs no hooks, plugins, wrappers or integrations; directly run agents are observed from outside (spec 015).
- [x] T006 [US1] Implement process discovery confidence and bounded fallback in Packages/CamLidCore/Sources/CamLidCore/ProcessDiscovery.swift; PID start identity, never CPU-based completion (FR-006, FR-008).
- [x] T007 [US1] Implement integration preview/diff/install/removal preserving Orca and existing provider configuration in Packages/CamLidCore/Sources/CamLidCore/IntegrationInstaller.swift (FR-015). — **Closed 2026-10-31 by [ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md):** CamLid installs no hooks, plugins, wrappers or integrations; directly run agents are observed from outside (spec 015).
- [~] T008 [US1] Test lifecycle races/reconnect/approval/network/crash/child/parallel/version mismatch in Packages/CamLidCore/Tests/CamLidCoreTests/AgentTests.swift and record 20-run installed-version evidence in docs/qa/agent-compatibility.md (SC-003). — **2026-11-03 cleanup:** Superseded by ADR 0002: there are no provider events, hooks or wrappers to race; the observer is tested in spec 015.

## Dependencies & Execution Order

Prerequisites: M2. Tasks in setup/foundation precede story work. Tasks inside each story stay ordered unless [P] explicitly marks separate files.
M2 safety story completes before live power tests in M2 power story; policy/simulator can run before physical arming.
M3 adapters [P] depend on shared evidence normalizer. M4 may overlap M3 on simulated policy; M5 needs both.
M6 consumes integrated M2–M5; only M6 PASS enables M7. No future gate is complete from document checks.

## Parallel Opportunities

Only tasks explicitly marked [P] may run concurrently after prerequisites; serialize shared power/journal mutations.
Independent story validation follows spec.md; multi-story milestone joins its stories at exit gate.

## Implementation Strategy

Exact/inferred tiers honest, opt-in configuration preserved, installed-version lifecycle and concurrency cases pass.
Current authorization permits scoped preview implementation and QA; external publication remains unauthorized.

## Current scope correction — 2026-10-13

Owner reaffirmed third-person observation: no hooks/MCP/bridge, producer-side event ingestion/wrapping or agent configuration writes. Earlier integration task boxes and T015 are historical component scope, not product progress or live-install prerequisites. No provider jobs may be started to finish those superseded gates. Passive source accuracy/uncertainty and physical safety remain unqualified.

- [x] T016 Record owner correction, reaffirm existing README/passive-supervision architecture, withdraw Codex live-bridge continuation and mark older integration acceptance superseded without deleting evidence. Documentation only; source routes unchanged.
- [x] T017 Product-boundary quarantine: CLI event/bridge/run exit3 beforeIO/launch; app sync/async producer events/diagnostics/admission denied beforedecode; remove automaticOrca runtimepolling and directpoll refuses. Realfs preview/install/removal disabled beforeIO; onlyinmemory historicalstoragefixtures admitted. OSscan failure/truncation/stale/future/nonfinite receipt becomesUnknown,Orca presence sameuncertaintyguard. RED logs and firstgreen8staleexpectationissues preserved. FullDebug449declarations before finalinstallerchange PASS; finalRelease450/Core229CLI58App163 and finalfocusedDebug16 PASS with actualbuiltCLI→privatePreview socket. Threeoptionalprovider/Orca/temp probes skipped; baselinepre-fix refreshquery mayhavescheduled,actualexecutionnotinstrumented. No actualuseragentconfig/modeljob/poweraction; legacylibraryfixtures retained,semanticexternalactivity/visualUI/independentreview stillnotqualified.
- [x] T018 Qualify compliant external activity signals and inference limits for standalone/parallel agents; lowCPU/networkwait, missing/stale/hidden work never become invented completion. Verify countdown cancellation/Unknown refusal inertly before any separately approved physical action. — **2026-11-03 cleanup:** Done by [spec 015](../015-agent-activity-observer/spec.md): CPU-based activity signals, their limits (a model thinking silently can look idle) and Unknown handling, calibrated on this Mac.

- [x] T019 Read-only Orca UI observer offline preparation: pinned1.4.224 publicstatusallowlist, standardAXTabGroup/AXTabs hypothesis, per-windowheader64pt/tinyGroupImage geometry beforedescription, noAXTitle/Value/actions/screenshots/providerAPIs. BoundedprivacyFakeAX/time/cycle/capacity/permission/parallel/grace/Unknown tests; firstretiredRun2issues preserved and adapteravoids repeatedUnknownresurrection. EarlierfullDebugRelease460each and finalApp174each verify composed461coverage; XcodeDebugbuildPASS. NewprivateQAapp identity/state ad-hocstrictverified, notlaunched,ownTCCgrantneeded. No nativeUIexposure/activitycoverage/semanticcompletion/power PASS; T018 remainsopen.

## Runtime refinement evidence (2026-10-05)

T003–T005 provider parsers are unit-tested; automatic provider hook/plugin bridges and installed-version lifecycle coverage are unfinished. T006 now includes a native same-user, basename-only bounded poller with PID/start identity; presence never produces working/completion or Auto arming. Installed lifecycle acceptance remains separate. T007 preserves owned edits in storage seams; native install/diff/removal workflow is unfinished. These original task boxes stay open until full scope is met.
T008 partial 2026-10-05: 20/20 codex (gpt-6-luna medium) + 20/20 opencode (longcat-2.5-preview-free) runs recorded with streams/markers; thread association + step_start ingestion added with golden InstalledStreamsTests; exec-failure-inside-item gap documented. Still open: network runs, Claude (absent), Orca hosted aggregation, bridge acceptance.

- [x] T009 Connect normalized runtime ingestion to app policy/dashboard/CLI; use app-owned receipt time, bounded enrollment and stale-working unknown deadlines; explicit opt-out removes provider tasks.
- [x] T010 Implement bounded read-only Orca 1.4.220 envelope/nested-row poller, local/runtime/version gating and no-overlap polling; live schema probe passes. This does not complete T008's 20-run matrix.
- [x] T011 Complete installed Claude/Codex/OpenCode bridge setup/reconciliation and native discovery; generate reviewed integration diffs without overwriting Orca-managed configuration, then verify T003–T007 acceptance. — **Closed 2026-10-31 by [ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md):** CamLid installs no hooks, plugins, wrappers or integrations; directly run agents are observed from outside (spec 015).
- [x] T012 Define production run retirement with bounded tombstones after runtime table exhaustion; verify no ancient replay/reused-run resurrection and no evicted active work. Oldest-terminal retirement, retiredRun rejection, newer-epoch reuse without bypassing the live table bound, default256-entry history bound with fail-closed exhaustion (never forget and resurrect), scoped child links, explicit endSession clearing. Runtime retires expired nonholding rows and counts holding transitions transactionally, including cached-idle and gap-fill identities.

2026-10-05 follow-up: bounded real stdin bridge implemented for Codex/OpenCode; actual CLI→app socket regression, all 40 captured streams replayed, OpenCode nonterminal step/permission ordering fixes, separate Codex failed-tool diagnostics, runtime receipt pruning and Orca two-pane aggregation regression pass. T008 remains open: captures are not full installed lifecycle acceptance; network/Claude/hosted Orca/detached descendants remain unverified. No paid provider jobs submitted in this follow-up.

2026-10-05 continuation: native process presence, PID-start reuse and stale/silent evidence regressions added; documented Claude hook_event_name/prompt_id/background task/cron schemas parsed offline with privacy/type/version tests. Maximum external event counters reject rather than overflow. Real provider installation is refused before filesystem I/O while descriptors/receivers are unimplemented; diff/removal storage tests preserve later hooks and custom namespaces. T003–T005/T007/T008/T011 remain open for installed protocol/lifecycle acceptance.

- [X] T013 Bound Codex retained session identities/run counters, reject invalid/overflow routing transactionally without changing association or forgetting replay counters, bound reconnect admission and propagate capacity rejection through ProviderStream; validate stream namespaces and preserve bounded distinct long/slash-containing run and child IDs; cover retained work, stream association and explicit source-boundary cleanup in CodexCapacityTests.swift and ProviderStreamTests.swift. Offline component scope; installed hook/desktop/silent-source acceptance remains T004/T008/T011.
- [X] T014 Preserve OpenCode capacity/counter-exhaustion errors from adapter emission through ProviderStream/ProviderBridge; reject overflow without committing parent/child state or silently dropping newly observed work. Verify 65th-session refusal, transactional child identity bounds, rejected snapshot retry, retained work→Unknown on disconnect and bridge→authoritative preview-app refusal without power effects. Component scope only; T005/T008/T011 installed-provider gates remain open.
- [x] T015 Owner-selected Codex offline bridge preparation: source-tag0.162.0 exec `collab_tool_call` item previously ignored then parentidle accepted (RED3wirevariants12issues;lateidlecase14issues). Decode only type, conservatively refuse unsupportedcollaboration with latched ProviderStream policyDenied; retainedworking/waiting or earlieridle→Unknown,never pretend childtracking. Targeted24declarations/28scenarios PASS; affected Core228/CLI58/receiver5 perconfiguration verified Debug/Release, including actual freshlybuiltCLI→isolatedPreview socket exit4/Unknown/privacy. Old-cacheSSDpath and initial nonexistentactualCLIpath failures preserved; only necessaryenvironmentrepair/narrow5checks rerun. No model/providerjob, hook/userconfig write, staging/commit, securitychange or poweraction; installer unavailable remains. Not independently reviewed; T004/T008/T011 realinstalled lifecycle/childprotocol/bridge gates remainopen.
