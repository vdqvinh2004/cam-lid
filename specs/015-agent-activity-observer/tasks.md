# Tasks: Agent Activity Observer

**Feature context:** `015-agent-activity-observer` · **Status:** 10/11 checked. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decisions
- [x] T001 Record the owner decisions (observer only; Claude Code back) in ADR 0002 and mark the hook/plugin tasks in spec 004 (T003–T005, T007, T011) as closed by that decision. — ADR 0002 written; spec 004 T003, T004, T005, T007, T011 closed by it.

## Phase 1 — Core
- [x] T101 `EvidenceKind.activity` with rank, confidence cap and Auto permission; update every switch over evidence kinds and their tests. — `EvidenceKind.activity` (rank 1 between lifecycle 3/wrapper 2 and process 0, confidence cap inferred, may arm Auto).
- [x] T102 Pure `AgentActivityClassifier` with table tests (working by CPU, by session file, by children; idle after quiet; exit; unreadable → unknown; clock jumps). — `AgentActivityClassifier` in `AgentActivity.swift`; 9 tests. Constants are provisional (marked `shortcut:`) until T401.
- [x] T103 Precedence: Orca lifecycle beats activity for the same agent; activity beats process. — Processes started under an Orca process are not sampled, so Orca lifecycle evidence decides for them; activity outranks process presence.

## Phase 2 — Native sampling
- [x] T201 Per-pid CPU time and descendants in `NativeProcessList`; bounded and cheap enough for the existing tick. — `NativeProcessList.activityProcesses`: outermost agent process per subtree with summed CPU time (`proc_pid_rusage`). Found while testing: Claude Code's installed binary runs under its version number (`2.1.314`), so a version-like name is resolved from the executable path (also used by presence discovery).
- [x] T202 Bounded newest-mtime scan of each agent's session directory, never reading contents. — `SessionActivityProbe`: newest modification time under the agent's own directory, bounded scan every 30 s plus a cheap re-check of the newest file; contents never read. **Dropped 2026-10-31 after calibration:** shared directories and missing writes made it unreliable; the probe was removed.
- [x] T203 Wire samples through the classifier into `RuntimeAgentStore`; history and status record provider, state and reason only. — Coordinator classifies each sample into `activity` tasks used by badges, Dashboard rows, Auto policy and `camlid status`; a classified idle process no longer makes completion "uncertain", so Sleep when done runs. Activity changes are not written to history (only the protection transitions they cause). 2 integration tests.

## Phase 3 — Claude Code and labels
- [x] T301 Claude Code back in the catalog, process discovery and Settings (neutral mark, no installer). — Claude Code back in the catalog with an SF Symbol mark, no artwork and no installer.
- [x] T302 "(estimated)" labels for activity evidence in the Dashboard, Settings, status and history. — Badges append "(estimated)" when only activity evidence backs them; `camlid status` lists tasks with `evidenceKind: activity` and `confidence: inferred`.

## Phase 4 — Calibration and trial
- [ ] T401 Calibration script and owner-run timelines for Claude Code, Codex and OpenCode; set constants; record in `calibration.md`. — **Partly done 2026-10-31:** Claude Code (Haiku 5.5) measured by Claude in three runs; `busyCPUFraction` 0.03 and `quietSeconds` 45 confirmed, session-file signal dropped ([calibration.md](calibration.md)). Codex (quota) and OpenCode (no login) not measured; tool-using runs not measured.
- [x] T402 Trial 8 of spec 014 (Auto with a real agent, closed lid) using this observer. — Done 2026-10-31 (run 3, Claude Code Haiku 5.5): see [014 g2-trial.md](../014-persistent-helper/g2-trial.md). 014 T706 still needs app kill and helper kill.
