# CamLid UI simplicity review

Date: 2026-10-05. Scope: investigation and proposed refinement, **not implemented**.

## Design read

Compact native macOS utility for people running coding agents. Fast status recognition, obvious actions, minimal reading. Evolve the existing Apple interface; retain system typography, SF Symbols, semantic colors, four Settings panes, menu-bar interactions and accessible controls.

Taste skill applied to audit, hierarchy, repetition and restraint. Its marketing layouts and web stack are outside this app's scope. Apple HIG governs native interaction. Design dials: variance **2**, motion **1**, density **5**. These are design intent, not measurements. No new imagery, fonts, decorative animation, glass layers or design framework.

## Evidence and boundary

Inspected the running `/Applications/CamLid UI Review.app`, bundle `dev.camlid.preview.ui`, PID 23215, in dark appearance. Read source through the codebase graph. App-only screenshots and capture manifest: evidence folder.

Observed dashboard content size is 390 × 560 pt; its WindowServer surface includes surrounding material at 416 × 586 pt. Settings surface is 580 × 572 pt including title bar. Dimensions are baseline observations, not proposed sizes.

Six current screenshots:

- Dashboard
- General
- Agents
- Safety
- Activity preferences
- Activity window

Dashboard AX nodes appear under the app menu bar, but CUA cannot resolve them as an exact AXWindow. A read-only CoreGraphics inventory identified the real owned surface, window 2754; CUA captured that exact window. Dashboard findings rely on visible pixels plus source, not hidden AXPopover presence. Settings and Activity have exact-window AX readback.

This pass navigated panes and opened existing windows. No enrollment changes, prompts, power or LidRun commands. Pane navigation does update the remembered Settings pane. Current launch traces include earlier settings edits; this audit did not create those edits. No app source/build changes or new gate acceptance. Full VoiceOver, appearance/device matrix and six-step onboarding flow were not tested here.

## Findings

P1 means affects understanding or the primary workflow; P2 means excess visual/cognitive effort. These are UX priorities, not security severity.

