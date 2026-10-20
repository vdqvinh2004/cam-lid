# Feature Specification: QA-driven UX and truthful telemetry

**Feature Branch**: None; feature context `010-qa-ux-sensors` (no Git repository).
**Created**: 2026-10-05
**Status**: Planned; this request authorizes investigation/design only.
**Input**: Remove dashboard Options, dismiss outside, numerical temperature, real lid state, remove Settings section label, resolve unavailable closed-lid protection, presets with Custom last, automatic preferences without Save Changes, clickable agent badges; compare installed LidRun Pro.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Predictable dashboard (Priority: P1)

Left-click opens dashboard; right/Control-click opens options. Read effective state, change mode and Stop without duplicate navigation.

**Why this priority**: Frequent interactions with reported defects.
**Independent Test**: Repeat open/dismiss cycles on preview, without power changes.
**Acceptance Scenarios**:

1. Given a closed dashboard, when left-click opens it, then status/reason, mode, Stop and health appear without Options.
2. Given an open dashboard, when clicking outside, pressing Escape, switching apps or clicking its status item again, then it closes without changing mode.
3. Given an inside control or nested selector, when interacting, then it remains usable and is not dismissed by its own events.
4. Given a right/Control-click or keyboard menu request, when options open, then Settings, Activity, updates and Quit remain reachable with only one surface open.

### User Story 2 - Preferences without Save (Priority: P1)

Select common numeric presets, with Custom… last. Valid ordinary preferences apply immediately; failures and conflicts are visible beside the control.

**Why this priority**: Less input and clear effective configuration.
**Independent Test**: Change each preference, read it through the status/config interface, reopen and restart.
**Acceptance Scenarios**:

1. Given Settings, when navigating sections, then neither “Settings section” nor Save Changes is visible; section names remain accessible.
2. Given a numeric preference, when selecting a preset, then its value applies immediately; input appears only for Custom….
3. Given custom text, when empty/incomplete/wrong-typed/out of range, then the last valid setting stays effective and an inline error identifies the issue.
4. Given valid custom text, when editing pauses or commits, then it applies automatically; pending/write failure remains visible and retry retains the candidate.
5. Given external edits, when a local field changes, then unrelated values survive; a same-field conflict preserves both values for deliberate resolution.
6. Given pending input, when closing/quitting, then valid writes settle or failure is explained; invalid input never applies silently.

### User Story 3 - Truthful temperature and lid readings (Priority: P1)

Read a measured, named temperature when qualified, thermal pressure separately, and independently measured lid state.

**Why this priority**: Hardware telemetry affects trust and protection.
**Independent Test**: Independent sensor comparison and supervised lid open/close/reopen; unsupported paths need no power actuation.
**Acceptance Scenarios**:

1. Given a qualified fresh temperature source, when health appears, then show degrees/unit, sensor identity and freshness, never degrees invented from pressure.
2. Given failed/unsupported/stale temperature, when health appears, then show unavailable/stale and separately report thermal pressure.
3. Given fresh lid observations, when changing the lid, then GUI/status agree on Open/Closed; absent evidence is Unknown or Not applicable on hardware without a lid.
4. Given a closed lid, when assessing protection, then display sleep/system continuity are not inferred from lid state.

### User Story 4 - Clickable agent badges (Priority: P2)

Toggle Orca/Codex/OpenCode/Claude detection through badges; distinguish detection enabled from connected sources and active work.

**Why this priority**: Enrollment currently resembles runtime activity.
**Independent Test**: Toggle badges and replay existing working/waiting/idle/stale/parallel fixtures, without paid jobs.
**Acceptance Scenarios**:

1. Given detection Off, when clicking/keyboard-activating a badge, then detection becomes On after persistence succeeds, without installing hooks.
2. Given On without a connected source, when shown, then say No source connected, never Active.
3. Given fresh work, when shown, then say Active with count; waiting/idle/unknown have separate text.
4. Given parallel Orca sessions, when one ends while another works, then remain Active; disappeared sessions become bounded Unknown.
5. Given active evidence, when detection is disabled, then existing bounded unknown policy handles evidence loss, never fabricated completion.

### User Story 5 - Qualified closed-lid protection (Priority: P1)

Understand exact prerequisites and use protection only on qualified hardware after recovery tests pass.

