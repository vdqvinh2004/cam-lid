# CamLid

A native macOS menu bar app that keeps a Mac awake with the lid closed while AI coding agents work, and lets it
sleep when they are done.

**Status (2026-10-31): early, unsigned, tested on one Mac.** Closed-lid operation has passed attended trials on
Mac17,3 with macOS 26A434 only ([trial record](specs/014-persistent-helper/g2-trial.md)). On any other model or
macOS build it stays off unless you explicitly accept "untested configuration" in Settings › Closed Lid. Builds are
ad-hoc signed and not notarized.

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
- The helper only acts for a signed CamLid app or CLI whose code hash it pinned at install, holds a 30-second lease
  that the app renews every 10 seconds, and restores the setting when the lease lapses (app quit, crash or hang).
- An independent recovery job runs every 15 seconds and restores the setting if the helper itself is gone.
- A journal records what CamLid changed, so the setting is restored after a crash or restart.
- **Strict (experimental, in progress)** will block only lid-close sleep through a kernel setting that a restart
  clears ([ADR 0003](docs/adr/0003-strict-mode-lid-only-on-the-persistent-helper.md),
  [spec 016](specs/016-strict-lid-only/spec.md)).

Known conflict: LidRun's helper resets the sleep setting and interrupts closed lid; CamLid warns when it is present.

## Requirements

- macOS 14 or later; tested on macOS 26 (Apple silicon).
- Xcode 27 (Swift 6.4, macOS 27 SDK) to build.

## Build

```sh
xcodebuild -project CamLid.xcodeproj -scheme CamLid -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$HOME/CamLidBuild" \
  CODE_SIGNING_ALLOWED=NO build
ditto "$HOME/CamLidBuild/Build/Products/Release/CamLid.app" /Applications/CamLid.app
```

The build signs the app and its embedded helper ad hoc. `project.yml` is the XcodeGen source
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

Every rebuild changes the app's code hash: click **Reinstall helper…** afterwards. To remove the helper (restoring
the sleep setting first), click **Remove helper…** or run `sudo camlid helper uninstall`.

## Command line

The `camlid` tool talks to the running app over a same-user local socket.

```sh
camlid status --json            # state, agents, health, helper lease
camlid start --mode auto        # same path as the Dashboard; refuses with a reason code
camlid stop
camlid config get --json
camlid helper status            # install | uninstall | trust need administrator rights
camlid diagnose --json          # "Why is my Mac awake?"
camlid logs export --redacted --output events.json
```

Full contract: [CLI](specs/003-native-foundation/contracts/cli.md).

## Privacy

History stays on the Mac (14 days or 20 MiB) and records mode changes, safety stops and agent states, never prompts,
code or transcripts. Exports hide identifiers. No network service is used except an optional manual update check.

## Project documents

- [Specs by milestone](specs/README.md) with tasks and status.
- Decisions: [ADR 0001](docs/adr/0001-persistent-helper-and-strict-experimental-mode.md),
  [ADR 0002](docs/adr/0002-observer-only-agent-activity.md),
  [ADR 0003](docs/adr/0003-strict-mode-lid-only-on-the-persistent-helper.md).
- [Constitution](.specify/memory/constitution.md).

## Limits

- Qualified on one Mac model and macOS build; other combinations are untested.
- Agent activity for terminal agents is an estimate: a model thinking silently for a long time can look idle.
- Unsigned: Gatekeeper blocks downloaded builds; build from source.
- No fan or charging control.
