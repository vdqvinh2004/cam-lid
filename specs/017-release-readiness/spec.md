# Feature Specification: Release readiness for v0.1.0

**Status:** Planned. Owner decisions recorded; no implementation started.
**Depends on:** [016 Strict trials](../016-strict-lid-only/spec.md), [ADR 0004](../../docs/adr/0004-distribution-through-github-releases.md), [ADR 0005](../../docs/adr/0005-stable-signing-certificate-for-the-helper-pin.md).
**Blocks:** the first public release.

## Problem

The first release would report a state the code cannot reach and show wording the owner does not want.

- **Readiness is hardcoded to Preview.** `AppCoordinator.protectionReadiness()` passes `buildKind: .preview` (around line 779). `ProtectionReadiness` checks Preview before Protected (around line 108), so the readiness state is never `protected` in any build.
- **CLI and Dashboard disagree.** `camlid status` writes `protection.effectiveState = "Preview"` and `state = "preview"` (around line 1540). The Dashboard shows Protected when a lease is verified (`powerActuationAvailable: holdReconciler.leaseVerified`, around line 1013).
- **Preview wording reaches users and tools.** Reasons `previewPowerDisabled` (with the copy "Preview mode does not control system power."), `commandNotAvailableInPreview` (around line 1619), `modeOffPreview` (around line 1710) and `backendPendingM1` (status list around line 1499, admit stub around line 1559, Activity text). JSON replies carry `preview: true`. The notification code has a "CamLid Preview:" branch in `OutcomeNotifications.swift` (dead today, because callers pass `preview: false`).
- **The `start` reply is constant.** It always reports `powerActuation: false`, even while the helper holds a lease.
- **The release script can ship ad-hoc by accident.** `scripts/release.sh` falls back to ad-hoc signing when `CAMLID_SIGN_IDENTITY` is unset. This happened on 2026-11-05.
- **Release text is out of date.** `README.md` says "pre-release, unsigned"; the release notes say "Pre-release. Tested on one Mac".
- **A slow lid read ends healthy sessions.** `LiveSensorProvider.finish()` marks a lid reading `slowSensorRead` when the whole sample takes more than 0.2 s, and the session stops with `lidUnknown`. On 2026-11-05 this happened at about 95 % CPU. The budget counts scheduling delay as well as the sensor call.

## Owner decisions (2026-11-05)

1. The release shows no Preview wording anywhere a user or a tool can see it.
2. The release is the standard build: signed with the release certificate, and no switch that exists only for testing is exposed by default. Strict visibility is open question Q-A.
3. Sensor stalls are measured before any tolerance is added (User Story 2).

## User Scenarios & Testing

### User Story 1 — Status and Dashboard say the same thing (P1)

When a verified lease holds the Mac awake, `camlid status` and the Dashboard both report protected. When nothing holds, both report ready or the true blocker. No Preview word appears in CLI replies, Activity rows, notifications or release notes.

**Acceptance**
1. Release build with a verified lease: status `protected`, Dashboard Protected.
2. Release build without a lease: status `ready` or the real blocker, never `preview`.
3. A test that builds the status reply with release facts finds no `preview` text.

### User Story 2 — A slow sensor read does not end a healthy closed-lid session (P1)

**Measurement gate (decided before coding).** On Mac17,3 with all ten cores busy for three minutes, record for each lid sample: (a) the time of the sensor call alone, (b) the time from sample start to finish.

- If (a) stays under 0.2 s, the cause is scheduling delay. Fix: time only the call, and move sampling to a queue with higher quality of service. No tolerance window.
- If (a) exceeds 0.2 s, a window is allowed within these limits: at most 5 seconds; only while the last good lid sample said *open* and is younger than 5 seconds; a *closed*, missing or stale reading stops the session at once.
- If the gate is inconclusive, no window. Unknown must never act as healthy.

**Acceptance**
1. Three minutes at 100 % CPU with a closed-lid session active: no `lidUnknown` stop.
2. A stalled source in a test stops the session within the window limit.
3. The gate result is recorded in the QA addendum.

**Why not stop at once, always:** healthy sessions end under load and users lose work.
**Why not a window, always:** during a window a closed lid, possibly in a bag, stays awake. The product refuses that case.

### User Story 3 — Only a verified release is published (P1)

1. `scripts/release.sh` stops when `CAMLID_SIGN_IDENTITY` is unset, unless `--adhoc` is passed. Ad-hoc output is named with an `ADHOC` suffix.
2. Release notes come from a template with: certificate fingerprint, helper version, CDHash table, tested configuration (Mac17,3, macOS 26A434), known limits, and the Strict line.
3. Private vulnerability reporting is enabled for `vdqvinh2004/cam-lid`.
4. Publication happens only after the owner approves.

## Requirements

- **FR-001** Build kind comes from the build configuration: Release → release, Debug → development. No hardcoded value.
- **FR-002** Readiness reaches protected only from evidence: verified lease, qualifying safety and requested intent. Blockers name real causes.
- **FR-003** Remove Preview from status and start replies, reason codes, Activity text, notification code and release text. Renamed reason codes stay parseable for one version.
- **FR-004** `camlid start` reports `powerActuation` from the lease.
- **FR-005** Sensor timing as in User Story 2.
- **FR-006** Release gating as in User Story 3.
- **FR-007** `README.md` status, signing and install text match the signed release.

## Success Criteria

- **SC-001** No Preview string in CLI replies of a release-equivalent test build.
- **SC-002** Status and Dashboard agree at every checkpoint of a live session.
- **SC-003** A three-minute full-load closed-lid session ends only when the owner stops it.
- **SC-004** The release script refuses ad-hoc builds by default.

## Open questions

- **Q-A — Strict in the release. Decided 2026-11-05: yes, visible.** "Strict (experimental)" stays in the release, labelled as ADR 0003 decision 8 requires. Its label does not use the word "Preview".
- **Q-B — Window or no window. Decided 2026-11-05: yes, decide by measurement.** The gate in User Story 2 chooses. If the gate is inconclusive, there is no window.

## Out of scope

- Notarization and Developer ID (see 020).
- New features (see 018 and 019).
- Changes to the Standard or Strict mechanisms.
