# Tasks: Agent Activity Observer

**Feature context:** `015-agent-activity-observer` · **Status:** 0/11 checked. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [ ] T001 Record the owner decisions (observer only; Claude Code back) in ADR 0002 and mark the hook/plugin tasks in spec 004 (T003–T005, T007, T011) as closed by that decision.

## Phase 1 — Core
- [ ] T101 `EvidenceKind.activity` with rank, confidence cap and Auto permission; update every switch over evidence kinds and their tests.
- [ ] T102 Pure `AgentActivityClassifier` with table tests (working by CPU, by session file, by children; idle after quiet; exit; unreadable → unknown; clock jumps).
- [ ] T103 Precedence: Orca lifecycle beats activity for the same agent; activity beats process.

## Phase 2 — Native sampling
- [ ] T201 Per-pid CPU time and descendants in `NativeProcessList`; bounded and cheap enough for the existing tick.
- [ ] T202 Bounded newest-mtime scan of each agent's session directory, never reading contents.
- [ ] T203 Wire samples through the classifier into `RuntimeAgentStore`; history and status record provider, state and reason only.

## Phase 3 — Claude Code and labels
- [ ] T301 Claude Code back in the catalog, process discovery and Settings (neutral mark, no installer).
- [ ] T302 "(estimated)" labels for activity evidence in the Dashboard, Settings, status and history.

## Phase 4 — Calibration and trial
- [ ] T401 Calibration script and owner-run timelines for Claude Code, Codex and OpenCode; set constants; record in `calibration.md`.
- [ ] T402 Trial 8 of spec 014 (Auto with a real agent, closed lid) using this observer; closes 014 T706.
