# Feature Specification: Agent Activity Observer

**Feature context:** `015-agent-activity-observer`; draft, no code yet.
**Created:** 2026-10-31
**Owner decisions (2026-10-31):** CamLid stays a pure outside observer: it installs no hooks, plugins or wrappers and
never edits an agent's configuration. Claude Code is supported again.

## Problem
Auto keeps the Mac awake while agents work and lets it sleep after they finish. Today only Orca reports working/idle
(`lifecycle` evidence). Agents run directly in a terminal (Claude Code, Codex, OpenCode) are seen only as running
processes, which by design never arm Auto (`processOnlyNoArm`), because a running process does not prove work.
Most users run these CLIs directly, so Auto does nothing for them.

## Approach
Infer working or idle from signals the agent produces anyway, observed read-only:
1. **Process lifetime.** A non-interactive run (`claude -p`, `codex exec`, `opencode run`) works while its process
   lives; exit ends the work.
2. **CPU activity of the agent process and its descendants.** Interactive agents redraw a progress spinner and run
   tools while working, and sit near 0% CPU while waiting for the user. Measured as CPU-time growth per window.
3. ~~Session-file activity~~ — **dropped after calibration** ([calibration.md](calibration.md)): the directories are
   shared by every session of an agent, and the calibration sessions wrote nothing there.
4. **Tool subprocesses.** Shells, compilers and git started by the agent count through the CPU of the agent's
   process subtree. A plain count of children is not used: agents keep long-lived children (MCP servers) that would
   make them look busy forever.

A task is **working** if any signal was active in the last activity window, **idle** after all signals have been
quiet for the quiet period, and **unknown** when signals cannot be read. The evidence kind is a new `activity`, with
confidence capped at `inferred`.

## User Scenarios & Testing

### User Story 1 — Auto with an agent run directly in a terminal (Priority: P1)
**Acceptance**
1. With Auto on and Claude Code, Codex or OpenCode selected, starting work in the terminal makes the agent show as
   working within the activity window, and Auto holds the Mac awake (closed lid included, under spec 014 rules).
2. When the agent finishes and waits for input, it shows as idle after the quiet period; Auto starts "Sleep when
   done" and then releases.
3. A non-interactive run holds while its process lives and releases when it exits.
4. If signals cannot be read, the agent shows as Unknown, which never proves completion (existing rule).

### User Story 2 — Honest labels (Priority: P1)
1. Activity-based state is labelled as estimated in the Dashboard, `camlid status` and history ("Working (estimated)").
2. Orca's lifecycle evidence, when present for the same agent, takes precedence over activity evidence.

### User Story 3 — Claude Code is back (Priority: P2)
Claude Code appears in the agent catalog and Settings › Agents again, detected by its `claude` process, with a
neutral mark (the earlier bundled artwork was removed).

### Edge Cases
- Long model thinking with no visible redraw or file write: may read as idle. Mitigated by calibration and the quiet
  period; this is the main accuracy limit and is stated in the UI.
- Several sessions of the same agent: process signals are per process; the session-file signal is per agent, so it
  can only extend "working", never prove one specific session idle.
- An idle agent left open for hours: idle, so Auto releases; the process alone never holds power.
- A busy unrelated child (a dev server started by the agent) keeps the agent "working"; bounded by the session cap.
- Sleep or clock jumps: windows use the continuous monotonic clock.

## Requirements
- **FR-001** No hooks, plugins, wrappers, environment changes or configuration edits for any agent.
- **FR-002** Read only: process table (pid, parent, start time, executable name, executable path for version-named
  binaries, CPU time). Never file contents; never prompts, transcripts or paths in history.
- **FR-003** New evidence kind `activity`, confidence at most `inferred`, ranked below `lifecycle` and above `process`;
  it may arm Auto.
- **FR-004** Thresholds (activity window, quiet period, CPU threshold) are constants calibrated on real sessions per
  agent and recorded with their measurements; not user settings.
- **FR-005** Sampling failure or a missing session directory degrades to Unknown or to the remaining signals; never
  to idle by default.
- **FR-006** Labels state that activity-based states are estimates.
- **FR-007** Claude Code returns to the catalog, process discovery and Settings without any integration installer.

## Success Criteria
- **SC-001** On the owner's Mac, for each of Claude Code, Codex and OpenCode, working is detected within 15 s of
  starting a turn and idle within the quiet period after it ends, across a recorded calibration set.
- **SC-002** No calibration run shows idle during an active turn (false release) longer than the quiet period.
- **SC-003** Unit tests cover the classifier, sampling failure, process exit and precedence.

## Non-Goals
Hooks or plugins; reading transcript content; network inspection; remote or cloud agents; qualifying Orca freshness
(separate, 002 T002).
