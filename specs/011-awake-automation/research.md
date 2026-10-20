# Research: M8 Awake Automation & Diagnostics

**Date**: 2026-10-08. Installed CLI read-only inventory plus official LidRun and Apple sources; [comparison](lidrun-comparison.md) owns detailed source links. Spec Kit research delegation reviewed vendor pages independently. No remaining design clarification; hardware qualification remains an explicit execution gate.

## 1. Incremental scope

**Decision**: Seven workflows: shared diagnostics, display preference integration, protected command wrapper, exact lifetime rules, guarded sleep, local alerts, and operational login startup.
**Rationale**: They fill demonstrated gaps. Auto/Timed/Infinite, battery/thermal/CPU policy, icon/tooltip/disclosure work, read-only diagnostics and history already exist. Current live backend does not.
**Alternatives considered**: Copy every competitor feature; duplicate M1/M2; build an automation framework. Rejected as unnecessary and misleading.

## 2. Power and display semantics

**Decision**: Consume the M1-qualified/M2-owned backend. Default system-idle prevention allows display sleep. Explicit lid-open display-awake preference adds only an owned display assertion. Never keep the internal panel awake with lid closed. Reject unknown lid when a requested display hold cannot be safely qualified; report actual availability.
**Rationale**: Apple distinguishes [system idle prevention](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep) from [display idle prevention](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep). Idle assertions alone do not establish closed-lid support. Existing product language prohibiting any display hold predates the user's explicit display preference request; see plan scope amendment.
**Alternatives considered**: Always display-on; `DeclareUserActivity` pulses; unowned `pmset` mutations. Rejected: incorrect behavior or ownership/safety violation.

## 3. On-demand diagnostics

**Decision**: Share typed snapshots with CLI; reuse SleepDiagnostics collection and add bounded read-only `/usr/bin/pmset -g assertions` / `-g custom` fallback/augmentation only for global/kernel categories not exposed by the existing public reader. Fixed executable/arguments; no shell and no privileged changes. One collection at a time, 5-second total deadline, 64 KiB combined output, 256 reported owners, partial errors explicit.
**Rationale**: Existing [IOPMCopyAssertionsStatus](https://developer.apple.com/documentation/iokit/1557072-iopmcopyassertionsstatus) and per-process reader cover user assertions. OS output is variable and not proof of physical sleep. Existing OrcaPoller has bounded-output handling; extract only a shared concrete runner if both callers need identical cancellation, never a general process framework. No periodic status-tick subprocess.
**Alternatives considered**: Activity Monitor scraping, full logs, wake-history analytics, arbitrary process killing. Rejected: noise, privacy and unreliable causality. General last-wake history deferred.

## 4. Command wrapper ownership

**Decision**: Extend `camlid run --keep-awake -- <argv>`; existing run remains evidence-only. App admits a session-bound job before launch. Same-user authenticated channel, opaque admission ID, boot ID and monotonic sequence; renewal every 10 seconds, 30-second expiry using continuous elapsed time. Lost ownership initiates release but never kills the child. Revoked jobs cannot reacquire without a fresh user command.
**Rationale**: Existing RunCommand preserves direct-child IO/exit; IPC and policy already exist. LidRun's independent wrapper lacks app battery/thermal safety when app is absent ([official CLI](https://lidrun.com/blog/lidrun-cli-keep-awake-terminal)). All protected work should share CamLid safety. Lease timing applies to a healthy executor; joint failure/OS hangs retain existing limitations.
**Alternatives considered**: Standalone raw assertion wrapper, login-shell argument joining, automatic app start/re-arm. Rejected: safety bypass, quoting drift, hidden activation. Protected wrappers join only an existing explicit Auto session; never alter Timed or defaults.

## 5. Exact lifetime rules

**Decision**: User-selected exact executable path or bundle identity, same-user observations, at most 20 rules. Hold only while explicitly armed Auto. Separate lifetime projection from NormalizedEvent AI work states. Stable identity uses PID + process start time + UID; exact executable metadata rather than truncated process names. Two complete absent observations 5 seconds apart establish lifetime end; collection failure becomes unknown immediately, bounds its hold at the existing wait policy, and never triggers completion sleep.
**Rationale**: Process presence is useful when explicitly requested as lifetime protection, but cannot prove AI activity/completion (constitution II). A lifetime epoch that participates in Auto release is marked ineligible for completion-triggered sleep; release returns control to OS idle policy. A later distinct epoch with exact task-completion evidence may use existing Auto completion policy.
**Alternatives considered**: Arbitrary regex/substring patterns, CPU heuristics, broad condition/action DSL. Rejected: accidental permanent holds and weak evidence.

## 6. Guarded sleep

**Decision**: `camlid sleep --dry-run [--json]`, and explicit sleep with identical revalidated admission. Fresh lid/display/input/work data <=5 seconds old; no input for at least 60 seconds; lid closed or all connected displays confirmed asleep; zero active/waiting/unknown tasks or lifetime matches; restoration verified. Unknown blocks. No `--force`. Preview refuses actual sleep. M2 owns actual backend sleep request/restoration.
**Rationale**: Existing PowerController restoration gate is reusable but insufficient for explicit in-use checks. A request is not observed sleep. Recent-input measurement must be qualified; absence of a collector is not zero activity.
**Alternatives considered**: Immediate force sleep, stopping foreign blockers, new GUI Sleep Now button duplicating macOS. Rejected; safe CLI workflow suffices.

## 7. Local notifications

**Decision**: Native UserNotifications, user-requested permission only. Opt-in categories; 5 ordinary alerts per rolling 10 minutes, dedup by session/event/reason. First critical safety or restoration failure per distinct reason/session bypasses ordinary budget, while replay does not. No CLI arbitrary message endpoint or outbound webhook.
**Rationale**: [Apple authorization](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)) covers permission and status; local-first keeps payloads private. Settings carries persistent categories; Activity remains the bounded source of reasons.
**Alternatives considered**: Phone push, accounts, arbitrary plugin alerts, silent authorization at launch. Deferred or rejected.

## 8. Login startup

**Decision**: `SMAppService.mainApp` registration/unregistration, actual status reconciliation at app launch and Settings activation. Distinguish user intent, enabled, requiresApproval, notRegistered, notFound/error. Default off; never resume/arm sessions at login.
**Rationale**: [Apple main app service](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) is native and available from macOS13, below project minimum14. Denied/revoked approval must remain visible. Current launchAtLogin Boolean is intent, not OS state.
**Alternatives considered**: Custom LaunchAgents, privileged startup, copying plist files. Rejected; platform already solves registration.

## 9. Explicit exclusions

Fan and charging writes remain outside v1. Fan licensing != hardware support (installed fanControlSupported=false). No general schedules, weekly metrics, remote alerts, GUI launcher, forced sleep, unsupervised hardware claims, full VoiceOver acceptance, or new dependencies. Keyboard and semantic labeling remain required under the existing user scope revision.
