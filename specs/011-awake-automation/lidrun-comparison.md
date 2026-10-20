# LidRun vs CamLid — feature decisions

Reviewed **2026-10-08**. Yes, earlier comparisons existed in [M4b](../010-qa-ux-sensors/lidrun-comparison.md) and [mode QA](../../docs/qa/mode-disclosure-lidrun-2026-10-07.md). This replaces their feature-gap baseline for M8 planning, not their historical test results.

**Evidence boundary**: Installed LidRun CLI 1.2.25 was inspected using help, status and patterns only. No power, watch-list, notification or fan setting changed. Published features below are vendor claims, not independent physical verification. CamLid is still **Preview: no live power backend**. “Implemented” below means the named UI/policy/read-only function exists, not physical protection.

| Feature | LidRun evidence | Current CamLid | Worth adding? / ownership | How CamLid can do better |
| --- | --- | --- | --- | --- |
| Actual idle/closed-lid keep-awake | Advertised idle hold and Pro closed-lid helper [L1,L2]; CLI exposes start/stop | Preview policy only; no verified live backend | **Essential**, existing M1/M2; M8 consumes it in US2, never duplicates it | Publish exact tested support rows, bounded ownership and verified restoration; never imply all Macs work |
| Timer and indefinite sessions | UI timer 30m–8h; manual indefinite; CLI seconds [L2,L3] | Timed finite/Infinite implemented in policy; Infinite still has safety stops | **Already covered**; backend integration US2 | One Timed mode, editable active duration starting now, no separate Manual/Off or Start button |
| Charging/battery controls | Charging condition, adjustable low-battery guardrails [L2,L4] | Battery operation opt-in, minimum battery and AC policy implemented | **Already covered**; physical acceptance M1/M2 | Explain AC required vs battery allowed and why a start/stop was blocked; charging is not AC presence |
| Thermal / CPU safety | Thermal guardrails [L4]; dedicated CPU-stop control not confirmed | Critical/serious thermal policy plus optional sustained CPU stop implemented | **Already covered**; validate real integration | Separate thermal pressure, qualified temperature and CPU pressure; no universal invented Celsius threshold |
| Allow display sleep toggle | Separate setting not established in reviewed official feature pages | Settings stores preference; live effect missing | **Essential**, M8 US2 | Apply preference to owned assertions; allow sleep by default; closed-lid internal display must stay off |
| AI/dev Auto Mode | Pro process/agent watches [L1,L6]; local watch list observed | Four providers and evidence states; passive observation can remain Unknown | **Already covered / qualification pending**, M3 | Distinguish detected CLI, process present, working, waiting and unknown; never equate low CPU with completion |
| Command-bound keep-awake | CLI wrapper holds until direct command exits [L3]; independent wrapper lacks app safety when app absent | Existing wrapper provides child lifecycle evidence/exit behavior, no power hold | **High value**, M8 US3 | Opt-in protection admitted before launch; central battery/thermal policy and expiring ownership; preserve argv/stdin/stdout |
| Custom process/app watches | `watch`, `unwatch`, `patterns` confirmed in help; Pro Auto advertised [L1,L6] | Provider inclusion only; arbitrary workload rules missing | **Useful**, M8 US4 | Exact executable/app identity, PID reuse protection, explicit lifetime wording, user Stop cannot be undone by a rule |
| Sleep from terminal | Installed help exposes guarded `sleep` and `--force` | Restoration gate exists; no explicit CLI sleep command | **Useful**, M8 US5 | Dry-run with all reasons; stale work/display/input blocks; no force bypass; request differs from observed sleep |
| Why Mac is awake | Activity/assertion inspection/global SleepDisabled described [L7] | Read-only per-process + aggregate assertion window implemented | **Extend**, M8 US1 | Same bounded/redacted GUI/CLI report, kernel/global coverage limits, correct display/system semantics |
| Activity / release reasons | Activity decisions and report views advertised [L2,L7] | Private bounded transition history and full-row details implemented | **Already covered** | Evidence freshness, restoration failures and exact reason; omit idle metrics with no decision value |
| Local outcome alerts | Installed CLI `notify` confirmed; vendor advertises alerts [L3,L8] | No user notification delivery for completion/safety outcomes | **Useful**, M8 US6 | Native opt-in alerts, deduplication, accurate Preview/requested wording; critical alert survives ordinary rate limit |
| Launch at login | Onboarding choice advertised [L9] | Stored preference only; no actual registration integration found | **Useful**, M8 US7 | Native OS registration/read-back; approval/revocation shown; login never starts a session |
| Smart Rules / time windows | Condition/action automation advertised [L5]; exact limits/tier not settled | No general condition/action engine | **Defer**; cover concrete lifetime gap via US4 | Keep safety controls fixed and explainable; add scheduling only for a demonstrated recurring workload |
| Phone push and webhooks | ntfy/Pushover; Telegram/Discord/Slack/custom channels advertised [L8] | None | **Defer**, outside M8 | Local-first privacy; remote destinations/credentials only after real demand and a separate threat model |
| GUI Run Command | Run & Watch advertised [L1,L3] | Terminal wrapper only | **Defer** | Terminal already serves coding workflows; avoid command-history/output capture and a second launcher |
| Fan control / cooling modes | CLI `fan` confirmed; this Mac reports licensed=true, supported=false | None | **Exclude v1**, constitution | Report unsupported hardware honestly; cannot promise a fix through a license or blindly copy vendor controls |
| Battery charge limiting | Not established in reviewed official docs/CLI | None | **Exclude v1** | Do not invent a competitor capability; charge control is separate from safe keep-awake |
| Weekly summaries / reports | On-demand weekly workstation report advertised [L10] | Activity history, no weekly dashboard | **Defer** | Add an export summary only when it answers a user's concrete question; no decorative stats |
| Watchdog / crash restoration | Vendor advertises watchdog/recovery [L1,L2] | Recovery model/journal/CLI rescue pieces exist; live executor absent | **Essential**, existing M1/M2, not a new duplicate feature | Separate app/helper/joint/OS failure classes and foreign ownership; healthy-lease bound is not a universal crash guarantee |
| JSON / script control | `status --json` confirmed | Shared-policy CLI and simulator implemented | **Already covered**, extend US1/3/4/5 | Versioned reason codes; configured mode separate from active session and actual backend lease |

