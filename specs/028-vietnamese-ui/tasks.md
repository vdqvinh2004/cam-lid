# Tasks: Vietnamese interface (v0.3)

**Feature context:** `028-vietnamese-ui` · **Status:** 18/19 checked. Sources: [spec.md](spec.md).

## Phase 1 — Inventory and spike

- [x] T001 Inventory every user-visible string in `CamLidApp`. About 190 literal labels and about 150 strings built in code (reasons, notifications, diagnostics, messages); 725 catalogue keys after the work. The counts in spec.md are the starting point.
- [x] T002 Spike: SwiftPM compiles `Localizable.xcstrings` into the package's `vi.lproj`. The app reads it with `Bundle(path:)` and CamLid's own language choice. xcodebuild puts `vi.lproj/Localizable.strings` in the app bundle.

## Phase 2 — Catalog and switch (FR-001, FR-002)

- [x] T010 `Localizable.xcstrings` with English keys and Vietnamese values (`Packages/CamLidCore/Sources/CamLidApp/Resources/`).
- [x] T011 Language setting (System / English / Tiếng Việt) in Settings › General, saved as `CamLidLanguage`.
- [x] T012 Applied at once: SwiftUI bodies redraw through an observed language state; the menu bar, the app menu and the window titles are set again on change; notifications read the language when they are made.

## Phase 3 — Translate (FR-001, FR-003)

- [x] T020 Dashboard.
- [x] T021 Settings, all panes.
- [x] T022 Activity and diagnostics. The copied diagnostics report stays in English, because it is for bug reports.
- [x] T023 Onboarding.
- [x] T024 Updates window and update messages.
- [x] T025 Menu bar items and notifications.
- [x] T026 Reason and status lines.

## Phase 4 — Checks (SC-001 to SC-004)

- [x] T030 Test: every key has a Vietnamese value (`LocalizationTests`).
- [x] T031 Test: the language choice changes the shown text (`LocalizationTests`).
- [x] T032 Screen check: the five main screens rendered in Vietnamese, light and dark (`VietnameseRenderTests`, opt-in). Clipping fixed on the Updates button. Read on the rendered images; the live app on the Mac is still to check.
- [ ] T033 VoiceOver spot check on the main controls. Not done: needs the Mac with VoiceOver on.

## Phase 5 — Release

- [x] T040 README and release notes mention Vietnamese (`scripts/release.sh` template and README "What it does").
- [x] T041 Mode names in Vietnamese: Auto → Tự động, Timed → Hẹn giờ, and "bộ hẹn giờ" → "hẹn giờ" (owner, 2026-11-20). English and the machine codes are unchanged. Checked by `LocalizationTests` and the render check of the mode buttons.
- [x] T042 Text already on screen follows a language switch (owner report 2026-11-20: the battery notice stayed Vietnamese). Notices, status lines and outcomes are stored as English and shown with `Localization.display`; `LocalizationTests`.
