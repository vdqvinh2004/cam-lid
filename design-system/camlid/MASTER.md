# CamLid Native Design System

Current UI contract, updated 2026-10-07 from the [UI/UX audit](../../docs/qa/uiux-review-2026-10-07.md).
Native macOS utility: SwiftUI content, AppKit menu/popover/window hosting. macOS 14 minimum.
Apple HIG governs behavior. See the [SwiftUI/HIG source review](../../docs/qa/swiftui-hig-research-2026-10-07.md).

## Visual rules

System typography, semantic primary/secondary labels, system accent and SF Symbols.
Use 8/12/16 pt spacing, native corners/materials and monospaced digits for changing values.
Capability and safety text must remain legible; no color-only state. Provider selection adds
an explicit circle/check indicator, independently of observed work. Native focus remains visible.
No decorative gradients, custom fonts, charts or perpetual animation. Respect system appearance,
Reduce Motion, Reduce Transparency and Increase Contrast. Full device/appearance acceptance
requires current runtime evidence; documentation does not establish it.

## Menu bar and dashboard

Native SF Symbols template: idle laptop, Auto arrows, Timed timer, and warning laptop for safety stops; no permanent CPU/battery clutter. Unknown/unavailable never
claims verified protection. Left-click toggles the dashboard; right/Control-click opens native
options. Settings supports Command-comma. Parent and UI-helper menus use Auto instead of Start; Stop appears only during a session.
Keep matching enablement, Command-D/L/period/Q shortcuts and guarded actions.

One compact status/action header, concise preview capability notice, two mode actions (Auto/Timed),
Timed duration, Auto Sleep when done, adaptive icon/value metrics, working-selected providers, bounded countdowns and
Activity. System status badges (battery, CPU, thermal, lid) are pinned above the scroll, always visible. Running rows below show only working enabled providers. Detection-disabled rows stay in Settings.
Empty text says No selected agents reporting work; Settings shows CLI installation detection.
Click Auto/Timed to start; click the active mode again to stop. No Off button. Timed offers finite duration or ∞ Infinite; Infinite has no maximum-session deadline and retains every battery/thermal/AC safety stop. Only active Timed shows a duration picker. Editing it starts the new duration now; active Auto instead shows Sleep when done. Stopped shows neither picker. Dashboard edits affect the current session; Settings Defaults apply to future sessions. Switching to Infinite removes the time limit only before any battery exposure; returning to Auto measures its limit from the original session start. Auto → finite Timed can shorten its deadline using the original start. Finite deadlines never extend or restart on fresh work. Manual remains only for wire compatibility. Settings has no mode controls. Unknown never means Done.

Working-provider rows use a terminal icon/count rather than redundant Active text; omit the
positive working-agent summary. Timer/Activity use system icons with explicit native labels/help.
Keep mode names, status and capability/safety/error meaning readable. Start/Stop buttons are removed; keyboard menu commands remain. Suppress the
redundant Ready-to-start subtitle. [Icon provenance and mode behavior](../../docs/qa/icon-ui-2026-10-07.md).

Battery, CPU, pressure and lid remain distinct; numerical temperature requires a named fresh
reader. Temperature never substitutes for pressure or proves protection. Each metric uses its
own SF Symbol plus a value; help/accessibility names retain the source and meaning. Dashboard
Details is removed by user request; history retains event diagnostics, Settings owns finite session limits; the dashboard owns duration and Sleep when done.
Content height follows the rows, with bounded scrolling at constrained sizes. Important state,
reason and mode actions stay above the scrolling metrics/providers. Width and height respect screen bounds.

The transparent anchor cannot transfer keyboard focus: focus the presented popover explicitly
on show, never during telemetry refresh. Escape closes once and is consumed so it does not
trigger Cancel/Skip in another window. Outside clicks and app switching retain their native
input; monitors are scoped to the visible popover and released on close. Restore status focus.

## Settings

Native singleton preference window with stable, noncustomizable Defaults/Agents/Safety/Activity
navigation; last pane retained, pane title reflects selection. Grouped fields, concise units,
presets/Custom, validation beside the control, quiet successful autosave. Failures/conflicts remain
visible with Retry/Use current/Apply my value. Native close/Command-W/whole-app quit preserve
bounded settlement and explicit unapplied-edit disposition. No Save button or success footer.

Defaults exposes Timed duration (including Infinite) and Sleep when done for new sessions. Agents shows four full-width CLI installation rows and Enable all. Dashboard and Welcome also use full-width rows, including odd counts. Installed CLI detection never depends on running task status. A running process without lifecycle
evidence remains Unknown internally;
selection controls sleep relevance, not observation or provider launch.
No bridges, hooks, provider configuration changes, setup diffs or external service installation.

