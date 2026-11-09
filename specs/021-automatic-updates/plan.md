# Plan: automatic update setting (v0.2)

**Spec:** [spec.md](spec.md) · **Tasks:** [tasks.md](tasks.md)

## Approach

Extend the existing information-only update check. Nothing new reaches the network: the scheduled check calls the same
`GitHubReleaseDriver` as *Check for Updates…*, and it never downloads or installs.

- **Owner:** `UpdateController` (`Packages/CamLidCore/Sources/CamLidApp/UpdateController.swift`). The persistent app
  owns the setting and the timer. The Settings window only shows the toggle and sends the choice (the view process is
  view-only, as `UtilityUIProcess.swift` describes).
- **Storage:** two keys in the app's preferences. `CamLidAutomaticUpdateChecks` (Bool; missing means Off, so an upgrade
  never turns it on) and `CamLidLastUpdateRequest` (the time the last request started).
- **Timer:** one tick per hour, tolerance 5 minutes, scheduled only while the setting is On. Off invalidates it at once.
- **Rule:** a tick makes a request only if 24 hours have passed since the last request of any kind, no session is
  active and no recovery is required. Otherwise the next tick tries again. Manual checks count as requests, so a daily
  check never follows a manual one within the same day.
- **Settings:** a toggle in Settings › General with the request described in the footer. The Updates window's default
  text now mentions the daily check.

## Decisions taken without the owner

- A scheduled check does not wait for agent activity or unsaved Settings. Agents can stay "waiting" for long periods,
  which would otherwise delay the check for days. Spec FR-003 names only sessions and holds.
- Enabling the setting does not request at once. The first request comes at the next hourly tick, when due.
- The version number is not decided here; the docs call the release "v0.2" (see the README index in `specs/README.md`).

## Not in this change

- Install mode (decision 3 of the spec).
- The privacy wording in README and SECURITY.md is drafted, but the owner reviews it before release (FR-006).
