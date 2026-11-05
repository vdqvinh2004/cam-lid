# Feature Specification: v0.3 — coverage, Vietnamese, maintenance

**Status:** Planned. Starts after v0.2 ships.

## Problem

- The UI is English only. The repo has no `.lproj` or String Catalog. LidWalk ships English and Vietnamese.
- Hardware evidence covers one Mac (Mac17,3, macOS 26A434). The untested-Mac gate keeps everything else off.
- A helper source change without a `PowerHelperVersion` bump would reach users silently; the ADR 0005 rule is manual.
- `camlid simulate` reads built-in defaults, not the user's stored configuration (`CommandContext` default in `Commands.swift`), so a simulation cannot reproduce a user's settings.
- `camlid start --mode` overwrote the saved mode from `timed` to `auto` during testing.
- Spec tracking: 28 tasks `[~]` and 6 `[ ]` across specs 002–011. Some notes link to `docs/qa` and `docs/planning`, which `.gitignore` excludes.

## Requirements

- **FR-001 Localization.** English and Vietnamese through a String Catalog, covering Dashboard, Settings, Activity, Onboarding, Updates, menu items, notifications and help text. Dates and numbers follow the locale. Machine codes in CLI JSON stay unchanged.
- **FR-002 Hardware breadth.** Qualify one more Mac model or macOS build with the existing procedure (sensor matrix). Until then the untested-Mac gate stays.
- **FR-003 Helper change guard.** A script fails when `Packages/CamLidPowerHelper/Sources` differs from the last release tag and `PowerHelperVersion.current` did not change. It runs inside `release.sh`.
- **FR-004 Simulation with the user's configuration.** `camlid simulate --use-current-config` reads the stored configuration. The default stays unchanged and is documented.
- **FR-005 `start` does not persist the mode.** Persistence only through `config set mode`. Release note for the change.
- **FR-006 Spec hygiene.** No `[~]` without a reason; references to ignored directories replaced by tracked paths or removed; `specs/README.md` updated.
- **FR-007 Audio holds, research first.** Read other processes' power assertions before considering audio sampling. Build only if the research shows a reliable signal, and record the decision.
- **FR-008 Remaining owner tests.** T026 (lid transitions; temperature stays blocked without a reference), T306 (battery stop-level session with the lid closed), grace in a real session, a VoiceOver walkthrough, and notch and second-display checks.

## User Scenarios & Testing

### User Story 1 — The app speaks Vietnamese (P1)
Switching to Vietnamese shows no English on the Dashboard, Settings, Activity, Onboarding or Updates.

### User Story 2 — A helper change cannot ship unnoticed (P1)
A deliberate helper edit on a test branch makes the guard fail; a clean tree passes.

### User Story 3 — Simulation and the CLI behave as documented (P2)
`simulate --use-current-config` reproduces one recorded live session's transitions. `start` no longer changes the saved mode.

### User Story 4 — Coverage grows (P2)
One more qualified row, or a recorded decision that none is planned for 0.3.

### User Story 5 — The repo tells the truth (P3)
The spec link check finds no reference to ignored paths; every `[~]` has a reason.

### User Story 6 — Owner tests are recorded (P2)
T026, T306, grace, VoiceOver and the notch/second-display check each end with a recorded pass or a specific failure.

## Success Criteria

- **SC-001** No English on the five main screens in Vietnamese.
- **SC-002** The guard behaves as specified on both branches.
- **SC-003** One simulated session matches a live session.
- **SC-004** Zero links to ignored paths in tracked specs.

## Open questions

- **Q-E — Audio holds.** Build or drop after the research? The owner decides.

## Out of scope

- Fan control (excluded by the project constitution), webhooks, weekly reports, Smart Rules.
