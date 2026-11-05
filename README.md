# CamLid

A native macOS menu bar app that keeps a Mac awake with the lid closed while AI coding agents work, and lets it
sleep when they are done.

**Status: signed with the project's own release certificate, not notarized by Apple, tested on one Mac.** Closed-lid operation has passed attended trials on
Mac17,3 with macOS 26A434 only ([trial record](specs/014-persistent-helper/g2-trial.md)). On any other model or
macOS build it stays off unless you explicitly accept "untested configuration" in Settings › Closed Lid. Releases are
signed with a self-signed certificate, not an Apple Developer ID, and not notarized ([why](docs/adr/0004-distribution-through-github-releases.md)).

## Download

Get `CamLid-<version>-macos-arm64.zip` from the [Releases](https://github.com/vdqvinh2004/cam-lid/releases) page
(Apple silicon, macOS 14 or later). Each release lists the SHA-256 of the zip and the code hashes of the app and its
root helper; check them before you run it.

1. Unzip it and move **CamLid.app** to `/Applications`.
2. macOS refuses the first launch because the app is not notarized. Open it once, then *System Settings › Privacy &
   Security › Open Anyway*, or run `xattr -dr com.apple.quarantine /Applications/CamLid.app`.
3. Continue with [Install and use](#install-and-use).

Updating: *Check for Updates…* asks GitHub for the newest release when you click it and opens the Releases page; it
never downloads or installs anything. A release is signed with CamLid's own certificate, so the installed helper keeps
working with the new app; CamLid asks you to reinstall the helper only when the helper itself changed, and the release
notes say so. An app you sign ad hoc yourself needs **Reinstall helper…** after every rebuild.

## What it does

- **Auto** keeps the Mac awake while the agents you selected are working, then waits for "Sleep when done" and lets
  the Mac sleep. **Timed** keeps it awake for a chosen time (or until you stop it, on the charger).
- **Agents are observed from outside only** ([ADR 0002](docs/adr/0002-observer-only-agent-activity.md)). CamLid
  installs no hooks, plugins or wrappers and never edits an agent's configuration.
  - Orca: read-only `orca` CLI status of its panes.
  - Claude Code, Codex, OpenCode run in a terminal: working or idle is estimated from the CPU activity of the agent
    and its child processes, shown as "(estimated)"
    ([spec 015](specs/015-agent-activity-observer/spec.md)). Launching an agent without a prompt does not count.
  - Watched programs: optional rules that keep the Mac awake while a given program runs.
- **Safety stops** on low battery, high thermal pressure, unplugged charger (unless "Allow on battery" is on),
  sustained CPU load (optional) and session time limits. Missing readings never count as healthy.
- **When a session ends with the lid closed, the Mac sleeps** (unless an external display is connected).

## How closed lid works

Keeping a closed Mac awake needs root, so CamLid installs a small helper (a LaunchDaemon) once, with your
administrator password ([ADR 0001](docs/adr/0001-persistent-helper-and-strict-experimental-mode.md),
[spec 014](specs/014-persistent-helper/spec.md)).

- **Standard (default)** sets the system `SleepDisabled` setting while a session runs and restores it afterwards.
- The helper only acts for a signed CamLid app whose signing certificate (or, for ad-hoc builds, exact code hash) it
  pinned at install ([ADR 0005](docs/adr/0005-stable-signing-certificate-for-the-helper-pin.md)), holds a 30-second lease
  that the app renews every 10 seconds, and restores the setting when the lease lapses (app quit, crash or hang).
- An independent recovery job runs every 15 seconds and restores the setting if the helper itself is gone.
- A journal records what CamLid changed, so the setting is restored after a crash or restart.
- **Strict (experimental, in progress)** will block only lid-close sleep through a kernel setting that a restart
  clears ([ADR 0003](docs/adr/0003-strict-mode-lid-only-on-the-persistent-helper.md),
  [spec 016](specs/016-strict-lid-only/spec.md)).

Known conflict: LidRun's helper resets the sleep setting and interrupts closed lid; CamLid warns when it is present.

## Requirements

- macOS 14 or later on Apple silicon; tested on macOS 26.
- Xcode 27 (Swift 6.4, macOS 27 SDK) to build it yourself.

## Build

```sh
xcodebuild -project CamLid.xcodeproj -scheme CamLid -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$HOME/CamLidBuild" \
  CODE_SIGNING_ALLOWED=NO build
ditto "$HOME/CamLidBuild/Build/Products/Release/CamLid.app" /Applications/CamLid.app
```

The build signs the app and its embedded helper ad hoc. To sign with a stable certificate instead (so rebuilds and
updates keep the installed helper), run `scripts/make-signing-identity.sh` once, then
`CAMLID_SIGN_IDENTITY="CamLid Release Signing" scripts/release.sh`. Without that variable the script refuses to build;
`scripts/release.sh --adhoc` makes a local test build named `-ADHOC`, not for publication. `project.yml` is the XcodeGen source
(`xcodegen generate` after changing targets).

Tests (each package):

```sh
swift test --package-path Packages/CamLidCore
swift test --package-path Packages/CamLidPowerHelper
swift test --package-path Packages/CamLidPowerWire
```

## Install and use

1. Open `/Applications/CamLid.app`; its icon appears in the menu bar.
2. Settings › Closed Lid: click **Install helper…**, enter your password, then turn on **Keep awake with the lid
   closed**. Details shows this Mac and whether it was tested.
3. Settings › Agents: select the agents that may keep the Mac awake.
4. In the menu bar Dashboard, click **Auto** or **Timed**. Click the active mode again to stop.

Every new build or release changes the app's code hash: click **Reinstall helper…** afterwards. To remove the helper (restoring
the sleep setting first), click **Remove helper…** or run `sudo camlid helper uninstall`.

## Command line

The `camlid` tool talks to the running app over a same-user local socket. It ships inside the app; put it on your
PATH with `sudo ln -s /Applications/CamLid.app/Contents/Helpers/camlid /usr/local/bin/camlid` (the quarantine flag must
be cleared first, see Download).

```sh
camlid status --json            # state, agents, health, helper lease
camlid start --mode auto        # same path as the Dashboard; refuses with a reason code
camlid run -- make build        # keeps the Mac awake while this command runs; needs CamLid running
camlid stop
camlid config get --json
camlid helper status            # install | uninstall | trust need administrator rights
camlid diagnose --json          # "Why is my Mac awake?"
camlid logs export --redacted --output events.json
```

Full contract: [CLI](specs/003-native-foundation/contracts/cli.md).

## License

MIT, see [LICENSE](LICENSE). The agent marks bundled for identification remain the trademarks of their owners
([TRADEMARKS.md](Packages/CamLidCore/Sources/CamLidApp/Resources/TRADEMARKS.md)); the license does not cover them.
CamLid has no third-party code dependencies.

## Privacy

History stays on the Mac (14 days or 20 MiB) and records mode changes, safety stops and agent states, never prompts,
code or transcripts. Exports hide identifiers. The only network use is the update check you start yourself (one request to GitHub's public releases API, with no
account, cookies or system profile).

## Project documents

- [Specs by milestone](specs/README.md) with tasks and status.
- Decisions: [ADR 0001](docs/adr/0001-persistent-helper-and-strict-experimental-mode.md),
  [ADR 0002](docs/adr/0002-observer-only-agent-activity.md),
  [ADR 0003](docs/adr/0003-strict-mode-lid-only-on-the-persistent-helper.md),
  [ADR 0004](docs/adr/0004-distribution-through-github-releases.md).
- [Security policy](SECURITY.md) and [contributing](CONTRIBUTING.md); `scripts/release.sh` builds a release.
- [Constitution](.specify/memory/constitution.md).

## Limits

- Qualified on one Mac model and macOS build; other combinations are untested.
- Agent activity for terminal agents is an estimate: a model thinking silently for a long time can look idle.
- Unsigned: macOS asks you to approve the first launch, and the app cannot update itself.
- Apple silicon only.
- No fan or charging control.
