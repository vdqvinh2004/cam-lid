# Native interaction contract

## Dashboard (US1; FR-001–003)

Left-click toggles an anchored NSPopover. Right/Control-click closes the dashboard before native options. Keep effective status/reason first, all four Mode button badges and contextual Start/Stop always visible; read-only wrapping icon/value badges show battery/power, CPU, independent pressure, lid and qualified temperature. Metric help and accessibility labels retain sensor meaning/source; Activity retains event diagnostics and Settings owns timing limits. Dashboard Details is removed by explicit 2026-10-07 user feedback; no Options button or redundant settings shortcut. Empty content-height target 180 pt, bounded scrolling for overflow. Native spacing/fonts/semantic colors/SF Symbols; no copied LidRun branding or product screenshots as app assets.

Close on outside mouse down, Escape, actual app deactivation and second status click. Inside controls and their owned menus count as inside. Use one dismissal owner; exclude the status anchor from both local and global outside-click handling. If required, scoped local/global mouse monitors plus deactivation notification; no keyboard event tap/TCC permission just for dismissal. Retain one set only while open; remove on close/quit; avoid reopening from the same mouse event. Changing rootView on refresh must not re-show/re-key. Delegate close reconciles visibility; restore keyboard focus appropriately without stealing other apps' focus.

Opening explicitly makes the popover window key and transfers first responder to its host; telemetry refresh never does. Only status icon/text combine into one accessibility element; interactive Start/Stop stays separate. Consume the local Escape event when dismissing the popover so it cannot activate Skip in Welcome behind it.

Native evidence must prove visible dismissal, not merely missing AX nodes; hidden AXPopover presence is not failure by itself. 30 cycles include real delivered outside events. Menu commands opening another window alone are not an outside-click test.

## Settings (US2; FR-004–008,016)

Native titled singleton Settings window, four sections General/Agents/Safety/Activity, no visible “Settings section”; accessible group name remains. Native grouped rows, label left/control right; unit in choice label, no duplicated text. Advanced disclosure for infrequent settings. No Save Changes/footer status wall. No Applied success footer or explicit Close button. Native close/Command-W retain settlement; inline delayed Pending and persistent failure/conflict where necessary; preview explanation belongs near protection control, not every setting.

Presets/Custom and bounds follow data-model.md. Selecting Custom itself does not save or replace the existing value. Focus lands in custom field with current value; Return/focus loss or 400 ms pause applies valid text; Escape cancels current unapplied edit only. Ordinary boolean/mode/preset changes commit immediately; immutable validation/atomic revision-aware patch applies through the same authority as CLI. Preserve all unrelated keys, including future configuration fields. Do not rebuild whole Configuration from defaults.

Provide Use current / Apply my value for same-field conflict; Retry for write failure. Failed/pending state never gets checkmark “Applied”. Selecting an agent toggle twice while pending coalesces final intent and does not launch duplicate setup. Switching sections keeps pending candidate visible on return. Close/Quit use bounded settlement from data model; successful settings remain applied even if another edit is discarded. Updates remain deferred while unresolved edits exist. No preference edit resets runtime/grace/wait anchors.

## Agent badges (US4; FR-012–013)

Four compact wrapping native button badges (2×2 at standard width). Each shows provider
name and one observed state/count. The 2026-10-07 QA follow-up supersedes the original no-check-glyph choice: an outlined circle or selected checkmark supplements fill, border width and native
selected state to communicate whether an agent may delay sleep without hue alone. Enable all selects all four.
Pointer, Tab, Space/Return actions agree; name/value describes provider, sleep relevance,
observed work and readiness, with stable camlid.agent.<provider> identifier.

Observation always runs independently of selection. Settings displays all observations; dashboard displays only selected providers reporting working tasks, matching the 2026-10-06 UX refresh.
Fresh working/waiting/idle Orca evidence is distinct from stale or process-only Unknown.
Not detected means no current process or lifecycle evidence. Settings selection filters sleep
policy and the dashboard's working-provider projection only. Empty dashboard says “No selected agents reporting work”; it never proves every observed agent idle. No bridge/hook/provider configuration or background-service setup flow. Local
Orca scope and standalone task uncertainty stay in read-only evidence. Agent badges display Task unknown and a short visible sentence explains that process presence cannot establish working/idle state.

