# Tasks: display option, copyable diagnostics, Chromium audio hold (v0.2)

**Feature context:** `023-feature-parity` · **Status:** 2/18 checked. Sources: [spec.md](spec.md), [comparison.md](comparison.md).

## Phase 0 — Decisions
- [x] T001 D1–D4 accepted as recommended, 2026-11-09 ([spec.md](spec.md), "Decisions").
- [x] T002 Spec 019 T071 recorded as go, browsers only. Tasks T080–T083 are tracked here as Phase 3.

## Phase 1 — Display option (US1; FR-001 to FR-004)
- [ ] T010 [FR-001] Settings › General › New sessions: toggle "Let the display sleep during sessions", bound to `allowDisplaySleep` (default `true`) through the existing `setAllowDisplaySleep` path.
- [ ] T011 [FR-003] The display choice is read when a session starts. A later change waits for the next session.
- [ ] T012 [FR-002] The lid-open hold also holds `PreventUserIdleDisplaySleep` when the display may not sleep. Same create, read-back and release path as the system hold.
- [ ] T013 [FR-004] Sleep diagnostics shows the display hold as CamLid's own assertion.
- [ ] T014 [SC-001, SC-002] Tests: by default no display assertion is created; with the option off, exactly one is held during a session and released when it ends.

## Phase 2 — Copyable diagnostics (US2; FR-005, FR-006)
- [ ] T020 [FR-006] Plain-text report from the existing diagnostics snapshot, with an allow-list of fields.
- [ ] T021 [FR-005] "Copy diagnostics" in the Sleep diagnostics window. Copies on press only.
- [ ] T022 [SC-003] Test: the report contains the allowed fields and none of the excluded patterns.

## Phase 3 — Chromium audio hold (US3; FR-007, SC-004; from spec 019 T080–T083)
- [ ] T030 [T080] Signal reader behind a protocol: a named "Playing audio" power assertion held by a Chromium-based browser. A fake for tests.
- [ ] T031 [T081] Audio rule next to watched programs, for Auto sessions only. The UI names it as a browser rule.
- [ ] T032 [T082] The hold ends after a 60-second quiet period. It never holds without the named signal. Activity records start and end only.
- [ ] T033 [T082] Tests: holds while the named signal exists; ends after the quiet period; no hold without a signal; other assertions ignored.
- [ ] T034 [T083] Live check with a Chromium browser on this Mac. Not in this implementation pass.

## Phase 4 — Verification and records
- [ ] T040 Focused tests for each phase, then the full CamLidCore run.
- [ ] T041 Release build succeeds with the changes.
- [ ] T042 Status and task records updated with the evidence.
