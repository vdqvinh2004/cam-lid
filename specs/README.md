# CamLid Milestone Specs

One scoped Spec Kit feature folder per milestone; requested project convention. Spec Kit uses
feature folders and one selected feature context; it does not itself require milestones as folders.
The shared roadmap (kept outside this repository) defines cross-feature gates and detailed procedures.


> **2026-11-03 reconciliation.** The milestone folders 002-011 were written before the design changed (observer-only
> agents, one persistent helper, GitHub releases). Their task lists now mark tasks `[x]` when evidence exists, `[~]`
> when [ADR 0002](../docs/adr/0002-observer-only-agent-activity.md), [0003](../docs/adr/0003-strict-mode-lid-only-on-the-persistent-helper.md)
> or [0004](../docs/adr/0004-distribution-through-github-releases.md) replaced them (the reason is on the line), and
> leave `[ ]` only for work that is still valid. Current work is the release after 0.1.0, v0.2 (specs 021 and 022), and spec 016 (remaining trials). Specs 019 and 020 plan later versions.

- [M0: Project Planning](001-project-planning/spec.md) — Complete: documentation only.
- [M1: Power and Detection Feasibility](002-power-feasibility/spec.md) — **Closed for this design:** the backend question was answered by the persistent helper (014) and Strict (016), qualified on one Mac by attended trials.
- [M2: Native Foundation and Safety](003-native-foundation/spec.md) — **Implemented:** helper, lease, journal, recovery and telemetry run and were tried on hardware (014, 016). Open: integrated flood tests (T014).
- [M3: Agents and Orca Integration](004-agent-integration/spec.md) — **Closed:** agents are observed from outside only ([ADR 0002](../docs/adr/0002-observer-only-agent-activity.md)); Orca by its CLI, terminal agents by CPU activity (015).
- [M4: Native UX and Activity History](005-native-ux/spec.md) — **Implemented:** menu bar, Dashboard, three Settings panes, Activity. Open: a walkthrough of the notch and left/right placements (T006).
- [M4a: Apple HIG UI/UX Refinement](009-apple-hig-ux/spec.md) — Mostly closed by direct inspection (2026-11); open: keyboard and VoiceOver walkthrough (T011).
- [M4b: QA-driven UX and truthful telemetry](010-qa-ux-sensors/spec.md) — Mostly closed; 9 tasks remain open (dismissal timing matrix, sensor and contrast matrices, performance measurement).
- [M5: Signed Beta and Updates](006-signed-beta/spec.md) — **Superseded** by [ADR 0004](../docs/adr/0004-distribution-through-github-releases.md): GitHub releases, ad-hoc signed, no notarization, no Sparkle.
- [M6: AI Quality Gate](007-ai-quality-gate/spec.md) — **Superseded** by owner-attended trials and a public pre-release ([ADR 0004](../docs/adr/0004-distribution-through-github-releases.md)).
- [M7: Supervised Real User Testing](008-user-testing/spec.md) — **Superseded:** early adopters report through the "Qualify my Mac" issue template.
- [M8: Awake Automation & Diagnostics](011-awake-automation/spec.md) — Diagnostics ("Why is my Mac awake?"), notifications and login adapters done; the wrapper and display-sleep parts are not planned; open: the `camlid sleep` command with revalidated admission (T030, T031).

Experimental feature spec (not a milestone; no gate change):

- [Closed-lid best-effort mode (012)](012-closed-lid-best-effort/spec.md) — Offline model implemented; R0 accepted historically. Full-Sleep/continuity/failure-class G2 qualification and separately approved G3 integration remain open. Manual, finite, attended, AC-only scope; no verified-restoration claim. **Review 2026-10-31:** all remaining tasks closed as superseded by spec 014 or moved to M5/M6/M7.

- [M9: Closed-Lid Best-Effort Hardening (013)](013-closed-lid-hardening/spec.md) — Original offline scope plus reproducibility follow-up complete (22/23 current tasks checked, including auth-only install-packet preparation and T501 foreign-policy row PASS with operator attestation); overall G2 and G3 T502 remain blocked. Current reproducibility/handoff work (kept outside this repository) preserves those gates. **Review 2026-10-31:** T502 closed as superseded by spec 014 (sign-off is 014 T601).

