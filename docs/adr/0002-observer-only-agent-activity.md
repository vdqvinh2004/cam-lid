# ADR 0002: Agents are observed from outside only; activity is inferred

- **Status:** Accepted (owner decision, 2026-10-31)
- **Affects:** spec 004 (agent integration), spec 015 (agent activity observer)

## Context
Auto needs to know whether an agent is working or finished. Orca reports this; agents run directly in a terminal
(Claude Code, Codex, OpenCode) do not, unless CamLid installs hooks, plugins or wrappers into them. Most users run
these CLIs directly.

## Decision
1. CamLid stays a pure outside observer. It never installs hooks, plugins or wrappers, never changes an agent's
   configuration or environment, and never takes part in an agent's process.
2. For directly run agents, working or idle is inferred from what the agent already produces: process lifetime and CPU
   activity of the agent and its descendants (session-file times were dropped after calibration). This evidence is a new kind, `activity`, capped at `inferred` confidence and labelled
   as an estimate; it may arm Auto.
3. Claude Code is supported again (observation only).

## Consequences
- Auto works for directly run agents without touching them; accuracy is lower than lifecycle events, mainly when a
  model thinks for a long time with no visible activity. Thresholds are calibrated on real sessions (spec 015 T401).
- Spec 004 tasks that install integrations (T003, T004, T005, T007, T011) are closed by this decision.