| ID | Priority | Evidence | Proposed resolution |
| --- | --- | --- | --- |
| UX01 | P1 | Agents shows a selection glyph, `Detection Off`, and trailing `Off` for every provider. Source repeats the same enrollment value in multiple places. | One provider name and one state line. Remove both repeated On/Off captions. Selection/check styling communicates monitoring intent; activity remains evidence-based. |
| UX02 | P2 | Four full-width, roughly 59 pt agent controls plus separators consume most of the visible pane; useful setup text is below the fold. | Four compact badges in a 2 × 2 grid at normal width. Use one grouping surface, fewer separators, and a single provider-details area below. |
| UX03 | P2 | `Click a badge to turn detection on or off` repeats what an interactive control should communicate. | Obvious selected/unselected toggle-button affordance, focus ring, hover and AX hint. Remove permanent instruction. Retain concise help if uncoached testing shows confusion. |
| UX04 | P2 | Agents places CLI syntax and backend qualification prose in the ordinary settings path. | Collapsed `Integration details` with provider-specific instructions and copyable commands. Surface `Not connected` directly on the badge; no invented Connect action or silent installation. |
| UX05 | P2 | Every Settings pane reserves a bottom strip for `Applied` and `Close`, even when nothing needs attention. | Remove strip, divider and Close button. Native red close control and Command-W close through the existing guarded settlement path. Successful autosave is quiet; pending/failure/conflict feedback stays at its field. |
| UX06 | P2 | `Requested mode` appears in dashboard and General. | Visible label `Mode` in both. Preserve `requestedMode` internally and distinguish actual state in the status header. |
| UX07 | P1 | Dashboard offers a disabled Stop while empty; Start Preview is only in the menu. Source mode edits save configuration; they do not start a new session. | One contextual primary action: Start Preview / Stop Preview in preview builds. Keep explicit arming separate from selecting Mode. Live Start remains qualification-gated. |
| UX08 | P2 | Five health rows; lengthy missing-temperature and lid/display prose compete with actual numbers. | Horizontal read-only metric badges, normally one row; a second row only when necessary. Move display verification, sensor source, missing-temperature explanation and freshness detail into Details. |
| UX09 | P2 | Thermal pressure and unavailable temperature occupy two rows. CPU varies with one decimal place. | Compact `Normal` pressure label, whole-percent CPU for glance display, full precision in Details/CLI. Show Celsius only for a qualified named temperature source. |
| UX10 | P2 | Empty dashboard retains fixed 560 pt content height and a large blank area before its footer. | Fit normal/empty content on opening; bounded height for long task lists. Preserve scrollable task content and stationary controls. Avoid resize jitter on sensor updates. |
| UX11 | P2 | Dashboard repeats preview/no-power information above and below metrics, including internal milestone `M1`. | One persistent plain-language capability line: `Preview: power control unavailable`. Put qualification details behind Details. Keep urgent safety/recovery errors prominent. |
| UX12 | P1 | Dashboard is Off but its main reason says AC power required, suggesting an error in an intentionally stopped app. | Off is neutral. Show a blocker prominently on a refused Start or an armed session; otherwise include requirements in capability Details. Do not conceal current safety stops. |
| UX13 | P2 | Safety contains `Requested closed-lid intent: Off`, `Override ownership is unknown...`, plus long requirements prose. | One capability result and actionable explanation. Detailed intent/ownership/helper/support-row evidence in disclosure. Unknown ownership must remain Unknown; do not attribute it to LidRun without proof. |
| UX14 | P2 | General includes disabled Launch at login; Activity preferences includes disabled Anonymous telemetry. Activity pane has substantial unused height. | Do not render unusable switches. If an unavailable feature needs explanation, use a concise capability note. Remove speculative remote telemetry control; keep local privacy/retention and Activity access. |
| UX15 | P2 | Settings uses a body segmented picker, fixed title and active green maximize control. Source disables minimize only. | Prefer native, noncustomizable pane toolbar; preserve General/Agents/Safety/Activity labels, remember selection, update pane title, disable minimize/maximize. Fit panes sensibly within screen bounds. |
| UX16 | P1 | Activity shows settings saves as repeated `off → ready`, while dashboard says Off. `sessionStateForRecord()` defaults to ready without a session; row UI draws a transition for every category. | Correct event-state projection first. Present `Settings updated`, `Lid reading available`, etc. as event titles. Show transition arrows only for actual state-transition events. Preserve raw audit evidence in Details/export. |
| UX17 | P2 | Activity reason picker uses raw reason codes; rows expose low-level states and identifiers. | Human-readable titles in rows and filter choices, stable raw code values underneath, expanded event details for diagnostics. Search should support both human labels and raw codes. |
| UX18 | P2 | Activity repeats export/deletion explanations and exposes destructive deletion as a permanent prominent button. | Compact toolbar with Search/Filter and Export. Put clear/delete operations in a secondary native menu; retain explicit destructive confirmation, redaction, failure and receipt feedback. |

UX01, UX05, UX06 and UX08 directly cover the latest user feedback. UX07 is a source-backed workflow finding, not a newly performed Start test. UX16 is visible plus source-supported; investigate category/state semantics before changing history. None of these are implementation acceptance results.

## Proposed dashboard

Hierarchy: effective state → one capability line → Mode and primary action → compact health → useful agent activity → Details and Activity.

Text schematic only, **not a screenshot or implemented UI**. Values below illustrate formatting; they do not represent current readings.

```text
CamLid                             Preview
Stopped
Power control unavailable

Mode  [Auto ▾]            [Start Preview]

[battery 42%] [cpu 18%] [thermal Normal] [lid Open]

No monitored agents

▸ Details                        Activity
```

Actual badges use SF Symbols, not the schematic icon names. Preview designation belongs in the capability line or title treatment, without duplicate warnings. Do not call preview activity Protected or Keeping awake. Armed, waiting, safety-stopped, disconnected and recovery states require their own accurate header copy.

### Metrics