- [Persistent Helper, Standard mode (014)](014-persistent-helper/spec.md) — Implemented, 31/31 tasks, signed off by the owner 2026-11-03 for Mac17,3 / macOS 26A434. Replaces the blocked exclusive-create/one-use admission with a root LaunchDaemon installed once through administrator authentication ([ADR 0001](../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md)). Strict now runs on this helper (see 016). Native actions on other Macs still need explicit owner approval and a qualified row.

- [Agent Activity Observer (015)](015-agent-activity-observer/spec.md) — Phases 0–3 done and trial 8 passed (T402, 10/11); calibration of Codex and OpenCode (T401) pending. Observer-only working/idle inference for agents run directly in a terminal (Claude Code, Codex, OpenCode) so Auto works without Orca; no hooks or configuration edits.
- [Strict Mode, Lid-Only (016)](016-strict-lid-only/spec.md) — Phases 1–2 (helper, app) done; trials S1–S4 passed and recorded in ADR 0003 (14/16); Standard on battery and the optional E5 observation remain. Strict runs the lid-only clamshell bit on the persistent helper (ADR 0003); experimental, AC only, per-row qualified.
- [Release readiness for v0.1.0 (017)](017-release-readiness/spec.md) — **Shipped** as the v0.1.0 pre-release on 2026-11-09 (tag at ed2d060, owner approved, T035). Open: the live Dashboard check (T015, partly).
- [Lid-open keep-awake, command wrapper, shortcut (018)](018-lid-open-and-run/spec.md) — **Included in v0.1.0** (owner decision, 2026-11-06); open items are in its tasks file.
- [Coverage, Vietnamese, maintenance (019)](019-coverage-and-localization/spec.md) — **Planned** for v0.3.
- [v1.0 gates (020)](020-v1-gates/spec.md) — **Planned:** conditions for 1.0; adds no features.
- [Automatic update setting (021)](021-automatic-updates/spec.md) — **Implemented for v0.2** (the release after 0.1.0). Decided 2026-11-09: Off by default, one check a day when on. ADR 0004 is amended; install is deferred. Open: the owner's review of the privacy wording.
- [Agent skill for the CamLid command (022)](022-agent-skill/spec.md) — **Implemented for v0.2** (the release after 0.1.0). The skill is in `.agents/skills/camlid/SKILL.md`; the opt-in Settings button writes it into a project folder. ADR 0002 is amended for that one file. No MCP. Open: an agent run (SC-001).

Each folder contains its scoped spec/plan/tasks; supporting research/model/quickstart/checklists
exist where applicable (012 uses the linked decision memo and runbooks). Base runtime contracts reside with M2/M3; M8 adds scoped automation extensions while consuming the existing policy/transport/backend contracts.
The shared product spec, architecture, limitations and domain model (kept outside this repository)
are sources of truth, shared references rather than additional milestone features. Local task IDs restart; the migration map (kept outside this repository)
preserves all 60 future tasks once. M0's four completed tasks are document work only.

## Feature Selection
This checkout has no `.specify/feature.json`. Use explicit feature context; current offline
current work is scoped to `SPECIFY_FEATURE_DIRECTORY=specs/014-persistent-helper`.
Selection alone passes no release gate or native-action permission.
Run Spec Kit against a single folder from repository root, for example:
```
SPECIFY_FEATURE_DIRECTORY=specs/002-power-feasibility rtk .specify/scripts/bash/check-prerequisites.sh --json --require-spec --require-tasks --include-tasks
```
Set same feature context when using `$speckit-plan`, `$speckit-tasks`, `$speckit-analyze` or later
`$speckit-implement`; in a fresh session inspect any local selection and prefer explicit context before running skills.
Current setup-plan preserves an existing plan; still use read-only prerequisite inspection to inspect context.
Prerequisite check resolves documents only, not milestone PASS. Preview implementation/QA authorized by subsequent user instructions; live actuation still gated.
