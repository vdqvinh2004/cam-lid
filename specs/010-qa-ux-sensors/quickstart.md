# Validation guide

**Today**: UI simplicity increment T046–T052 implemented; 335 Swift tests (200 Core/42 CLI/93 App) and seven canonical checks pass. Native bounded preview done partial (290 pt dashboard, 4 badges, footer gone, outside dismissal, menu Start/Stop refusal); full 30-cycle/IME/VoiceOver/appearance/device matrix remains open. Physical/full milestone acceptance remains partial/open; see tasks.md and docs/qa/qa-refinement-report.md plus docs/qa/ui-simplicity-report.md. These procedures are not passes. Use isolated QA state; do not mutate LidRun or production provider files for comparison. All host-power tests supervised and gated by M1.

## Prerequisites and documentation checks

From repository root:

```sh
rtk .specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks
```

Confirm feature_directory=specs/010-qa-ux-sensors. Record build/source hashes, exact OS/model/display, source/provider versions, support row and config revision for later QA. Live status includes additive lid/unsupported temperature/provider/protection fields. Config writes use `camlid config set --file <patch.json> --expectedRevision <N> --json`; stale revision is refused.

## Component/build checks

After implementation, run canonical verifier once on settled sources:

```sh
rtk python3 scripts/verify-preview.py --build-directory /tmp/camlid-m4b-verify --output docs/qa/preview-evidence/m4b
```

Expected: source unchanged during verification, Swift tests/Debug/Release/binary integration/packaging checks pass; read-only preflight does not claim M1 PASS. New tests include per-field concurrency/failure/pending settlement, presets/custom boundaries, Boolean lid typing, per-source timestamps, temperature decode/unsupported path, badge aggregation and capability refusal. No redundant tests for removing a static label alone.

## US1 dashboard

Using native CUA on exact app window/status surface, verify no Options, left-toggle/right-menu/Control-menu, Stop/mode, Escape and actual outside clicks on desktop/another app/CamLid settings. Avoid interacting with unrelated private documents. Repeat30 cycles each appearance row; record delivered event and independently observed visible dismissal/close callback. Include nested selector, rapid toggle, app switch, lock/unlock and new display geometry. AX node presence alone is inconclusive. Background refresh must never reopen/front app. Missing status-item targeting is blocked, not PASS.

## US2 preferences

For each canonical table row: all presets, Custom lower/upper/non-preset, empty/decimal/negative/overflow/out-of-range, locale digits/IME, valid400 ms idle commit, Return/focus loss, rapid edits. No raw field until Custom; no Save/section label. Observe field feedback and live CLI readback/revision ≤1 s healthy. Reopen/restart and confirm value. Use isolated storage failure injection for failed writes; retain candidate/last valid. Concurrent CLI edit another key survives; same key conflict offers Use current/Apply my value. Close/Quit pending valid settles≤2 s or shows explicit retry/keep-open/discard; updates deferred while editing unresolved. Check active cap/grace/wait deadlines did not extend.

## US3 telemetry

Read-only lid observation on exact Mac/build: open→supervised close→reopen; test no external display and external clamshell topology separately. If no qualified backend, accept natural sleep and verify on reopen; don't treat execution while asleep as polling failure or continuity proof. Signal transitions while awake appear≤2 s, age>5 s stale, missing/wrong type becomes Unknown; desktop absence established before Not applicable.

Temperature: first qualify named source/reference using plan.md protocol. Only then compare UI/CLI degrees/source/age; sample2 s, age>10 s stale,200 ms platform-read budget off main thread. Error/null/unavailable never0°. Source/reference tolerance max(2°C, documented resolution) for the same physical metric and synchronized≤2 s samples; if no defensible reference, qualification blocked. Use ordinary coding load; no thermal stress. Inject Critical pressure alongside a slow/temp failure and verify existing immediate event stop remains uncached. GUI/status/logs expose availability without sampling spam.

## US4 badges

All four badges mouse/keyboard: Detection On/Off persistence, pending/failure feedback, disconnected/setup/error state, fresh active/wait/idle/stale, multiple tasks/Orca panes. Click is enrollment only, no paid prompts, hooks or provider writes. Mixed active+unknown staysActive with details; no active+unknown becomesUnknown; disabled work never completes by invented event. Replay existing40 captured provider profiles rather than rerun paid jobs by default. Captures are regression evidence, not full M3 acceptance.

## US5 protection

Use fixtures for Preview/Needs setup/Untested/Conflict/Recovery required/Ready/Protected; fixtures can never actuate. Verify exact blocker text and unqualified live refusal. M1 `specs/002-power-feasibility/tasks.md` T003–T008 remain backend owners. Only after qualified backend+M2 safety, execute existing supervised PowerFeasibility/RecoveryFailureMatrix and three30-minute runs per supported row. Observe system progress/internal panel sleep/restoration/system sleep separately. LidRun competing-state rows require separately authorized supervised configuration; no automatic stop/start to make test pass. Manual Sleep/global ownership failure rejects candidate.

## Final quality and user gate

Actual keyboard plus light/dark/contrast/transparency/motion, long labels/20 tasks/notch/scale where available. Measure shared SC-005 and new dismissal/autosave latency, not estimate them. Independent AI reviews source against spec/contracts/L01–L20 and attached evidence; zero critical/high, all supported rows physical PASS required. Record docs/qa/qa-refinement-report.md and update M6 report with verdict. Only then five supervised users under M7 (≥4/5 uncoached primary-flow success). Remaining hardware/cert/Orca/Claude gates never disappear because this milestone's component suite passed.

Current user scope: VoiceOver acceptance excluded. Passive observation requires no bridge/hook/provider setup; provider badges select sleep relevance. Latest evidence: docs/qa/passive-supervision-report.md. Earlier checkpoints above retain their historical scope.
