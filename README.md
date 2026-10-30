# CamLid

Native macOS menu bar app for AI-aware closed-lid work.

**Status (2026-10-31): preview.** Telemetry is read-only. Closed lid may hold the Mac awake only when the user opted in,
the helper is installed, and either the Mac matches a support row qualified by an attended trial (`QualifiedSupportRows`;
today one row: Mac17,3 with macOS 26A434) or the user accepted "untested configuration" for this exact model and macOS build in Settings ›
Safety › Closed lid. The attended G2 trial passed on one Mac (Mac17,3, macOS 26A434; see
[g2-trial.md](specs/014-persistent-helper/g2-trial.md)). Known conflict: the LidRun helper resets the sleep setting and
interrupts closed lid. M6 has not passed and M7 is blocked.

**Deployment model.** The closed-lid helper is a root LaunchDaemon installed once with administrator
authentication (Standard mode), replacing the earlier exclusive-create / one-use admission. The earlier
mechanism remains as a frozen, experimental Strict mode. Decision: [ADR 0001](docs/adr/0001-persistent-helper-and-strict-experimental-mode.md);
work: [spec 014](specs/014-persistent-helper/spec.md) (see its tasks file for status). Install and status commands: `camlid helper install|uninstall|trust|status` (administrator rights needed
for all but `status`), or Settings › Safety › Closed lid.

Dashboard, Settings, Welcome, Activity and Updates run in an owned UI subprocess that exits when its last surface
closes; the persistent menu-bar process is the sole policy, preferences, history, update-check and CLI authority.
Battery, thermal, CPU, built-in-display and lid telemetry is read-only; missing or stale sources stay Unknown.
The CLI reaches the running app over an authenticated same-user local socket.
See the [milestone folders](specs/README.md) for scope and status.

## Build and verify

Canonical toolchain: Xcode 27.0, Swift 6.4, macOS 27 SDK; deployment target macOS 14.
This does not establish compatibility with other OS/hardware rows. Legacy CLT Swift 6.1.2
warm tests passed, but clean SwiftUI imports encountered SDK module conflicts; use Xcode
consistently and separate scratch directories from older compiler builds.

```sh
rtk env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --no-parallel \
  --package-path Packages/CamLidCore --scratch-path /tmp/camlid-spm-xcode
rtk xcodebuild -project CamLid.xcodeproj -scheme CamLid -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/camlid-xcode \
  CODE_SIGNING_ALLOWED=NO build
rtk python3 scripts/verify-preview.py
```

The last command runs tests, Debug/Release builds, actual CLI-binary integration, and
read-only hardware preflight, recording logs/hash manifests under `docs/qa/preview-evidence`.
Provider-runtime/version probes remain disabled. Verification cannot grant M1/M6 approval. `project.yml`
is the XcodeGen source; regenerate with `rtk xcodegen generate` when targets change.
Tool target is `camlid-tool`, product `camlid`, avoiding case-insensitive target collisions.

## Preview controls

The menu-bar mark changes from a laptop while idle to white Auto arrows or a white Timed clock; safety stops retain a warning mark. Left-click toggles the dashboard; right-click opens quick options. Modes are visible
button badges: click Auto or Timed to start, click the active mode again to stop.
Timed includes ∞ Infinite: no time limit on AC, with battery/thermal safety stops and explicit charger/battery preferences retained. Battery exposure always imposes a finite session ceiling. Auto and finite Timed sessions keep their time limits. Sleep when done controls Auto’s completion delay from the dashboard. Timed shows an editable duration while running; changing it starts the new duration now. Auto shows an editable Sleep when done delay. Neither control appears while stopped. Settings contains Defaults, Agents, Safety, and Activity. Defaults apply to future sessions; dashboard edits affect only the current session. Mode switches retain the original session start: Infinite removes the AC-only deadline but cannot clear an established battery ceiling; a finite Timed choice can shorten an existing limit without extending it. Settings selects which agents may delay sleep, with Enable all and bounded
safety preferences. Settings shows installed CLI detection; dashboard shows selected agents reporting work. Mode activation opens a preview session; it cannot keep the
Mac awake. Check for Updates reports unavailable in this unsigned preview; Defaults exposes launch-at-login intent and actual macOS registration status; signed login acceptance remains gated.

Dashboard uses compact icon/value metrics with no Details section. Agent badges say Task unknown
when activity cannot be verified; a running process alone does not prove work or completion.
Safety offers Require charger and separate Allow battery sessions switches, an editable battery entry level (20–80%, default 40%, above the stop floor), a battery limit (15–240 minutes, default 60), battery cutoff, and session limit. Battery sessions require both charger requirement off and battery opt-in on. Their ceiling is min(session limit, battery limit), measured from session start; reconnecting AC or editing the timer cannot extend that ceiling. Infinite bypasses time limits only while exclusively on AC. Advanced explains waiting for agent input and the optional 90%-CPU-for-2-minutes stop. Battery preference changes take effect immediately. The timer countdown appears only in Timed, with 5/10/15-minute choices under a 15-minute cap. [Current battery and controls review](docs/qa/battery-controls-2026-10-08.md) and [LidRun feature comparison](docs/qa/mode-disclosure-lidrun-2026-10-07.md).
Saved preferences never restore an armed session. Invalid persisted preferences use safe
preview defaults. Config and revision persist together; concurrent stale settings are refused.