Safety explains Preview only in one short sentence; no engineering blocker disclosure. Require charger remains on by default; separate Allow battery sessions opt-in remains off. Both must permit battery use. Start on battery at or above and Battery session limit reuse native preset/Custom fields with inline validation; entry stays strictly above the stop floor. Caption discloses drain, best-effort macOS behavior and Preview's no-power limit. Stop below battery level and Session time limit name the actual stop conditions. Inline captions explain that Auto and finite Timed share the limit, while Infinite ignores it only on AC. Battery exposure imposes min(session limit, battery limit) from the original session start; AC return, mode switches and timer edits cannot extend that ceiling. Advanced explains waiting for agent input and the optional 90%-CPU-for-2-minutes stop; thermal stops always apply. Active menu-bar symbols render explicitly white because native status buttons can ignore template tint. Auto hides the timer countdown and its reserved space. Timed includes 5/10/15-minute choices below a 15-minute cap. Advanced expands or collapses when its full row is clicked; retain native keyboard and disclosure semantics. Preferences never arm
power. CPU/numeric temperature alone are not completion or thermal-safety proof. Unavailable startup settings are omitted.

## Welcome

Three read-only pages: current capability; live observed agents and selection; limits/controls.
Keep explicit no-power behavior, ventilation and sensor uncertainty.
Explain mode actions and Activity using the same labels as their controls. No disabled future
consent controls or hypothetical permission ceremony. Finish awaits a bounded authority
acknowledgement, shows failure/Retry, preserves preferences and records completion once.
Replay never resets closed-lid or telemetry consent. Skip leaves settings untouched.

## Activity

Search stays at the top in loading, refreshing, empty, no-match, failure and populated states.
Type/Reason filters share available width; initial height follows the first readable snapshot. Clear restores all local results.
Retain previously loaded rows while refreshing; identify stale rows on read failure and offer
Retry. Ignore stale request replies, preserve local filters and row identity, and never raise
or reopen a window on a background response. Export/deletion require readable settled data.

Click any part of an Activity row header to expand/collapse; expose Expanded/Collapsed and preserve stable row identity. Readable reasons and state come before raw diagnostic codes. Raw-code search and full redacted
export remain supported. Deletion stays secondary and confirmed; outcomes state what happened.
History retention/privacy policy remains 14 days or 20 MiB without prompts/code/transcripts.

## Updates and UI lifecycle

Dashboard, Settings, Welcome, Activity and Updates are rendered by the transient UI helper.
The parent owns policy, preferences, history, CLI and update-check authority. Updates is a
snapshot/action projection; no download/install command exists. Unsigned/untrusted distribution
is explicitly unavailable without a useless disabled action; checks defer for work, recovery and unresolved edits. Compact update content has no forced vertical spacer. Snapshot decoding
cannot enable installation. Closing the helper's last surface releases the process and its UI caches.
Keep the accepted fork-per-open latency tradeoff; no speculative prewarming or scene rewrite.

## 2026-10-15 Operate refresh (implemented, verification deferred to an AC session)

Dashboard answers in order: state header → next event (pinned countdowns above the
scroll, `camlid.dashboard.next`) → working agents → metrics below the fold. Countdown rows
moved out of the scroll without changing `preferredHeight` accounting. Empty working state
keeps the summary line and adds a `Choose agents…` link-button (`camlid.dashboard.chooseAgents`)
that opens Settings at the Agents pane via the `settings(section)` UI event; no IPC or policy
change. No scroll anywhere: the popover fits its content exactly. System badges sit above; agent rows below list working providers only. The hint
summary and Choose agents action appear only when no agent is selected for detection —
enabled-but-idle shows no agent section. Auto (dashboard badge and menu item) disables
with no selected agent; Timed stays available. Popover height is formula-driven
(base 144 with 20pt top padding: empty 129, one row 170, hint +30, +26 native chrome)
and verified against SwiftUI fitting size at exact width plus live Quartz bounds and AX frames.
Activity rows show relative time (`2m ago`) with the absolute timestamp in help;
a count line (`camlid.activity.count`) states `N records` or `M of N records` under filters.
All Settings panes share one scroll container (`camlid.settings.scroll`) so Safety content
cannot clip. No model, identifier, policy or backend change; semantic colors, focus, help
and VoiceOver labels preserved.

## Guarantees and validation

No protection claim without backend/support-row/lease/recovery verification. Lease expiry or
IPC loss alone cannot prove restoration. Preview UI work does not pass M1/M2 physical safety,
M5 distribution, M6 full quality or M7 user-trial gates. VoiceOver acceptance remains excluded
under existing scope; semantic labels/roles/values and keyboard behavior remain required.
See [implementation evidence](../../docs/qa/uiux-implementation-2026-10-07.md) for verified cases
and [subsequent compact UI feedback](../../docs/qa/compact-ui-2026-10-07.md). Older screenshots/reports are historical and are not current acceptance evidence.

Prior mode/disclosure follow-up and LidRun feature decisions: [review and evidence](../../docs/qa/mode-disclosure-lidrun-2026-10-07.md).

Current duration/defaults follow-up: [review and evidence](../../docs/qa/mode-defaults-2026-10-07.md).
