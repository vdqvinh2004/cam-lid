# LidRun Pro comparison and local observations

**Observed**: 2026-10-05. Installed CLI version 1.2.25. Read-only commands: `rtk lidrun --help`, `rtk lidrun status --json`. No start/stop/timer/sleep/fan/watch/enrollment/license operations executed.

| Evidence | Result | Meaning / boundary |
| --- | --- | --- |
| CLI reachable | status ok=true | Running app/service responds; not backend qualification |
| Mode | Awake Off | At read time; not proof no persistent external owner exists |
| assertionActive / clamshellActive | false / false | No active LidRun hold reported, not physical lid sensor |
| License / fan hardware | fanLicensed=true / fanControlSupported=false | Entitlement differs from hardware support; no upgrade recommendation |
| Battery / charging | 90% / false | isCharging=false does not establish AC disconnected; AC and charging are different |
| Thermal | Normal | Qualitative; no Celsius field or RPM values in response |
| Watch list / tasks | codex, opencode, claude / [] | Configured providers differ from current observed tasks |
| Root-domain read | lid=false, causesSleep=true | Open lid instant; close/reopen freshness remains untested |
| CamLid Settings AX | section label, four checkboxes, Save Changes present | Matches user findings; native actual VoiceOver not tested |
| CamLid source | transient popover; hardcoded unknown lid; Options callback; whole-draft Save | Inspection evidence, not reproduction of every GUI issue |

## Native comparison limitation

CUA list_apps misreported LSUIElement PID=0; list_windows located actual LidRun PID50684 with hidden status/dummy surfaces. Exact-window1441 inspection returned AX-unresolved and empty tree: no normal LidRun dashboard/settings window exposed. No pixel/foreground escalation or user power settings changed. Therefore installed-native layout, autosave, outside dismissal and actual temperature display are **not verified**. Initial web image download request returned HTTP403; no screenshot invented. The comparison below uses published first-party examples and live CLI facts. Follow-up native navigation is T002; do not call it complete from a website.

## Design choices

| Area | Published LidRun / observed CLI | CamLid choice |
| --- | --- | --- |
| Status hierarchy | Compact top status, sensor strip, tasks, modes and release reasons | Follow compact hierarchy; one effective reason before details |
| Surface navigation | Published menu/window examples include status/reports/settings | Keep user's left dashboard/right options; no duplicate Options |
| Numerical temperature | Homepage illustrative60°C; local CLI only Normal | Named qualified temperature + independent pressure; explicit unavailable |
| Provider state | Patterns and tasks separate in live CLI | Detection On/Off badge plus truthful activity/readiness/count |
| Immediate controls | Published direct mode/timer/safety controls | Per-field direct apply; conflict/error/readback, Custom last |
| Protection | Vendor describes helper/global override/watchdog | M1 evidence before selection; independent restoration/external ownership |
| Safety | Battery/thermal/timer/charging guardrails | Preserve conservative limits; no bag/unsaved-work guarantees |
| Pro features | Licensed fans unavailable here | Explain hardware blockers; fan/charging control stays outside v1 |
| Logs | Vendor activity/why awake/why stopped emphasis | Transition reasons, source freshness and restoration; bounded/redacted |

[Official product examples](https://lidrun.com/), [closed-lid mechanism](https://lidrun.com/blog/keep-mac-awake-when-lid-closed), [helper guide](https://lidrun.com/guide/enable-helper), [safety](https://lidrun.com/safety). Vendor mechanism and recovery claims are not independent hardware proof. Do not copy branding, assets, subscription design or repurpose Caps Lock; global shortcuts need a separately justified user choice.

## Implementation-turn recheck

2026-10-05: read-only CLI status again reports Awake Off, assertion/clamshell false, Normal, licensed fan with unsupported fan hardware. Exact hidden native window1441/PID50684 remains AX-unresolved with zero elements; bounded native navigation cannot resolve dashboard/settings. T002 completes its permitted **unresolved-surface disposition**, not a hands-on design comparison. No LidRun mode/settings/fans/licensing changed.

## Baseline label clarification

Any CamLid Settings AX observation containing section labels, checkbox detection or Save Changes describes the pre-M4b baseline. Current controls are recorded in [QA refinement evidence](../../docs/qa/qa-refinement-report.md). Unresolved LidRun native surfaces remain unresolved; no layout/design parity is inferred from CLI status.