Using the built CLI while the app runs:

```sh
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid status --json
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid diagnose --json
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid sleep --dry-run --json
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid config get --json
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid config set --file patch.json --dry-run
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid watch list --json
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid watch add --executable /absolute/path/to/tool
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid watch add --bundle-id com.example.tool
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid watch remove <rule-id>
rtk /tmp/camlid-xcode/Build/Products/Debug/camlid logs export --redacted --output events.json
```

`diagnose` and the “Why is my Mac awake?” window share a bounded on-demand report. JSON removes owner/preventer names, PIDs and raw assertion reasons; missing coverage stays explicit. Status separates saved `configuredMode` from nullable `activeSessionMode`. Diagnostics never clears another app’s request.
`sleep --dry-run` reports blockers without mutation; actual `sleep` refuses in Preview, with no force option. Legacy `run` refuses unconditionally under the third-person architecture; no agent is launched or wrapped. See the [M8 command contract](specs/011-awake-automation/contracts/awake-automation.md) for implemented versus deferred paths.
`watch` edits exact lifetime-rule preferences through revision-checked config; Settings also lists, adds, enables, and removes watched programs. During an explicitly active Auto session, CamLid samples same-user executable paths and app bundle IDs, reports a separate lifetime reason, and blocks completion sleep while presence or uncertainty remains. Process presence never creates AI activity or an AI completion event; saved rules do not start a session. Preview still performs no power actuation.
Current owner-directed source changes: Settings → Permissions keeps optional Notifications only; CamLid no longer requests Accessibility or polls agent UI. Settings → Agents uses Detect Orca as the only switch for read-only CLI observation and keeps the mixed-JSON disclosure. The legacy `orcaMetadataConsent` key remains readable for compatibility but no longer controls observation. No Screen Recording or Full Disk Access is required. Software verification passed 489 tests in each Debug/Release plus Xcode build; isolated QA updated. Sanitized live status now shows Orca Working1, Codex process2 and OpenCode process4, with standalone task states Unknown. Native QA confirmed Notifications-only Permissions and fully visible Orca source disclosure at the new default Agents size; comprehensive accessibility/appearance and standalone activity qualification remain open. Orca queries run only when Orca is selected for detection; turning Detect off discards late results. [Current verification boundary](docs/qa/no-ax-terminal-observation-2026-10-14.md).

Defaults → Notifications stores opt-in categories; explicit GUI enablement requests native permission. CLI config edits never request notification permission. Returning to Settings refreshes actual OS permission/login state. Utility windows provide standard native editing commands and shortcuts. Login and notifications start off; saved intent does not arm a session. Isolated native QA verified failure delivery in Notification Center and permission grant/readback/revoke; complete native alert acceptance and signed login/update/uninstall remain open.

Config mutations, status, agents, Stop, and export use the app's state; unreachable app
returns exit 4. `start [--mode auto|timed|manual] [--duration 30m]` starts a session through the same path as the Dashboard (exit 0), or refuses with a reason code (exit 3: `modeOff`, `closedLidNotPermitted`, battery entry, `sessionAlreadyActive`); power is held only once the helper confirms, shown as `leaseVerified` in `status`.
Legacy `event`, `bridge` and `run` now refuse with exit3/`externalObservationOnly` before
reading stdin, forwarding events or launching a child. App IPC also rejects provider events,
tool diagnostics and command admissions; internal CamLid status/config/history remain available. `quit` requests preview-app exit,
reporting no owned power resources; future live backend shutdown needs confirmed restoration.
Recovery apply without a confirming helper remains unresolved; dry-run is restorable, not verified.
`simulate --scenario file.json` uses isolated clocks/sensors and never touches host power.

Owner explicitly permits read-only Orca CLI observation without a separate consent toggle, distinct from hooks/bridges or agent actions. When Detect Orca is enabled, mixed JSON may pass through local temporary memory; only opaque pane identity/state/query clocks are retained, never prompt/message/tool content in history/logs/exports or sent to AI/server. Turning Detect Orca off stops new reads and discards late results. This is not a zero-data-collection claim, and receipt freshness is not proof of underlying state freshness or complete job coverage. Standalone Codex/OpenCode Working/Idle remains unqualified; process presence alone is not work. [Current scope and verification](docs/qa/no-ax-terminal-observation-2026-10-14.md).
Same-user Orca/Codex/OpenCode/Claude process discovery needs no provider setup. Process
presence alone is Unknown, never proof that a task is working or finished. No bridges, hooks,
provider configuration changes, LaunchAgents or external background services are required. No prompts/transcripts are logged. History is private,
rotated JSONL, capped at 14 days / 20 MiB; export salts vary between exports. Storage failures
stay visible. See [agent compatibility](docs/qa/agent-compatibility.md).

