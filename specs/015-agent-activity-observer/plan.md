# Implementation Plan: Agent Activity Observer

**Spec:** [spec.md](spec.md)

## Design
- **Sampler (CamLidApp, native):** extends `NativeProcessList` with per-pid CPU time (`proc_pidinfo` /
  `PROC_PIDTASKINFO`, user + system time) and parent links, so each agent process gets the CPU-time growth of itself and
  its descendants per tick. Session-directory activity is the newest modification time found by a bounded scan
  (depth- and count-limited) of the agent's own directory, cached between ticks.
- **Classifier (CamLidCore, pure):** `AgentActivityClassifier.step(previous, sample, now) -> (state, reasons)` with
  constants from calibration. Inputs: process alive/exited, CPU-time delta, child count, newest session mtime.
  Output: working / idle / unknown and a short machine reason (`cpu`, `sessionFile`, `children`, `exited`, `quiet`,
  `unreadable`).
- **Evidence:** `EvidenceKind.activity` (rank 1.5: below lifecycle, above process; confidence cap inferred). Fed into
  `RuntimeAgentStore` as normal tasks keyed by provider and pid+start time, so `PolicyEngine` (unchanged) arms Auto on
  it and runs the existing completion grace. Orca lifecycle tasks for the same agent take precedence.
- **Claude Code:** catalog entry (`claude`, CLI name `claude`, SF Symbol mark), process name in discovery, session
  directory `~/.claude/projects`.
- **Labels:** badge/status text "(estimated)" for `activity` evidence; history records only provider, state and reason.

## Calibration
`scripts/agent-activity-calibrate.swift`: samples a chosen agent process (CPU-time growth, children, session mtime)
every 2 s and prints a timeline; the owner runs it while doing "start a turn → wait for completion → leave idle" a few
times per agent. Constants are set from those timelines and recorded in `calibration.md`.

## Risks
- Low-CPU model thinking can look idle (the main limit); the quiet period trades false releases against slow sleep.
- Agents may change their session-file layout or TUI behaviour between versions; record versions with calibration.
