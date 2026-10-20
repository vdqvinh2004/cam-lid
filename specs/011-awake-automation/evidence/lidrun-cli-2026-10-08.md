# Installed LidRun CLI evidence — 2026-10-08

Read-only verification by the main agent. CLI at `~/.local/bin/lidrun`, installed help reports **1.2.25**.

Commands: `rtk lidrun --help`, `rtk lidrun status --json`, `rtk lidrun patterns`.

Help exposes: status/JSON, start, stop, sleep/force, fan modes, autowatch, watch, unwatch, patterns, timer seconds, notify title/body, and command wrapper. App-running requirement applies to daemon commands; wrapper is described as self-contained. Help advertises notify maximum 5 per 10 minutes and rejects short/generic watch patterns.

Selected status evidence (transient observation, not saved configuration or hardware test):

```json
{
  "ok": true,
  "mode": "Awake Off",
  "assertionActive": false,
  "clamshellActive": false,
  "fanLicensed": true,
  "fanControlSupported": false,
  "thermal": "Normal",
  "tasks": [],
  "patterns": ["codex", "opencode", "claude"]
}
```

`patterns` agrees with the three entries above. A requested cooling mode in status is not a measured fan speed; no fan mutation performed. No start/stop/timer/sleep/fan/watch/unwatch/autowatch/notify command executed. No actual wrapper command executed. No native LidRun layout or closed-lid test performed this turn. Published behavior is separately linked in [comparison](../lidrun-comparison.md).

## Official-page retrieval check

Root web reader could not render these three pages. Direct read-only HTTPS retrieval returned HTTP200 and these titles on 2026-10-08; vendor contents, not feature runtime tests:

- Smart Rules: If-This-Then-That Automation for Mac Power — condition/action and time-window descriptions.
- Turn On Phone Notifications for LidRun — ntfy and Pro webhook destinations.
- Your Weekly Mac Workstation Report and What It Means — explicitly on-demand, not scheduled.

Full source URLs are in the comparison. No article body is copied into evidence.
