# Feature Specification: M4a Apple HIG UI/UX Refinement

**Feature Branch**: None; folder identity is independent of Git.
**Created**: 2026-10-05
**Status**: Planned; documentation only in this change.
**Input**: Add a milestone to improve CamLid UI/UX following Apple Human Interface Guidelines.
**Prerequisites**: Existing M2/M4 preview for design and simulated validation; integrated M3/M4 behavior for final validation. Executes before M5 release readiness and M6 PASS.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Understand and control status at a glance (Priority: P1)

As a coding user, I open the menu bar dashboard, understand whether protection is actually available, see why it stopped, and change mode or stop without searching.

**Why this priority**: Ambiguous status can cause unsafe assumptions about a closed MacBook.
**Independent Test**: Walk through every dashboard state with deterministic inputs and both pointer and keyboard navigation, without actuating power.

**Acceptance Scenarios**:
1. **Given** a running app, **When** I left-click its menu bar item, **Then** one anchored dashboard opens; right-click or Control-click opens quick options; options are also reachable from the dashboard with a keyboard.
2. **Given** unsupported, preview, unknown, stale, safety-stopped or recovery-required status, **When** I read the dashboard, **Then** requested mode and effective outcome are separate and the reason and next action are readable without relying on color.
3. **Given** an active session, **When** I change mode, **Then** the original cap remains fixed; Stop remains immediately reachable; preview never claims real protection or an actual sleep countdown.

### User Story 2 - Configure confidently and understand history (Priority: P2)

As a user, I find common settings quickly, opt into integrations knowingly, correct invalid values, and understand/export a session decision.

**Why this priority**: Clear structure reduces setup mistakes while keeping advanced options accessible.
**Independent Test**: Change a valid preference, correct an invalid value, handle a stale revision, inspect a log and cancel export/deletion using test storage.

**Acceptance Scenarios**:
1. **Given** Settings, **When** I navigate General, Agents, Safety and Activity, **Then** related controls are grouped and advanced options use progressive disclosure with explicit units and consequences.
2. **Given** an invalid value or concurrent configuration edit, **When** I save, **Then** a specific error appears near the field or affected section, the draft is preserved, and no partial save is implied.
3. **Given** history or integration unavailable, **When** I open its view, **Then** empty, loading and error states are distinguishable; unsupported commands explain their unavailability.
4. **Given** onboarding or an integration toggle, **When** I review it, **Then** backend limitations and integration side effects are clear and enabling a toggle never silently changes provider configuration.

### User Story 3 - Use familiar accessible Mac interactions (Priority: P1)

As a keyboard user, I operate all essential controls and retain context across window changes and background updates.

**Why this priority**: Accessibility and predictable focus are core native behavior, not visual polish.
**Independent Test**: Repeat US1/US2 using keyboard under appearance/accessibility settings and constrained screen layouts.

**Acceptance Scenarios**:
1. **Given** a background telemetry update, **When** it arrives, **Then** focus stays in my current app/control and timers do not repeatedly announce unchanged context.
2. **Given** a dashboard, **When** I press Escape or click outside, **Then** it closes predictably; explicit Settings/Activity actions focus a single existing window; closing/reopening reflects persisted state and handles unsaved drafts explicitly.
3. **Given** dark/light appearance, Increase Contrast, Reduce Transparency or Reduce Motion, **When** I use the app, **Then** text, controls and statuses remain readable with no essential information hidden by effects.

### Edge Cases

No agents; 20 tasks; long provider/version names; unknown battery/CPU/lid; failed storage/export; stale config revision; expired cap; unverified restoration; hidden status item on a notch-constrained display; multiple displays/scaling; menu open during refresh; window close with unsaved changes; reduced transparency; larger text; backend unavailable. Fixture screenshots never establish physical power safety.

## Requirements *(mandatory)*

### Functional Requirements

Local UX identifiers supplement shared product FR-001/002/014–018/021 and do not redefine safety defaults.

- **UX-001**: Preserve left-click dashboard and right-click/Control-click options; provide keyboard access to equivalent actions.
- **UX-002**: Prioritize effective state, explanation and Stop, followed by requested mode, task summary and health; advanced diagnostics remain secondary.
- **UX-003**: Use familiar macOS controls, typography, semantic colors and restrained symbols; status always has text. Decorative effects must not obscure information.
- **UX-004**: Separate preview/unavailable/requested mode from verified protection, observed sleep and restoration; unknown values stay explicit; disabled actions explain why.
- **UX-005**: Group Settings by user purpose with units, validation, preserved drafts and revision conflict handling; existing limits and defaults remain unchanged.
- **UX-006**: Provide meaningful loading/empty/error/history states, explicit export outcomes and confirmation for destructive history deletion; retain private redaction semantics.
- **UX-007**: Essential actions support keyboard with meaningful labels, values, order and visible focus; no color-only or hover-only information.
- **UX-008**: Dashboard and windows fit the visible display area; long text wraps or reveals full content; large task collections scroll; background updates never steal focus.
- **UX-009**: Respect system appearance, contrast, transparency and motion preferences; avoid duplicating system-wide preferences.
- **UX-010**: Onboarding communicates unsupported closed-lid behavior, unsaved-work and ventilation limits, opt-in integrations and a next step without repeated blocking prompts.
- **UX-011**: Maintain a source-linked HIG review with each criterion mapped to a control, test case and recorded result; exceptions require rationale. No claim of Apple certification.
- **UX-012**: UI refinements preserve shared GUI/CLI configuration, policy, safety priority, original session deadlines and log privacy.

### Key Entities

- **Presentation state**: Effective outcome, requested mode, verified capability, reason, task/health freshness and next action.
- **Settings draft**: User edits, original revision, validity and save/conflict outcome.
- **HIG review case**: Source guidance, affected surface, expected behavior, evidence and disposition.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **UX-SC-001**: All ten state cases in the interaction contract distinguish actual capability from requested mode; zero misleading protected/restored/sleep claims.
- **UX-SC-002**: Every essential action in the interaction contract can be completed by keyboard without a pointer; zero focus traps or background focus steals in the walkthrough.
- **UX-SC-003**: All specified appearance/layout cases pass with readable reasons and reachable Stop; zero clipped critical actions or missing text equivalents.
- **UX-SC-004**: Every invalid-setting, conflict, export-failure and delete-cancel case preserves expected data and gives a specific outcome; GUI and CLI agree after save.
- **UX-SC-005**: Every applicable HIG review item has source, case, evidence and disposition; no unresolved critical/high UX defect. M6 performance budgets still apply.

## Assumptions

Apple HIG is design guidance; project-specific criteria are identified separately. Native preview work can proceed without M1 power actuation. This milestone refines existing M4 surfaces and owns new HIG acceptance evidence, not provider bridges, packaging or power implementation. M4 tasks are not duplicated or marked complete by this plan. Real-user usability outcomes remain M7, after M6 PASS. Acceptance requires native interaction tests and meaningful regression tests for changed presentation, settings conflicts and GUI/CLI agreement. This request authorizes planning documents only.

## User scope revision — 2026-10-05

VoiceOver acceptance removed at the user’s explicit request. Keyboard access, meaningful labels, visible focus and non-color state equivalents remain required. Historical VoiceOver NOT RUN records remain historical, not failures or passes for this revised scope.
