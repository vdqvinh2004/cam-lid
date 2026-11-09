# Feature Specification: M5 Signed Beta and Updates

**Feature Branch**: None; numbered folder is feature identity, not Git branch.
**Created**: 2026-10-04
**Status**: Superseded 2026-11-03 by [ADR 0004](../../docs/adr/0004-distribution-through-github-releases.md): no Developer ID, no notarization and no Sparkle; releases are ad-hoc signed zips on GitHub built by `scripts/release.sh`. History below is kept.
**Input**: CamLid milestone M5: Sparkle update integration, signing/notarization, helper lifecycle, migrations and supported build revalidation. One scoped feature folder per user instruction.
**Prerequisites**: M2, M3, M4, M4a. Roadmap.
**Scope**: Sparkle update integration, signing/notarization, helper lifecycle, migrations and supported build revalidation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Check and defer updates (Priority: P1)

User or reviewer obtains verified milestone outcome: Current/available/offline/error states; active protection defers update installation.

**Why this priority**: Required to deliver signed beta and updates and protect downstream gates.
**Independent Test**: Current/available/offline/error states; active protection defers update installation.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** Current/available/offline/error states; active protection defers update installation.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### User Story 2 - Install and remove safely (Priority: P2)

User or reviewer obtains verified milestone outcome: Fresh signed/notarized install, denial, migration, helper mismatch, OS build change, tampered update rejection and uninstall cleanup verified.

**Why this priority**: Required to deliver signed beta and updates and protect downstream gates.
**Independent Test**: Fresh signed/notarized install, denial, migration, helper mismatch, OS build change, tampered update rejection and uninstall cleanup verified.

**Acceptance Scenarios**:
1. **Given** milestone prerequisites, **When** scoped validation runs, **Then** Fresh signed/notarized install, denial, migration, helper mismatch, OS build change, tampered update rejection and uninstall cleanup verified.
2. **Given** missing evidence or failed mandatory check, **When** gate evaluated, **Then** report
   blocked/failed and prevent dependent milestone from claiming completion.

### Edge Cases
L07–L12, L17, L19; OS/helper change invalidates unsupported closed-lid capability. Failed prerequisites, unsupported versions, absent evidence and accidental
simulation-as-hardware claims must remain visible. Limitations.

## Requirements *(mandatory)*

### Functional Requirements
Stable FR identifiers refer to shared product requirements, not a second set of product defaults.
Scope statements below narrow delivery ownership; complete invariants/values remain authoritative
in product specification.

- **FR-013**: Deliver scoped behavior for product FR-013: Release owned resources and verify restoration with failure-class timing. Full numeric invariants remain in product source; delivery limited to stated milestone scope.
- **FR-019**: Deliver scoped behavior for product FR-019: Provide trusted signed update checks and defer installation during protected work. Full numeric invariants remain in product source; delivery limited to stated milestone scope.

### Key Entities
Relevant evidence/state follows [data-model.md](data-model.md); shared runtime definitions
remain in domain model.

## Success Criteria *(mandatory)*

### Measurable Outcomes
- **M5-SC-001**: Every listed install/upgrade/removal/update trust case records expected and actual outcome; no failed mandatory cleanup or signature check before signed beta is eligible for M6.

**Milestone exit gate**: Distribution trust and owned-state cleanup verified before external test; unresolved recovery prevents installer/removal success claims.

## Assumptions
Scoped preview preparation is authorized. Signed candidate install/upgrade/remove and update trust tests still require predecessor evidence and distribution credentials.
Tests required where scoped validation changes safety, detection, native UX or release behavior.
Checked component tasks do not establish physical feasibility or signed distribution acceptance. M0 completed documentation work does not establish runtime support.

## Added M4a dependency (2026-10-05)

[Apple HIG UI/UX milestone](../009-apple-hig-ux/spec.md) is required before this milestone final approval. Preparation may overlap; the accepted candidate must include M4a evidence and no unresolved critical/high UX finding. M4a does not replace M1 physical recovery or other existing gates.

## Current implementation boundary

The initial controller uses Sparkle information-only probes. It does not download, install or relaunch updates. Developer ID identity/team, signed-bundle HTTPS feed and a 32-byte Ed25519 verification key are required before a probe starts. Session/work/uncertainty/recovery/dirty-draft blockers defer explicit requests; repeated clicks do not queue probes. Current/available/offline/error/unavailable/deferred states are tested with a stub, not a claimed live feed. Preview and local archives cannot satisfy M5-SC-001.
