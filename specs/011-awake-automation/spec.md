# Feature Specification: M8 Awake Automation & Diagnostics

**Feature context**: `011-awake-automation`; documentation only, no branch created.
**Owner correction — 2026-10-13:** [Third-person agent observation](../../docs/planning/third-person-agent-observation-2026-10-13.md) overrides the older agent integration/launch-wrapper path in this milestone. CamLid must not participate in agent workflow or wrap/relaunch an agent to obtain lifecycle evidence. Passive exact lifetime rules are not working/completion evidence. Existing diagnostics/notifications/safety/physical gates otherwise remain; legacy wrapper source is not claimed removed.
**Created**: 2026-10-08
**Status**: Partial implementation; integrated acceptance and hardware gates remain open.
**Input**: Compare LidRun with current CamLid, recommend useful gaps and better behavior, and create a milestone with all implementation tasks.

## User Scenarios & Testing

### User Story 1 — Understand why this Mac is awake (Priority: P1)

A user opens the existing diagnostics window or requests a terminal report and sees which applications prevent system or display sleep, whether a global sleep setting blocks it, and what CamLid actually owns.

**Why this priority**: Useful immediately, including Preview, without changing host power.
**Independent Test**: With no active CamLid session, inspect known system/display blockers and unsupported data; GUI and terminal agree and neither changes power settings.
**Acceptance Scenarios**:

1. **Given** another application's system-sleep hold, **When** diagnostics refresh, **Then** its owner and system-sleep effect appear separately from display holds and recent user activity.
2. **Given** incomplete or unavailable observations, **When** a report is requested, **Then** partial coverage, freshness, and failure reasons are visible; absent data never means no blockers.
3. **Given** a saved Timed default with no session, **When** status is inspected, **Then** configured mode is distinct from active session and physical protection.

### User Story 2 — Apply display preference to qualified sessions (Priority: P1)

A user starts Auto or Timed and can rely on the existing Allow display sleep setting being applied on a qualified backend.

**Why this priority**: A persisted preference alone does not deliver the requested behavior.
**Independent Test**: On a qualified support row, allow display sleep and observe work continuing with the display asleep; disable it with lid open and observe the display remaining awake. Stop releases only owned resources.
**Acceptance Scenarios**:

1. **Given** a verified backend and Allow display sleep enabled, **When** a session starts, **Then** CamLid prevents system idle sleep without holding the display awake.
2. **Given** a lid-open session with display sleep disabled, **When** the preference changes during the session, **Then** the owned display hold updates without restarting its timer; failure is explained.
3. **Given** a closed lid, safety stop, quit, or ownership loss, **When** resources are evaluated, **Then** no internal-display hold defeats the closed-lid display-sleep requirement, and Stop/safety/restoration take precedence.
4. **Given** Preview or an unqualified combination, **When** a user enables a mode, **Then** the UI reports missing protection rather than claiming physical keep-awake.

### User Story 3 — Keep awake for one terminal command (Priority: P1)

A developer opts into safety-governed keep-awake for the existing command wrapper, preserving command input/output and exit behavior.

**Why this priority**: Exact child lifetime is stronger evidence than guessing whether an agent process is working.
**Independent Test**: Wrap a short command, observe admission and hold lifecycle, then repeat with denied admission, app loss, safety stop, and direct-child exit.
**Acceptance Scenarios**:

1. **Given** a qualified running app and explicitly armed Auto, **When** a developer requests a protected command, **Then** protection is admitted before the child launches and releases when that direct child exits.
2. **Given** unavailable or denied protection, **When** protected execution is requested, **Then** the command is not launched and a reason is returned; existing unprotected wrapper behavior remains available.
3. **Given** a running protected command, **When** Stop, safety, or owner loss occurs, **Then** protection is revoked without killing the child; late messages cannot re-arm it.
4. **Given** detached descendants, **When** the direct child exits, **Then** their completion is not asserted or used to request sleep.

### User Story 4 — Watch an explicit app or process lifetime (Priority: P2)

A user adds a rule for an unsupported workload and understands that the rule holds while the selected program exists, without claiming AI task completion.

**Why this priority**: Covers builds and tools outside the four supported agent integrations.
**Independent Test**: Select one exact program, explicitly arm Auto, launch/exit it, and exercise PID reuse, stale data, concurrent matches, Stop, and unknown observations.
**Acceptance Scenarios**:

1. **Given** an enabled rule and explicitly armed Auto, **When** its exact selected program is present, **Then** its lifetime hold and reason are shown separately from agent work evidence.
2. **Given** missing, stale, truncated, or failed observations, **When** matches disappear, **Then** CamLid reports unknown, respects bounded uncertainty, and does not claim completion or initiate sleep from that disappearance.
3. **Given** a stopped or safety-stopped session, **When** the watched program remains alive, **Then** no rule re-arms the app until a new explicit activation.