For isolated native QA, launch the app with `--qa-state-directory /tmp/camlid-qa-<unique>`;
create that root directory first. It uses separate preferences/history/control endpoint.
Set `CAMLID_CONTROL_DIRECTORY` to `<root>/control` for the CLI. Native launch uses CUA Driver;
no GUI automation may bypass screen lock. The normal launch path uses user Application Support.

## Remaining gates

[Roadmap](docs/planning/roadmap.md), [limitations](docs/planning/limitations.md),
[constitution](.specify/memory/constitution.md), [CLI contract](specs/003-native-foundation/contracts/cli.md),
[helper contract](specs/003-native-foundation/contracts/power-helper.md),
[preview transport decision](docs/planning/preview-control-decision.md).
M1 supervised lid/display/manual-Sleep/recovery validation precedes backend selection.
Conditional helper/durable ownership journal, installed-agent acceptance, signed updates,
native accessibility/performance QA, and consenting real-user trials remain open.
No fixed recovery deadline is promised after helper/OS hangs. No fan/charging control exists.

Spec Kit uses one folder per milestone M0–M8 (including M4a/M4b). Explicit `SPECIFY_FEATURE_DIRECTORY` scopes
skill work; the selected feature does not imply gate completion. This repository now tracks the source and documentation; generated binaries and private
raw QA archives remain ignored. Preview implementation and QA do not authorize native actions.

### Passive agent supervision

**Owner direction, 2026-10-15:** continuous keep-awake during externally observed agent work remains the core goal, followed by guarded sleep eligibility when all tracked work is confirmed non-working and the completion delay expires. Unknown/incomplete coverage is not completion. Opportunistic DarkWake is not the product backend; its isolated experiments are historical research only, with the unstarted closed-lid comparison parked. No hook/bridge/wrapper or agent configuration changes. This direction does not enable the unqualified closed-lid power backend. [Decision and limits](docs/planning/third-person-agent-observation-2026-10-13.md).

Latest continuous-supervision source increment shares completion-uncertainty guards between Auto and Sleep dry-run/manual paths: selected Orca unqualified coverage, Unknown or positive process presence never proves completion. Debug/Release489tests each + XcodeDebug build passed; installed QA app was not replaced and power remains disabled. [Red/green evidence and remaining gates](docs/qa/continuous-supervision-resumption-2026-10-15.md).

Pinned Orca admission now accepts reviewed `1.4.224`/`1.4.226` only; other versions still refused and coverage still unqualified. Debug/Release491tests each + XcodeDebug build passed (includes UX refresh); installed QA app was not replaced. [Compatibility evidence](docs/qa/orca-1-4-226-source-compatibility-2026-10-15.md); [backend refresh still blocked](docs/research/continuous-closed-lid-backend-refresh-2026-10-15.md).

Dashboard shows selected providers reporting work. Settings → Agents shows whether each CLI is installed and controls whether each
provider may delay sleep; selection never launches provider work.
Orca now has the same outside-observer boundary as standalone providers. Process presence cannot
establish working/idle, remote work or detached child state. Unknown evidence remains Unknown;
missing or incomplete scans must not claim absence. Legacy stream/wrapper entry points are disabled,
not optional product integrations. [Boundary correction and tests](docs/qa/third-person-boundary-2026-10-13.md).

Numeric CPU temperature appears only when the bounded read-only reader has a current supported sample; missing/stale readings stay explicit. The public thermal API reports pressure, labeled separately. A numerical reading does not qualify a closed-lid backend or hardware safety row.
Closed-lid protection is implemented behind the qualified-row gate described above and is not active in shipped builds; without it this preview owns no power resources. See
[current supervision QA](docs/qa/passive-supervision-report.md). VoiceOver acceptance is
excluded by user request; keyboard and native accessibility semantics remain in scope.

### M5 update and packaging preparation

Check for Updates… opens the native Updates window. CLI `status --json` includes the same `updates` state. Sparkle 2.10.0 is pinned; checks are information-only, manual, and deferred during sessions/work/recovery or an unsaved draft. Unsigned/ad-hoc builds and missing feed/key stay explicitly unavailable. No update installation is implemented yet.

`rtk python3 scripts/package-beta.py --app /path/CamLid.app` audits the bundle without changing it. Add a new `--output-directory` to make a local preview zip; existing destinations are refused. See specs/006-signed-beta/quickstart.md for signed-candidate prerequisites. This preparation does not pass M5 or enable closed-lid operation.
