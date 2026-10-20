# Native Interaction Acceptance Contract

No new runtime API. GUI consumes existing M2/M3 contracts. Preserve stable accessibility IDs where possible; intentional changes update tests atomically.

## Essential actions

Open dashboard; open options; choose mode; Stop; open Settings; navigate settings sections; correct/save a value; resolve revision conflict; opt into an agent without automatic installation; open/filter history; export/cancel; delete/cancel; open diagnostics; close a window; Quit. Settings uses Command-comma when an app window is active; Quit uses Command-Q. Escape dismisses transient dashboard. Menu bar activation follows macOS keyboard navigation; no global shortcut required.

## Ten state cases

Off; ready/no active work; working with verified capability (fixture only until qualified); waiting; unknown/stale activity; completion grace; safety stopped; unsupported backend; preview/unverified lease; recovery required/restore failed. A fixture cannot enable host power. Mode selection is a request, never verification. Unknown lid/battery/CPU is explicit. Display observation does not prove system sleep. Preview grace says simulated/preview timing, never promises sleep.

## Surface rules

Dashboard: effective status + reason first, accessible Stop, mode, compact tasks/health and optional details; standard anchored transient behavior; fits visibleFrame and scrolls overflow. Options: native command grouping; Settings…, Activity, diagnostics, updates eligibility and Quit; unavailable actions explain prerequisites through adjacent text or accessible help, not tooltip alone.

Settings: General, Agents, Safety, Activity with advanced disclosure; unit labels and field errors; preserve user draft on failed save; explicit discard/cancel before abandoning dirty draft. Reopening clean settings reloads persisted values. Never duplicate system appearance controls.

Activity: clear empty/loading/error states, readable reason/session filters and redacted export outcome; destructive deletion confirmation; storage errors visible. Onboarding: brief purpose/limitations, user-controlled enrollment, concise next step and optional later access.

## Appearance and layout matrix

Light/dark; Increase Contrast; Reduce Transparency; Reduce Motion; larger supported text settings; keyboard/VoiceOver; 1x/2x scaling where available; notebook notch-constrained visible area; external display and edge anchoring. Use 20 tasks, long labels and unknown telemetry. Record actual tested rows; unavailable hardware rows remain blocked. Critical actions and reasons cannot clip or depend on color/animation/hover.

## Evidence rules

Each case records build/source hash, OS/display settings, action, expected/actual and method. CUA checks cannot substitute for actual VoiceOver output or physical display/sleep observation. Existing performance SC-005 is measured in M6. Screenshots exclude unrelated content and agent prompts; fixtures contain no sensitive work.

## Implemented presentation conventions (2026-10-05)

System fonts, semantic primary/secondary colors, native grouped forms, segmented sections, template SF Symbol status item and native NSPopover chrome. Stop/mode stay above the scrolling task list. Background refresh replaces view data without activating the app; explicit dashboard opening may activate for interaction. Settings uses a revision-aware editor; invalid raw text and stale drafts are retained. Close/Quit ask before discarding. General/Agents/Safety/Activity section choice persists; no system appearance override. Power capability stays unavailable in preview. Synchronous history reads expose empty/error states; export cancellation/success/failure and deletion receipts are explicit.

## Planned QA refinement supersession (2026-10-05)

[010 QA UX/sensors](../../010-qa-ux-sensors/spec.md) defines the next design: no dashboard Options, preset/Custom numeric choices, per-field automatic application instead of Save, and accessible agent badges. These supersede the conflicting interaction choices above only upon implementation/validation. Existing screenshots/component passes remain historical; no native/full M4a gate is passed by the new plan.

## Current scoped follow-up (2026-10-07)

The [010 interaction contract](../../010-qa-ux-sensors/contracts/interaction.md) now records implemented Start/Stop parity, key popover focus and consumed Escape, three-page read-only Welcome with live observations and retryable completion, color-independent badge selection, and request-correlated Activity loading/refresh with fixed top controls. Updates presentation joins the transient UI helper; parent retains authority. Settings applies valid edits automatically and retains bounded close/conflict handling. These replace conflicting historical presentation conventions above. [Current evidence](../../../docs/qa/uiux-implementation-2026-10-07.md) is scoped; full appearance/hardware/performance acceptance remains open.