| Metric | Visible content | Detail / accessibility |
| --- | --- | --- |
| Battery/power | Battery symbol, integer percent; plug/charging symbol only when that observation supports it. | Battery percent, AC/battery/unknown supply, charging separately. AC presence is not synonymous with charging. |
| CPU | `cpu` SF Symbol, short CPU label if needed, integer percent. | Full precision, measurement definition, sample age. Keep current sampler normalization. |
| Thermal pressure | Thermometer symbol, Normal/Fair/Serious/Critical/Unknown. | Explain that this is system thermal pressure, not Celsius. Existing safety priority unchanged. |
| Lid | Laptop symbol, Open/Closed/Unknown/Not applicable. | Independent lid observation and age. Display sleep/continuity remains separate and unverified unless actually measured. |
| Temperature, qualified only | Thermometer plus measured number and °C, with concise sensor label if ambiguity exists. | Named sensor, units, source and age. Keep independent thermal-pressure badge; temperature never replaces it. |

Default current unsupported-temperature row is omitted from the glance strip, with `Temperature unavailable` discoverable in Details. This removes clutter, **not the unsupported fact** from status/CLI. Any capability-critical sensor failure still affects the main reason. Never show 0°C for missing data or map Normal to degrees.

Prefer one row at standard 390 pt content width; allow wrapping at narrow width, localization or increased text size. No horizontal scrolling, ellipsis on numbers/units, tiny text or tooltip-only critical information. Metric badges are read-only labels, not action buttons. Details remains keyboard-accessible. Stale/unknown uses explicit text or a distinguishable symbol with an accessible explanation; no silently stale healthy number.

Use stable widths/monospaced digits. Round only the glance presentation, never policy values or CLI serialization. Do not parse preformatted text to recreate metric truth: project existing typed HealthSnapshot observations into a small presentation value, without another sensor framework.

### Dashboard sizing and actions

- Start with a design target of 280-340 pt empty content height, versus current 560 pt; verify rather than shrink text to force it. Actual warning/locale/text needs take priority.
- Standard width stays near 390 pt. Screen bounds and current 260 pt fallback remain test inputs, not a promise that all four badges fit one line everywhere.
- Bound long activity to an internal scroll region. Stop and Mode must remain reachable with 20 tasks or long error messages.
- Compute fit at opening and deliberate disclosure changes; sample ticks must not move controls or reset scroll/focus. Meaningful new content may grow within screen bounds without hiding a focused control.
- Stopped and selected non-Off mode: Start Preview is accessible in dashboard and menu. Off selection: explain selecting a mode before Start; do not silently pick one.
- Active session: Stop Preview. Selecting Off keeps existing explicit stop behavior. Other mode edits keep existing caps/grace/wait anchors; never renew a session by cosmetic refactoring.
- Timed mode can expose its relevant duration preset near Mode using the current bounded duration authority. Do not add an unlimited hold or reset an active deadline. This is a later refinement after the basic Start/Stop path.
- Preserve outside/Escape/app-switch/status-toggle dismissal and owned nested picker behavior. No new global hotkey or event-tap permission.

## Proposed agent badges

Selected appearance means **monitoring enabled**. The single text state means **observed activity or source readiness**. Their meanings stay separate even though redundant On/Off captions disappear. All four providers remain visible and independently selectable; this is not a mutually exclusive segmented control.

| Condition | Single visible state | Selection / AX |
| --- | --- | --- |
| Monitoring disabled | Not monitored | Unselected, muted but readable; AX says detection disabled. Do not pretend observed idle. |
| Enabled, no connected evidence source | Not connected | Selected check/tint; AX says enabled, source disconnected. |
| Fresh working evidence | Active · 2 tasks | Selected; count is real work, not process count. |
| Waiting only | Waiting | Selected; retain existing bounded retention. |
| Fresh explicit idle/terminal evidence | Inactive | Selected; this is the valid Inactive case. |
| Missing/stale/ambiguous evidence | Unknown | Selected; explanation available in details. |
| Working plus unknown sessions | Active · 2 tasks | Selected; unknown count and confidence in details, with a non-color ambiguity indication where needed. |

`Active/Inactive` alone cannot safely cover disabled monitoring, disconnected bridges or stale work. Remove repetitive enrollment copy without inventing activity. Native Toggle/button semantics and `camlid.agent.<provider>` IDs survive; a visually styled badge can legitimately expose AXCheckBox semantics. No separate checkbox-looking widget is necessary.

Badge design: provider name, one compact state line, selected check glyph integrated into the badge; 2 × 2 grid at normal Settings width. Aim for 48-64 pt height and at least 32 pt interactive target. One group container, 8 pt spacing, native font sizes. Narrow/text-expanded layouts wrap vertically. Preserve Orca local-only scope in nearby help/details.