## Recommended milestone

**M8 Awake Automation & Diagnostics**, [spec](spec.md), [plan](plan.md), [tasks](tasks.md).

Immediate MVP: **US1 diagnostics**. US6 local alerts and US7 login can follow without live power actuation. US2 display integration, US3 protected wrapper, US4 lifetime holds and US5 actual sleep consume qualified M1/M2 output. Simulated policy work may precede it; physical claims cannot.

The biggest gap is real keep-awake, already owned by M1/M2. More controls do not resolve that gap. Finish that foundation before advertising overnight or closed-lid protection. M8 adds seven useful workflows rather than copying every LidRun feature.

## Sources

- **L1**: [LidRun pricing](https://lidrun.com/pricing): broad tier claims; not a hardware support guarantee.
- **L2**: [Closed-lid guide](https://lidrun.com/blog/keep-mac-awake-when-lid-closed): helper/global override, completion choices and restoration claims.
- **L3**: [CLI guide](https://lidrun.com/blog/lidrun-cli-keep-awake-terminal): wrapper vs app-controlled commands and safety difference. Installed help is fresher for `sleep`/`fan`, which the article's command list omits.
- **L4**: [Safety](https://lidrun.com/safety), [getting started](https://lidrun.com/guide/getting-started): battery, charging and thermal claims; exact emergency-floor wording varies.
- **L5**: [Smart Rules](https://lidrun.com/blog/smart-rules-mac-power-automation): advertised condition/action combinations; no verified standalone scheduled-start command.
- **L6**: [Auto Mode](https://lidrun.com/blog/auto-keep-awake-only-while-working): vendor descriptions do not establish reliable completion evidence for every process.
- **L7**: [Awake diagnostics](https://lidrun.com/es/blog/what-is-keeping-your-mac-awake): global/assertion troubleshooting. Its display/system assertion explanations are reversed; [Apple assertion definitions](https://developer.apple.com/documentation/iokit/iopmlib_h/iopmassertiontypes) take precedence.
- **L8**: [Notifications](https://lidrun.com/guide/notifications): destinations and app-running dependency; no messages sent.
- **L9**: [Installation](https://lidrun.com/guide/install): login option; actual registration behavior not tested.
- **L10**: [Weekly report](https://lidrun.com/blog/weekly-mac-workstation-report): on-demand summary, not proof of scheduled reporting.

Current CamLid baseline: [sleep diagnostics QA](../../docs/qa/sleep-diagnostics-2026-10-08.md), [mode behavior QA](../../docs/qa/mode-disclosure-lidrun-2026-10-07.md), and source review of Configuration, PowerController, RunCommand, AppCoordinator and Settings. These distinguish read-only/policy implementation from missing live backend.