**Why this priority**: Core purpose; a cosmetic enabled switch cannot solve power limitations.
**Independent Test**: Capability fixtures explain blockers without actuation; M1 physical gate proves real support.
**Acceptance Scenarios**:

1. Given preview/unqualified hardware or missing helper, when inspecting protection, then show the specific blocker and next step without claiming protection.
2. Given another utility owns a persistent override, when assessing readiness, then refuse competing ownership without overwriting it.
3. Given M1-qualified hardware and integrated safety, when deliberately armed, then verify continuity and internal-display sleep separately, with safety/Stop/runtime precedence.
4. Given completion/Stop/manual Sleep/app or helper failure, when releasing, then record observed restoration or unresolved recovery; command acceptance is insufficient.

### Edge Cases

- Rapid left/right activation, reopen during dismissal, nested menus, lock/unlock, multiple Spaces/displays, notch/edge geometry, keyboard-only input.
- Missing/wrong-typed/conflicting sensors; desktop without lid; fanless hardware; multiple temperature sensors; sensor name/units/freshness changes; unsupported OS.
- Input composition, pasted decimal/negative/huge numbers, locale separators, Custom matching a preset, externally loaded non-preset values, rapid edits, disk full.
- Concurrent external edits, restart/write failure, quit during retry, update readiness during pending input.
- Enabled-but-uninstalled agent, disconnected bridge, ambiguous Orca identity, stream EOF, parallel work, disabled integration with current work.
- Pre-existing LidRun holds, corrupt recovery journal, helper mismatch, partial restore/manual Sleep. CPU is never proof of work completion or thermal safety.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Dashboard MUST omit Options; right/Control-click and keyboard options MUST remain.
- **FR-002**: Dashboard MUST dismiss on outside click, Escape, app switch and repeated status activation; inside controls MUST work.
- **FR-003**: Stop/effective reasons/preview labels/constrained layout MUST survive; background refresh MUST not activate.
- **FR-004**: Settings MUST remove visible section label and Save Changes while keeping accessible navigation.
- **FR-005**: All four editable numeric preferences MUST offer valid presets followed by Custom…; raw input appears only for Custom….
- **FR-006**: Valid preferences MUST apply automatically; incomplete/invalid custom input MUST preserve last valid configuration.
- **FR-007**: Persistence MUST be atomic, preserve unrelated concurrent edits, and retain candidates with explicit same-field conflict/write-failure recovery.
- **FR-008**: Close/Quit/update readiness MUST account for pending/invalid/failed edits; reopening/restarting MUST show persisted values.
- **FR-009**: Temperature MUST be qualified measurement with degrees/unit/sensor/source/freshness; pressure MUST remain separate and authoritative for existing thermal safety.
- **FR-010**: Lid MUST expose fresh Open/Closed or Unknown/Not applicable; lid alone MUST NOT prove display sleep or continuity.
- **FR-011**: Sensor failure/staleness MUST appear in GUI/status and bounded transition logs; unavailable temperature MUST NOT become zero/healthy proof.
- **FR-012**: Agent badges MUST be clickable and accessible, separating selected monitoring intent, source readiness and Active/Waiting/Inactive/Unknown work. Remove duplicated visible On/Off captions; accessible values retain enrollment state.
- **FR-013**: Enrollment MUST NOT silently install hooks/edit provider files/submit prompts/purchase services; disabling MUST preserve conservative bounded evidence handling.
- **FR-014**: Protection MUST explain build/hardware/helper/recovery/conflict blockers; requested intent, verified capability and actual protection MUST differ.
- **FR-015**: Live closed-lid support MUST require M1 physical/recovery qualification and integrated safety; preserve external ownership and manual Sleep.
- **FR-016**: GUI/status/config MUST share policy, bounded private logs, accessibility and safety deadlines; preferences MUST NOT implicitly arm privileged sessions or extend leases.
- **FR-017**: AI quality review/native checks MUST precede supervised users; simulation MUST NOT count as physical support evidence.

### Key Entities

