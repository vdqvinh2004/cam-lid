# Contributing

Thanks for looking. CamLid changes how a Mac sleeps, so changes are held to a high bar for safety, not for size.

## Build and test
```sh
swift test --package-path Packages/CamLidCore
swift test --package-path Packages/CamLidPowerHelper
swift test --package-path Packages/CamLidPowerWire
xcodebuild -project CamLid.xcodeproj -scheme CamLid -configuration Release -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```
Xcode 27 (Swift 6.4) is the canonical toolchain. `project.yml` is the XcodeGen source (`xcodegen generate` after
changing targets). Every build changes the app's code hash, so click *Reinstall helper…* after installing one.

## Rules that are not negotiable
- **Observer only.** CamLid never installs hooks, plugins or wrappers into an agent and never edits an agent's
  configuration ([ADR 0002](docs/adr/0002-observer-only-agent-activity.md)).
- **Unknown is not healthy.** A missing reading stops or refuses; it never counts as safe.
- **A change to the helper needs tests, and a trial if it changes what the Mac does.** The recipes are in
  [specs/014-persistent-helper/g2-trial.md](specs/014-persistent-helper/g2-trial.md) and
  [specs/016-strict-lid-only/tasks.md](specs/016-strict-lid-only/tasks.md).
- Keep the app's UI native (SwiftUI/AppKit, system controls, accessibility labels, light and dark).

## Qualifying another Mac
Closed lid is on by default only for Macs that passed the attended trials (see `QualifiedSupportRows`). If you have
another model or macOS build, run the trial recipe above on it (lid closed, app kill, helper kill, restart) and open an
issue with the model (`sysctl hw.model`), the build (`sw_vers`), and the logs it asks for. A row is added only after the
owner reviews the results.

## Pull requests
Small and focused, with tests. Describe what the Mac does differently. Do not commit signed builds or QA archives.

## Releases
`scripts/release.sh` builds the release zip and its notes; the owner uploads it (see
[ADR 0004](docs/adr/0004-distribution-through-github-releases.md)).
