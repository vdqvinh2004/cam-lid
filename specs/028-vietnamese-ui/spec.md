# Feature Specification: Vietnamese interface (v0.3)

**Status:** Released in 0.3.0 beta on 2026-11-23. Replaces spec 019 FR-001, User Story 1 and tasks T011–T014. D1–D3 are applied as recommended; the owner confirms them. A native-speaker review of the Vietnamese text and the VoiceOver check are open (tasks T033).

## Goal

Show CamLid in Vietnamese as well as English, as LidWalk does, so a Vietnamese-speaking user can read every screen, menu item and notification without switching the system to English.

## Before this change (read in the code, 2026-11-19)

- The interface is English only. The repository has no `.lproj` folder and no String Catalog.
- User-visible text is spread through the code. In `Packages/CamLidCore/Sources/CamLidApp` there are about 69 `Text("…")`, 39 `Button`, 23 `Label`, 33 `.help` tooltips, 9 `Toggle`, 7 `Picker` and 4 alerts. Strings are also built in code: reason and status lines (`AppCoordinator`, `ActivityPresentation`, `UpdatesView`), menu items (`MenuBarController`), notifications, onboarding pages and the diagnostics report.
- Spec 019 estimated about 62 `Text` literals. This count is the new baseline; T001 confirms it.

## Decisions (owner to confirm)

- **D1. Language choice.** By default the app follows the macOS language: Vietnamese gives Vietnamese, anything else gives English. Settings › General › Language offers System, English and Tiếng Việt, as LidWalk does. *Recommended.*
- **D2. Machine output stays English.** CLI messages, JSON keys, command names, flags, log lines and file names are not translated. Scripts and the agent skill depend on them. *Recommended.*
- **D3. Glossary.** The terms below are the proposal. The owner confirms or changes them before translation starts. *Owner, 2026-11-20: Auto is shown as Tự động and Timed stays Hẹn giờ. English keeps Auto and Timed, and the machine codes auto and timed do not change.*

| English | Vietnamese |
| --- | --- |
| Keep awake | Giữ thức |
| Keep awake with the lid closed | Giữ thức khi đóng nắp |
| Close Lid | Đóng nắp |
| Session | Phiên |
| Auto / Timed / Infinite | Tự động / Hẹn giờ / Không giới hạn |
| Watched programs | Chương trình theo dõi |
| Activity | Hoạt động |
| Settings | Cài đặt |
| Dashboard | Bảng điều khiển |
| Diagnostics | Chẩn đoán |
| Update / Install / Check for Updates | Cập nhật / Cài đặt / Kiểm tra cập nhật |
| Notification | Thông báo |
| Recovery | Phục hồi |
| Quit | Thoát |
| Keep in English: CamLid, helper, Strict, agent, Orca, Claude Code, Codex, OpenCode | — |

## Requirements

- **FR-001** Every user-visible string is in a String Catalog with an English value and a Vietnamese value. No sentence is built from English fragments.
- **FR-002** The language follows D1. A change in Settings applies without reinstalling. If an open window needs a restart to switch, the Settings text says so Notices, status lines and outcomes are stored as English and shown in the current language, so a switch changes the text already on screen too (owner report, 2026-11-20).
- **FR-003** Vietnamese text does not clip or truncate on the five main screens (Dashboard, Settings, Activity, Onboarding, Updates) at their default sizes. Labels wrap instead.
- **FR-004** VoiceOver labels, hints and tooltips come from the same catalog.
- **FR-005** Dates and numbers follow the selected language.
- **FR-006** Machine output stays English (D2).

## Success criteria

- **SC-001** On the five main screens in Vietnamese, no English text remains. The owner checks the screenshots.
- **SC-002** A test fails if any key has no Vietnamese value.
- **SC-003** The five screens fit at default sizes in light and dark appearance.
- **SC-004** A VoiceOver spot check reads Vietnamese labels on the main controls.

## Technical constraint to settle first (T002)

`CamLidApp` is a SwiftPM target. SwiftUI looks up `Text("…")` keys in the main bundle by default, while `Package.swift` declares package resources (`resources: [.process("Resources")]`). The catalog must be found from wherever it lives: the app bundle, or `Bundle.module` in the package. T002 decides the location with a build of the app and a check that a Vietnamese string appears.

## Out of scope

Languages other than English and Vietnamese. Translating CLI output (D2). Translating agent or provider names. The About window's own text, which macOS localises. The CamLid credits and the "About CamLid" menu item are in scope (spec 030, D4).

## Open after this spec

D1–D3 (owner). A native-speaker review of the Vietnamese strings, which the owner can do.
