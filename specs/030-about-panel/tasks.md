# Tasks: About panel (v0.3)

**Feature context:** `030-about-panel` · **Status:** 13/15 checked. Sources: [spec.md](spec.md).

## Phase 1 — Read

- [x] T001 Confirm the name, version, copyright and icon keys in the built app's `Info.plist`.
- [x] T002 Find every menu that needs the item: status menu, menu bar CamLid menu, utility menu.

## Phase 2 — Implement (FR-001 to FR-005)

- [x] T010 `Packages/CamLidCore/Sources/CamLidApp/AboutPanel.swift`: `show()` and `credits`.
- [x] T011 `MenuBarController.swift`: menu item with identifier `camlid.menu.about`, its handler, and removal of the stale comment about About.
- [x] T012 `UtilityUICoordinator.swift`: menu item and handler in the utility menu.

## Phase 3 — Checks (SC-001 to SC-004)

- [x] T020 `AboutPanelTests.swift`: credits and link, status-menu item, utility menu item.
- [x] T021 Menu tests still pass: `UISimplicityTests`, `UtilityEditingMenuTests`, `AccessibilityStateTests`, `CamLidStatusIconTests`.
- [x] T022 Full `CamLidCore` `swift test`: all three runs pass (293, 68 and 430 tests).
- [x] T023 CamLid scheme builds in Debug (arm64).
- [x] T024 Credits render in light and dark, off screen. Scratch check outside the project: text colour, centring and link colour.
- [ ] T025 Live check: open "About CamLid" from the status menu and from the menu bar, in light and dark, and click the link. Not done: no CamLid build was launched on the owner's Mac.
- [ ] T026 VoiceOver: the menu item and the About window are announced. Not done.

## Phase 4 — Docs and release

- [x] T030 `specs/README.md` lists spec 030.
- [x] T031 Spec 028 no longer lists the About panel as out of scope; its catalog covers the credits and the menu item (D4).
- [x] T032 Release notes for 0.3.0 mention the About item (the `scripts/release.sh` template, 2026-11-19). The version bump and the release run are separate steps.
