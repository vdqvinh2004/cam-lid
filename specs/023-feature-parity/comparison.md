# Feature comparison: CamLid, LidRun and LidWalk

**Date:** 2026-11-09 · **Baseline:** branch `v0.2` (commits `8ce434a`, `a667952`) on top of v0.1.0 ·
**Used by:** [spec 023](spec.md)

## Evidence and limits

- **CamLid:** the README, specs 001–022 and the code under `Packages/CamLidCore`. Items marked "present in code" were not
  run on hardware for this review.
- **LidRun:** the installed app (version 1.2.31) and the static reverse-engineering notes, kept outside this repository.
  The notes cover version 1.2.30 (build 255). Nothing in them was run. The CLI review in
  [spec 011](../011-awake-automation/lidrun-comparison.md) (2026-10-08, CLI 1.2.25) also covers the vendor feature list.
- **LidWalk:** its README and implementation report (version 1.0), kept outside this repository. LidWalk describes itself
  as an independent implementation of behaviour recovered from LidRun, and it shares no code with it.
- **Vendor claim:** a feature LidRun advertises that we have not confirmed.

**Clean-room rule.** This comparison records behaviour only. No code, assets, bundle identifiers, keys or credentials from
LidRun or LidWalk are reused. LidRun's bundle contains a credential-shaped configuration value; it is not recorded here.

## Filter

A feature is **needed** only when all four hold:

1. It serves the core job: keep the Mac awake while work runs, including with the lid closed, and report the truth about it.
2. A macOS user would call its absence a defect, or it is needed to support users.
3. It keeps CamLid's rules: observer-only agents ([ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md)); no
   prompts, transcripts or command output stored; no network use beyond the explicit update check; no fan control; safe
   defaults; native UI.
4. It can be verified. A feature that waits on a signal we have not found is parked.

Decision key: **Covered** (already in CamLid) · **Needed** (add) · **Owner** (needs a decision) · **Planned** (already in
another spec) · **Deferred** · **Excluded**.

## Keep awake

| Feature | LidRun | LidWalk | CamLid now | Decision |
| --- | --- | --- | --- | --- |
| Timed sessions with presets and an unlimited option | Vendor claim: 30 min–8 h, indefinite | Finite sessions with countdown | Timed presets and Infinite | Covered |
| Keep awake with the lid open, no helper, no root | Not established | Yes | Yes ([spec 018](../018-lid-open-and-run/spec.md)) | Covered |
| Closed-lid keep-awake through a privileged helper | Yes; the helper also exposes wake scheduling and fan control | Yes; Close Lid only | Yes: Standard on tested Macs, Strict experimental | Covered |
| Display stays awake, optional | Vendor toggle; effect not established | Yes (optional display assertion) | **Gap.** `allowDisplaySleep` is stored and settable from the CLI, but no app control shows it and no assertion uses it | **Needed** (spec 023, US1) |
| Audio playback keeps the Mac awake | Not in the reviewed material | Yes (watched apps and audio) | Research only ([019](../019-coverage-and-localization/tasks.md) T070): `coreaudiod` holds its assertion with or without playback; only Chromium browsers name "Playing audio" | **Owner** (019 T071) |
| Watched programs keep an Auto session awake | Vendor claim: custom process and app watches | Yes (watched apps) | Yes: "Watched programs" in Settings and `camlid watch` | Covered |
| Keep awake while one command runs | CLI wrapper | Yes; output written to a log file | Yes: `camlid run -- <command>`; no output stored | Covered. Do not copy output logging (privacy) |
| Global shortcut | Not established | ⌃⌥⌘K | ⌃⌥⌘K | Covered |

## Safety