Only successful persistence updates selected state. Slow writes, failures and conflicts remain adjacent to the affected badge; no success flash/footer. Keep keyboard activation, focus indication, readable disabled state and non-color selection. Do not make the activity indicator itself imply that clicking starts/stops an agent.

## Proposed Settings and Activity

Settings changes apply automatically. Closing uses red close or Command-W, retaining the same SettingsCloseGuard and bounded settlement logic. Quiet success does not mean quiet failure: applying feedback after the existing delay, inline errors, Retry, Use current / Apply my value and explicit discard choices all remain. Global errors without a field must have a visible contextual banner, not be deleted with the footer.

Keep the four pane names for this refinement. General contains Mode and completion delay with minimal contextual help. Agents contains badges and collapsed integration instructions. Safety contains one capability summary, battery/power/session limits and Advanced. Activity contains concise local-history/privacy information and access to the Activity window. Never remove ventilation guidance from the product entirely when reducing Safety prose.

Suggested copy inventory:

| Current | Proposed |
| --- | --- |
| Requested mode | Mode |
| 0 enrolled tasks (preview) | No monitored agents, or No agent activity when providers are enabled |
| Start an enrolled local agent… | Context-specific guidance only when useful; explain missing setup without making a false connection promise |
| Thermal pressure: nominal | Normal in thermal badge; full meaning in accessible label/Details |
| Battery floor | Minimum battery |
| Waiting retention | Keep awake while waiting, with brief explanation and existing finite bounds |
| View Activity / Activity Log… / Open Activity… | Consistent Activity naming; preserve menu availability and shortcuts |
| Requested closed-lid intent: Off | Omit this duplicate line; exact intent remains in capability Details |
| Export redacted… | Export…; keep a concise privacy explanation in the export flow |

Activity should primarily answer what happened and when. Configuration events must not look like power transitions. Show natural event names with timestamp/provider where useful, and expand for evidence/confidence/reason/state/IDs. Present full timestamp on expansion; avoid losing date context when grouping. Human-readable filters still select raw stable codes. Keep export redaction, history failure handling, bounded retention and irreversible-delete confirmation.

## Execution plan for the next implementation pass

These are proposed work packages, **not checked tasks**. No new milestone or source files are implemented by this audit.

1. **Contract refinement.** Update spec/interaction/data-model/tasks together before implementation: visual On/Off captions no longer required, enrollment/readiness/activity axes still required; no normal Applied footer; native close preserved; health badges replace rows; preview state stays truthful. Record UX01-18 mapping. Historical checked T035 does not certify the new badge design.
2. **Small copy/control pass.** Mode labels, duplicate enrollment captions, footer removal, disabled speculative telemetry, contextual helper reduction. Preserve native close guard, field feedback and settings authority. Static label edits need no tests that merely repeat strings.
3. **Dashboard workflow and density.** Typed metric projection, wrap behavior, capability warning consolidation, fit-on-open sizing, Start/Stop. Add meaningful state/unknown/safety/arming/deadline regressions. Preserve no activation on background refresh.
4. **Badge and Settings layout.** Compact grid, single evidence state, integration disclosure, pane toolbar/title/window behavior. Reuse projection/autosave, no new monitoring or installation system.
5. **Activity truth and layout.** Reproduce UX16 with controlled ordinary preference edits; fix recorded no-session state if confirmed, distinguish category presentation, retain raw history. Then readable filters, compact toolbar and secondary delete commands.
6. **AI/native review, then user review.** Run canonical settled-source checks after code changes; independent source/contract review; CUA matrix below; then user UI review. This is preview UX review, not the gated M7 full product trial. Hardware/signing/backend prerequisites remain open.

Keep shared SettingsView/AppCoordinator edits sequential. Refactoring a label does not authorize helper/power/backend changes. Existing release gates and unknown source states cannot be cleared by cleaner UI.

## Acceptance matrix

