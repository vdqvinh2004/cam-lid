# Feature Specification: About panel (v0.3)

**Status:** Implemented on v0.3, not released. Added on the owner's request ("Thêm của about panel cho v 0.3 đi", 2026-11-19). The live check is open (tasks T025–T026).

## Goal

From CamLid, a person can open the standard macOS About window to see the version, the copyright and the license, and to find the source and the releases.

## Before this change (read in the code, 2026-11-19)

- Neither menu had an About item: the status menu and the menu bar's CamLid menu (`MenuBarController.buildMenu()`), and the menu bar of the utility windows (`UtilityUICoordinator.installMenu()`). A comment in `MenuBarController` said About would come with the real app shell.
- `CamLidApp/Info.plist` already sets `CFBundleName`, `CFBundleShortVersionString` (from `MARKETING_VERSION`), `CFBundleVersion`, `NSHumanReadableCopyright` ("Copyright © 2026 vdqvinh2004. MIT License.") and the `AppIcon` icon.
- The minimum system is macOS 14, so `NSApplication.activate()` needs no availability check.

## Decisions

- **D1. Native window.** `orderFrontStandardAboutPanel` shows the icon, name, version and copyright from the bundle. No custom window. *Implemented.*
- **D2. Where.** "About CamLid" follows "Check for Updates…" in the status menu and in the menu bar's CamLid menu. In the utility menu it sits before "Quit CamLid". *Implemented.*
- **D3. Content.** One sentence on what CamLid does, and a link to the repository (source, releases, issues). No update check, no network call, no analytics. *Implemented; the owner can change the wording.*
- **D4. Language.** English for now. Spec 028 translates the credits sentence and the menu item together with the rest of the catalog.

## Requirements

- **FR-001** "About CamLid" opens the standard About window from the status menu and from the menu bar. The app is brought to the front first, because a menu bar app is not active by itself.
- **FR-002** Icon, name, version and copyright come from the bundle. No version string is written in code.
- **FR-003** The credits show the sentence from D3 and a link to `https://github.com/vdqvinh2004/cam-lid`.
- **FR-004** Opening the About window reads no user data, sends nothing and does not check for updates.
- **FR-005** The status-menu item has the accessibility identifier `camlid.menu.about`.

## Success criteria

- **SC-001** `AboutPanelTests` pass: the credits and the link, the status-menu item and the utility menu item.
- **SC-002** All three `CamLidCore` test runs pass (293, 68 and 430 tests).
- **SC-003** The CamLid scheme builds in Debug for arm64, and the built `Info.plist` has the expected keys.
- **SC-004** Live check on the owner's Mac: the item opens the window from the status menu and from the menu bar, in light and dark, and the link opens the repository. *Open.*

## Notes

- The version shown is the one the build carries. `project.yml` still says 0.2.0 until the release step bumps it; the release script passes `MARKETING_VERSION`.
- The credits were checked off screen in light and dark by rendering the same text in a text view. The About window's own layout belongs to macOS and was not inspected live.

## Out of scope

A custom About window, a `Credits.rtf` file, an acknowledgements list, an update check inside About, a Help menu.