## Protection readiness (US5; FR-014–015)

Replace generic “unavailable” with a concise capability row and blocker-specific explanation. Examples: “Preview — power control disabled”, “Needs helper approval”, “This Mac/macOS combination is untested”, “Another utility controls sleep”, “Recovery required”. “Review requirements…” opens existing capability/help details; no decorative disabled toggle without explanation. Ready/Armed/Protected are different. Preview fixtures remain clearly preview and cannot change host power.

Current preview supersession by user feedback: Safety shows Preview only and one sentence explaining that this build cannot keep the Mac awake or prevent lid-close sleep. Remove redundant engineering blocker/closed-lid preference disclosure. Preserve AC/battery/session/waiting/CPU controls and ventilation guidance. CLI readiness evidence remains available; no backend is enabled by this presentation change.

Further dashboard feedback: working-provider rows use provider mark/name and icon/count, omitting redundant Active/positive summary. Duration and Activity use icons with native help/accessibility names; preserve important mode/Start/Stop/state/capability text. Omit only the redundant Ready-to-start subtitle. [Current icon UI/provenance/mode explanation](../../../docs/qa/icon-ui-2026-10-07.md). Timed/Manual behavior remains finite and unchanged; no infinite timer implemented.

M1 selects backend only after physical evidence. This feature adds readiness presentation and acceptance integration, not an alternative shortcut around that gate. Do not issue LidRun start/stop/sleep/fan commands from badge/settings flows or take ownership of its helper.

## Accessibility/layout

Keyboard on every primary action; VoiceOver acceptance excluded by user request; light/dark, Increase Contrast, Reduce Transparency, Reduce Motion; system text sizing where supported; 1x/2x/edge/notch/multiple display rows. 20 task rows and long localized labels must scroll without clipping critical actions. Numeric status announces name/unit/availability; avoid live announcements every sample. Announce meaningful safety/availability changes once. Preserve existing IDs where meaning unchanged; intentionally retired Options/Save IDs update native tests/documentation.

## Simplicity increment (FR-018–024)

Native Settings pane toolbar is noncustomizable, remembers selection and changes pane title; minimize/maximize disabled. Dashboard/menu/Welcome use Start/Stop with a readable “Power control unavailable” capability line and explanatory help. Off is neutral unless an attempted action fails. Content-fit empty dashboard target ≤364 pt, bounded scroll for long lists, no numeric refresh resizing. Activity event titles distinguish configuration/sensor events from state transitions; human labels preserve raw filtering/export codes. Deletion remains secondary and confirmed. See ui-simplicity-review.md for UX01-18 mapping and native acceptance.

Unknown evidence is not completion: release bounded protection without completion grace or a sleep request. Selected unattributed standalone processes and stale discovery likewise block a completion-sleep request. CLI detectionEnabled retains its schema name and means selected to affect sleep, not observation enrollment.

## Implemented QA follow-up (2026-10-07)

Welcome has three read-only pages: purpose/capability, current agent observations, limits/controls. Completion does not patch configuration or reset consent. Finish waits for a request-correlated acknowledgement, shows pending/failure/Retry, and records completion once; replay is idempotent. Keep ventilation, sensor uncertainty and recovery limits.

Activity keeps search/Clear and Type/Reason/action rows at the top for populated, empty, no-match, loading and failure states. Reads have request IDs; ignore late/duplicate replies. Refresh retains rows and expansion/filter state, marks stale data on failure, offers Retry, and does not raise a background window. Export/delete require confirmed available records. Human reasons and state precede selectable raw codes.

Updates is presented in the same owned transient UI helper as other surfaces. Parent UpdateController retains check/Sparkle authority and deferral guards. No installation action exists. Closing the last surface releases the helper. [Implementation evidence](../../../docs/qa/uiux-implementation-2026-10-07.md) records scoped passes and remaining matrix rows; no full milestone gate is implied.