| Feature | LidRun | LidWalk | CamLid now | Decision |
| --- | --- | --- | --- | --- |
| Low-battery stop | Vendor claim: guardrails | Yes | Yes: battery floor and charger rule | Covered |
| Thermal-pressure stop | Vendor claim: guardrails | Yes | Yes | Covered |
| Sustained CPU stop | Not confirmed | No | Yes (optional) | Covered |
| Restore only what the app changed, with read-back | Vendor claim: watchdog | Yes (ownership, read-back) | Yes: ownership, read-back, recovery journal | Covered |
| Recovery after a crash or restart | Vendor claim: watchdog | Not verified (LidWalk's own limits) | Yes: journal, orphan recovery, `camlid recover` | Covered |

## Visibility and support

| Feature | LidRun | LidWalk | CamLid now | Decision |
| --- | --- | --- | --- | --- |
| Menu-bar countdown | Not established | Yes | Present in code (`MenuBarCountdown`) | Covered; confirm on a real Mac at release |
| Activity history | Vendor claim | Yes | Yes: 14 days, no prompts or transcripts | Covered |
| Why the Mac is awake | Assertion inspection | Diagnostics tab | `camlid diagnose`; Sleep diagnostics window | Covered |
| Copy diagnostics | Not established | Yes | No copy action | **Needed** (spec 023, US2) |
| Outcome notifications | Vendor claim: alerts | Yes | Yes: categories and permission | Covered |

## System

| Feature | LidRun | LidWalk | CamLid now | Decision |
| --- | --- | --- | --- | --- |
| Launch at login | Vendor claim | Yes (LaunchAgent) | Yes | Covered |
| English and Vietnamese UI | Not established | Yes | English only; Vietnamese planned | **Planned** (spec 019, v0.3) |
| Update check | Automatic download and install (Sparkle 2.9.3) | Sparkle, off until a feed is set | Manual check and optional daily check; never installs ([spec 021](../021-automatic-updates/spec.md)) | Covered. Install deferred ([ADR 0004](../../docs/adr/0004-distribution-through-github-releases.md)) |

## Agents and automation

| Feature | LidRun | LidWalk | CamLid now | Decision |
| --- | --- | --- | --- | --- |
| Agent-aware keep-awake, observer-only | Vendor claim: process and agent watches (Pro) | No | Yes: Claude Code, Codex, OpenCode, Orca; no hooks | Covered. CamLid's own differentiator |
| Skill and JSON status for AI agents | CLI with JSON status | CLI | Skill ([spec 022](../022-agent-skill/spec.md)), `status --json`, `diagnose --json` | Covered |
| Sleep from the terminal | Guarded `sleep` with `--force` | No | `camlid sleep` in the CLI; behaviour not re-verified here | Covered |
| App Intents and Shortcuts actions | Yes (App Intents found in static analysis) | No | No | Deferred: not needed for the agent-first product |

## Excluded or deferred

| Feature | LidRun | LidWalk | CamLid now | Decision |
| --- | --- | --- | --- | --- |
| Fan control | Yes (helper method) | No | No | Excluded (constitution) |
| Wake scheduling | Yes (helper method) | No | No | Excluded: not keep-awake, and it widens the privileged surface |
| Phone and chat push, webhooks | Vendor claim: ntfy, Pushover, Telegram, Discord, Slack, custom | No | No | Excluded: privacy and credentials |
| Command output capture | No | Yes (`watch.log`) | No | Excluded: CamLid never stores prompts or output |
| Charge limiting | Not established | No | No | Excluded: not keep-awake |
| Install an update in place | Yes (Sparkle installer) | No | No | Excluded until a Developer ID decision ([ADR 0004](../../docs/adr/0004-distribution-through-github-releases.md)) |
| Weekly report | Vendor claim | No | No | Deferred: no concrete user question yet |
| Time windows and smart rules | Vendor claim | No | Watched programs only | Deferred |

## Summary

- **Covered:** most of LidWalk's list and the core of LidRun's.
- **Needed:** two items. A display option, which also makes a stored setting real, and copyable diagnostics.
- **Owner decision:** audio, for Chromium browsers only or after another signal is found.
- **Planned elsewhere:** the Vietnamese interface, in spec 019.
- **Excluded or deferred:** the rest.

CamLid is not short on features relative to LidWalk. It is short on the two items above. Adding more would need a user
need, not a comparison.

## Notes

- LidRun versions differ across sources: installed 1.2.31, static notes 1.2.30, CLI review 1.2.25. Re-check the vendor
  claims against the installed version before any decision that depends on them.
- The reverse-engineering notes are kept outside this repository and are not linked here.
