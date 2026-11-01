# Calibration (spec 015 T401)

Measured with `scripts/agent-activity-calibrate.py` on the owner's Mac (Mac17,3, macOS 26A434), 2026-10-31.
Agent: Claude Code 2.1.314 with `claude-haiku-5-5`, prompts that need no tools, temporary working directory.
Codex was not measured (quota exhausted); OpenCode was not measured (no login found).

CPU is the growth of CPU time of the agent's whole process subtree, as a fraction of one core, averaged over 5 s
(the app samples every 5 s).

| Run | Phase | 5 s averages |
|---|---|---|
| TUI, 300-word answer | waiting for input before the prompt | 0.000–0.020 |
| | answering (about 8 s) | 0.09–0.21 (1 s samples) |
| | waiting for input after | 0.010–0.039, one 1 s spike of 0.137 |
| TUI, 1,200-word answer | just launched | 0.08–0.34 |
| | waiting before the prompt | 0.023–0.054 |
| | answering (about 30 s) | 0.050–0.128 |
| | waiting for input after (90 s) | 0.006–0.015, one window of 0.054 |
| `claude -p`, 800 words | process lifetime about 25 s, then exit | 0.04–0.44; the subtree total drops as children exit |

## Decisions
- **`busyCPUFraction = 0.03`.** Every answering window was at or above 0.05; settled waiting windows were at most
  0.015. Occasional spikes above 0.03 while waiting only delay sleep by one quiet period; they never cause an early one.
- **`quietSeconds = 45`.** Unchanged: answering windows never dropped below the threshold in these runs, so the quiet
  period only has to bridge short pauses between steps.
- **Session-file signal dropped.** The interactive calibration sessions wrote no transcript under `~/.claude/projects` (only the `claude -p` run did, at its end), and that
  directory is shared by every Claude Code session, so another active session (including the one running this
  calibration) would keep every Claude Code process "working". Codex and OpenCode keep similarly shared directories.
  The app uses process lifetime and subtree CPU only.
- **Subtree CPU can drop** when a child exits; the classifier treats a drop as "no usable delta", keeps an active task
  working through the quiet period, and otherwise waits one sample.

## Not covered
Long model "thinking" without visible output was not isolated; the answering windows include streaming. Interactive
runs with tool use, Codex and OpenCode remain to be measured before they are relied on.

## Amendment (2026-11-01): one busy sample is not work
During Strict trial S1 the owner saw "Claude Code · 1 working" on an idle Claude Code after the Mac woke, and the
session had already returned from "Sleep when done" to protected once after Claude had finished. Measured afterwards,
the idle subtree ran at 0.004–0.020 of a core, below the 0.03 threshold; the false "working" came from single
5-second bursts (the reconnect after a wake, a write after a turn), which the classifier counted as work and then
held for the 45 s quiet period. Change: from idle, two consecutive busy samples (10 s) are required; an agent that is
already working needs one, so answering (continuously 0.05–0.21) is unaffected apart from about 5 s more to detect
its start. A sample gap over 30 s (sleep, stall) gives no rate. Start and end of work are now recorded in Activity.