| Area | Required check |
| --- | --- |
| Latest QA | No visible Detection On/Off duplication, Applied footer, explicit Settings Close button or Requested mode label; health uses compact horizontal badges. |
| Enrollment truth | Disabled, enabled/disconnected, active, waiting, fresh inactive, stale unknown, parallel/mixed evidence, failure/conflict; GUI/config agree. No click launches jobs or installs integrations. |
| Metrics | Fresh, missing, stale, invalid, unsupported and no-lid rows; degrees only from qualified sources; supply/charging separate; no healthy-looking stale values. CLI precision/schema retained. |
| Layout | Dark/light, 260/390 pt dashboard widths, 500/580 pt Settings widths, long/localized labels, expanded text, 0/1/20 tasks, multiple warnings; no clipping or horizontal scroll. |
| Interaction | 30 real visible open/dismiss cycles, outside/Escape/status toggle/app switch, nested pickers/disclosures, Settings reopen and remembered pane. Exact screenshot readback, not AX presence alone. |
| Primary action | Start only deliberately; preview never changes power. Stop available when armed, Off stops, refusal reason actionable. Mode and preset edits never renew cap/grace/wait. |
| Autosave/close | Red close, Command-W, Quit, custom input, pending/invalid/conflict/failure/uncertain-write, restart, CLI concurrent edit; bounded settlement and update deferral unchanged. |
| History | Off-mode settings change stays Off in truthful metadata; event vs transition distinction; readable filter/search preserves codes; export redaction and destructive confirmation tested. |
| Accessibility | Real keyboard and VoiceOver: badge selection versus activity, metric name/unit/freshness, toolbar selection, close, disclosure, failures. Increase Contrast/Reduce Transparency/Reduce Motion; color never sole cue. |
| Performance | No sensor-triggered window jitter or focus steal. Existing idle/RSS/dashboard-ready/dismissal/preference timing budgets remain binding; remeasure affected paths only. |

Design target: empty dashboard height reduced by at least 35% relative to current 560 pt at standard settings, while retaining truthful status/actions. Four badges and readiness are visible without scrolling at the standard Settings size. These are future measurements, not current passes.

## Primary references and interpretation

- [Apple HIG: Writing](https://developer.apple.com/design/human-interface-guidelines/writing) supports concise, consistent, useful labels. Removing repetition here is a CamLid design decision.
- [Apple HIG: Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) supports obvious selected/unselected appearance with a non-color cue. Our two-axis badge mapping is a product decision, not an Apple-defined agent convention.
- [Apple HIG: Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) supports a small transient surface. Content-fit sizing and a compact glance strip apply that principle here.
- [Apple HIG: Settings](https://developer.apple.com/design/human-interface-guidelines/settings) informs a stable pane toolbar, pane title, remembered pane and native window controls. Quiet autosave/footer removal comes from the user's requirements, not a claimed HIG mandate.
- [Apple HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) informs alternative state cues and readable content. Icon-only badge designs still need accessible names and keyboard-reachable detail.
- [Apple WWDC25: Make a big impact with small writing changes](https://developer.apple.com/videos/play/wwdc2025/404/) reinforces reducing repetition and keeping vocabulary consistent.

The public HIG page renderer sometimes returned a JavaScript-only shell. Text was cross-checked through Apple's official `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<topic>.json` payloads and indexed Apple results. No third-party UI guidance is treated as Apple policy. This pass did not re-inspect LidRun or borrow its branding; prior comparison remains historical.

## Implementation disposition — 2026-10-05 continuation

This review doc stays the investigation record. Implementation is recorded in
`docs/qa/ui-simplicity-report.md` (code + 335-test/7-check verifier + bounded
native preview) with fresh read-only continuation evidence in
`docs/qa/preview-evidence/ui-simplicity/continuation-2026-10-05.json`,
60 s perf sample, `Tests/UI/QARefinementValidation.md` continuation subset,
`docs/qa/performance-report.md` supplemental note, and
`docs/qa/independent-review-2026-10-05.md` UI addendum (no new Critical/High
beyond the known no-backend/in-memory-journal release blocker).

T046–T052 complete; T053 partial (full 30-cycle/IME/VoiceOver/appearance/device
matrix open, direct popover clicks manual-check); T054 reporting complete with
all hardware/signing/M6/M7 gates explicitly open. M1/M2/M5/M6/M7 predecessors
unchanged.