### User Story 5 — Request sleep with an explanation first (Priority: P2)

A script can ask whether sleep would be allowed, then request it only when work, interaction, and restoration checks pass.

**Why this priority**: Makes completion automation reviewable and avoids ambiguous stop-versus-sleep behavior.
**Independent Test**: Dry-run all allowed/blocked/unknown cases without power mutation; physically verify one eligible sleep request on a qualified row.
**Acceptance Scenarios**:

1. **Given** active work, an awake display with open lid, recent input, uncertain telemetry, or unverified restoration, **When** sleep is requested, **Then** the request is rejected with all applicable reasons.
2. **Given** a closed lid or all displays confirmed asleep, no recent input or active/unknown tracked work, and verified restoration, **When** sleep is requested, **Then** requested and independently observed sleep remain distinct outcomes.
3. **Given** Preview, **When** dry-run or actual sleep is requested, **Then** dry-run explains blockers and actual sleep never changes host power.

### User Story 6 — Receive useful local alerts (Priority: P2)

A user opts into local notifications for completion, failure, safety stops, and restoration problems.

**Why this priority**: Useful without accounts, phone services, or remote data transmission.
**Independent Test**: Enable/deny permission, replay duplicate transitions, flood ordinary events, and inject a critical safety event; alerts remain accurate and bounded.
**Acceptance Scenarios**:

1. **Given** alerts disabled or permission denied, **When** an event occurs, **Then** no permission prompt repeats and Activity retains its normal reason.
2. **Given** alerts enabled, **When** repeated messages describe the same transition, **Then** only one alert appears; a first critical safety/restoration alert is not suppressed by ordinary-event limits.
3. **Given** Preview or a sleep request without observation, **When** an alert is shown, **Then** it does not claim actual protection or successful physical sleep.

### User Story 7 — Start the app at login without starting a session (Priority: P2)

A user enables Launch at login in app Settings and sees the actual operating-system registration state.

**Why this priority**: Finishes a currently stored but ineffective preference.
**Independent Test**: Register, revoke approval externally, disable, and relaunch/login; state is reconciled and startup never activates a mode.
**Acceptance Scenarios**:

1. **Given** login registration needs approval or fails, **When** the user enables it, **Then** Settings explains the actual state rather than showing a successful preference alone.
2. **Given** enabled login startup, **When** the app launches, **Then** saved defaults remain intact, recovery follows existing ownership rules, and no previous session is resumed.

### Edge Cases

- Other applications own assertions or global settings; reports explain them without deleting or overriding them.
- Display disconnected is not display asleep; aggregate assertion flags do not guarantee physical sleep or closed-lid support.
- Clock/wake changes, child signals, app/helper crash, stale receipts, PID reuse, rule overlap and collector truncation.
- Infinite has no session deadline; renewable ownership leases and battery/thermal safety still apply.
- Stale work evidence blocks explicit sleep; lifetime-only rules never prove task completion.
- Notification denial, OS login approval changes, uninstall/update cleanup and concurrent preference revisions.

## Requirements

### Functional Requirements