- Preference edit: field, persisted value/revision, candidate, pending/invalid/conflict/failure and outcome.
- Numeric choice: preset or Custom, unit and validated bounds.
- Health observation: type/value/unit/source/sensor/freshness/unavailable reason.
- Agent badge: provider, detection intent, readiness, activity/count and evidence age.
- Protection capability: qualification row, prerequisites, ownership/recovery, intent and verified actuation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Thirty dashboard open/dismiss cycles per tested appearance row pass without stuck surfaces/unintended mode changes; outside dismissal visible within 250 ms of delivered input.
- **SC-002**: Valid discrete changes persist and appear in status within 1 second on healthy local storage; defined invalid/conflict/failure matrix never overwrites unrelated valid settings.
- **SC-003**: Every health reading has availability/freshness; qualified lid changes appear within 2 seconds while awake; temperature meets source/reference tolerance per advertised support row.
- **SC-004**: All four badges distinguish On-but-disconnected/active/waiting/idle/stale; parallel completion never labels continuing work inactive.
- **SC-005**: Zero critical/high AI QA findings; every primary action keyboard tested; appearance, performance and privacy budgets pass.
- **SC-006**: Every advertised closed-lid row passes continuity/display/restoration matrix; no unqualified row shows Protected or permits live arming.
- **SC-007**: After AI QA PASS, at least four of five supervised users open/dismiss dashboard, change preset/custom and interpret badge/protection without coaching; zero safety/restoration failures.

## Assumptions

- Preset-first covers completion delay, waiting retention, battery floor and session cap; no speculative numerical thermal threshold.
- Active/Inactive describes observed work; Detection On/Off is separate intent. Disconnected is not evidence of inactivity.
- Custom applies after a short pause or field commit; setup and session arming remain explicit.
- Apple native conventions govern. LidRun is comparison/conflict evidence, not a runtime dependency.
- M1–M7 and L01–L20 remain binding. Honest unsupported temperature rows may ship; complete closed-lid product still requires qualified support.
- M4b refines M4a with engineering SC-001–006 before M5 final acceptance/M6 and user SC-007 after M6 in M7; supersedes only its Options/Save/raw-number/checkbox choices, without retroactive acceptance.

## Approved simplicity refinement (2026-10-05)

User authorized implementation of UX01-18 in ui-simplicity-review.md. This supersedes visible On/Off captions, health rows and Applied/Close footer choices only. Existing safety/evidence/history/unknown/deadline/power gates remain. T046 onward tracks this increment separately.

- **FR-018**: Settings omits normal Applied/footer/Close button; native close and Command-W preserve bounded settlement and inline/global failure feedback.
- **FR-019**: Visible label is Mode; dashboard exposes deliberate contextual Start/Stop, with no implicit arming or deadline renewal.
- **FR-020**: Horizontal wrapping metrics project typed observations, keep missing/stale explicit and temperature qualified; diagnostics and full precision remain in Details/CLI.
- **FR-021**: Dashboard fits empty content and bounds long lists; background refresh preserves focus/scroll/size; preview line appears once, stopped is neutral and refusal/safety notices remain prominent.
- **FR-022**: Compact independently selectable agent badges show one readiness/activity line; integration detail is collapsed, pending/conflict/failure stays adjacent.
- **FR-023**: Native stable Settings panes remember selection and update title; unusable speculative controls omitted, capability/privacy/ventilation retained.
- **FR-024**: Activity distinguishes events/transitions, records truthful no-session state and provides readable searchable/filterable labels with raw codes preserved; export/redaction/confirmed deletion remain.

## User scope revision — 2026-10-05

VoiceOver acceptance removed at the user’s explicit request. Keyboard access, meaningful labels, visible focus and non-color state equivalents remain required. Historical VoiceOver NOT RUN records remain historical, not failures or passes for this revised scope.

Passive supervision supersedes bridge/setup requirements and detection opt-in semantics in US4/FR-012–013. The running app observes bounded same-user executable metadata and Orca local status without hooks, configuration edits, daemon installation or prompts. Dashboard shows detected agents independently of sleep selection; Settings badges select which observed agents may delay sleep and offer Enable all. Process-only presence is Unknown, never working/idle/completed evidence. Mode choices are visible clickable badges. Metrics are text badges; Details contains one compact source/capability block. Existing backend/sensor/recovery qualification and privacy bounds remain.

Completion uncertainty, including selected standalone process presence or stale discovery, may end its bounded hold but cannot start completion grace or emit a sleep request. This supersedes earlier bounded-Unknown→completion-grace interpretation. Safety, cap, Off and recovery precedence remain.