- **FR-001**: Extend the existing diagnostics surface with shared terminal reporting; distinguish system/display/user-activity effects, owner, observation time and coverage.
- **FR-002**: Explain global sleep-disable state and available kernel/device blocker categories using read-only observations; unavailable categories remain explicitly unknown.
- **FR-003**: Distinguish configured mode, active session, requested hold, verified protection, and restoration in GUI/terminal status; never infer activity from saved defaults.
- **FR-004**: Diagnostics must refresh on demand, remain bounded, redact exports by default, and collect no command arguments, prompts, code or transcripts.
- **FR-005**: Use the previously qualified shared power backend; this milestone must not duplicate backend feasibility, ownership or crash recovery work.
- **FR-006**: Apply Allow display sleep during active sessions. Default allows display sleep; a requested display hold applies only with lid open. Closed-lid internal display sleep remains mandatory.
- **FR-007**: Stop, safety, ownership expiration and quit override all holds. Infinite has no maximum-session deadline; finite timers and Auto retain their existing limits. Runtime duration edits restart from the edit instant; defaults remain separate.
- **FR-008**: Add opt-in protected execution to the existing command wrapper; verified admission precedes child launch, and denied admission launches nothing.
- **FR-009**: Preserve child input/output and exit/signal behavior without logging arguments/output; direct-child exit releases its hold, without claiming detached descendants are complete.
- **FR-010**: Wrapper ownership must expire after lost owner/renewal, reject replay, and never bypass central battery/thermal/restoration policy; revocation must not kill the child or allow automatic re-arming.
- **FR-011**: Allow at most 20 explicit lifetime rules matching an exact executable selection or application identity; reject wildcard/substring/regex and generic system targets.
- **FR-012**: Rules affect only explicitly armed Auto, use stable process identities, respect current safety/deadline policy, and report presence as a lifetime reason separate from AI activity.
- **FR-013**: Fresh complete observations are required to declare absence. Observation failure/uncertainty must not trigger completion sleep; Stop suppresses rule activation until the next explicit session.
- **FR-014**: Add terminal sleep dry-run and guarded sleep requests; reject active/unknown tracked work, recent interaction, open-lid awake/unknown displays, unknown telemetry, and unverified restoration.
- **FR-015**: Explicit sleep has no force bypass; Preview never actuates, and requested/observed/blocked/unknown remain separate outcomes.
- **FR-016**: Add opt-in local notifications for completion, failure, safety and restoration outcomes; request permission only from explicit enablement and show denial without repeated prompts.
- **FR-017**: Deduplicate alerts by session/event/reason, bound ordinary alerts, and retain the first critical safety/restoration alert for each distinct reason in a session.
- **FR-018**: Make Launch at login operational, reconcile actual OS approval/registration, and unregister through normal disable/uninstall flows; login never re-arms a session.
- **FR-019**: Place persistent preferences and lifetime-rule editing in Settings; retain runtime mode/duration/Auto-delay controls on Dashboard. Agent Settings retain detected/not-detected CLI information without live task status.
- **FR-020**: Use native controls, whole-row disclosures, keyboard access, meaningful labels, text plus symbols, and adaptive light/dark layouts; avoid idle filler rows and duplicate mode controls.
- **FR-021**: Persist only necessary preferences/rules with existing atomic revision-aware storage; retain private bounded transition history and redact diagnostic exports.
- **FR-022**: Deliver deterministic policy/contract/security tests, native walkthrough evidence and supervised physical evidence for affected support rows; simulator results cannot pass physical power gates.

### Key Entities

- **Diagnostic snapshot**: Observed blockers, effects, owners, freshness, coverage and actual CamLid ownership.
- **Protected command admission**: Session-bound revocable ownership and direct-child lifecycle evidence.
- **Lifetime rule and match**: Explicit exact program selection; stable process identity; present/absent/unknown observations.
- **Sleep decision**: Fresh inputs, reasons, restoration and requested/observed outcome.
- **Notification preference/outcome**: Opt-in category, actual permission and deduplication identity.
- **Login registration**: User intent separately from actual OS state.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All seeded system/display/global/unknown diagnostic cases produce matching GUI and terminal explanations; each refresh finishes or reports partial failure within 5 seconds.
- **SC-002**: On every qualified affected support row, both display preferences and session Stop/safety/quit produce the expected physical results; zero foreign power settings/resources are overwritten.
- **SC-003**: Every protected-wrapper admission/revocation/exit/failure scenario preserves expected child behavior; every lost-owner hold starts release within the agreed 30-second healthy-executor lease bound.
- **SC-004**: All rule identity, fresh absence, stale/replay/truncation, Stop and safety scenarios pass; zero presence-only observations are reported as AI completion.
- **SC-005**: Every unsafe or unknown sleep case is blocked; eligible requests are separately recorded as requested and observed, with physical evidence for every claimed support row.
- **SC-006**: All permission, duplicate, ordinary-rate-limit and critical-alert cases pass; no notification claims an unobserved physical outcome.
- **SC-007**: Enable/approval/revoke/disable/login/update/uninstall cases reconcile actual registration correctly and start zero sessions automatically.
- **SC-008**: Native walkthroughs cover keyboard, light/dark, disclosure rows, error/empty states and window sizes with zero unresolved critical/high defects; exports contain no arguments, transcripts or unredacted identities by default.

## Assumptions

- Single-user local Mac workflow; no account, remote service, general rule engine or dependency added.
- Current diagnostics, Auto/Timed/Infinite, runtime pickers, safety controls, agent detection and history are existing baseline; extend them, do not rebuild them.
- M1 selects and qualifies power mechanisms; M2 implements owned resources/recovery. M8 consumes their accepted output and does not bypass M5/M6/M7 release gates.
- Default proposed bounds and interaction threshold are detailed in the contracts; changes need recorded rationale and validation, not a new preference for every constant.
- Fan/charging control remain outside v1. Remote push/webhooks, weekly reports, schedules, GUI command launcher, arbitrary scripts and forced sleep are deferred.
- LidRun capabilities are vendor-advertised unless explicitly confirmed by the read-only CLI inventory; closed-lid behavior has not been physically compared.
