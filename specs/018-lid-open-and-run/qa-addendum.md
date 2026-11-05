# QA addendum: agent calibration (spec 018, US4, T040)

Date: 2026-11-05. Mac17,3, macOS 26A434 (the qualified row `mac17-3-26a434`).

## Method

`scripts/agent-activity-calibrate.py --mode tui`: one agent session per run in a new temporary folder. The script
accepts the trust dialog at about 5 s, sends the prompt at 30 s, and records once per second for 150 s. The prompt was
"Explain in about 300 words how tides form. Do not use any tools." The models were the cheap ones, at low effort, as
requested. On this date the script gained three things: `--arg` (extra arguments for the agent CLI), `--submit-delay`
(default 0.3 s, before Enter), and a 40×120 terminal for the agent process. The terminal size was added last, for Codex.

`cpu_rate` is the change in the agent's process-subtree CPU time per second, so 0.03 means 3% of one core. The
thresholds in `Packages/CamLidCore/Sources/CamLidCore/AgentActivity.swift` are `busyCPUFraction = 0.03` by default and
`0.01` for Codex. This addendum changes no threshold (T041 stays open).

## Runs

| Agent | Model and effort | Command | Valid |
|---|---|---|---|
| Claude Code | `claude-haiku-5-5`, `--effort low` | `claude --model claude-haiku-5-5 --effort low` | yes: the answer appears in the terminal (work shown as 11 s) |
| OpenCode | `opencode/big-pickle`, no effort option exists at the root command | `OPENCODE_CONFIG_CONTENT='{"model":"opencode/big-pickle"}' opencode --standalone` | yes: the answer appears; the model name appears in the terminal |
| Codex | `gpt-6-luna` (provider `headroom`), `model_reasoning_effort="low"` | `codex --model gpt-6-luna -c model_reasoning_effort="low"`, script option `--submit-delay 1.5` | yes: the answer appears; the state goes working, idle, working, idle |

Claude and OpenCode ran before the terminal-size change, with the default pty size. Both drew their answers, so the
size matters for Codex only, as far as these runs show.

Not counted:
- OpenCode, first attempt: `--model` is not accepted at the root command. OpenCode printed its help and exited at 2.6 s.
- Codex, first attempt (0.3 s before Enter, default pty size): no answer text in the terminal, and no session record
  for the run under `~/.codex/sessions`.
- Codex, second attempt (1.5 s before Enter, default pty size): 27 visible characters, all terminal control codes, and
  no answer. The third attempt changed only the terminal size, and the answer appeared. The default size is the likely
  cause, which is why the script now sets 40×120.

`--standalone` keeps the server inside the measured process tree. The user's own background service
(`opencode serve --service`) was not used. The default background mode was not measured, so this run does not show
where OpenCode's work happens in that mode.

## CPU by phase (1-second samples)

| Agent | Idle, 10–30 s | Answering, 30–60 s | After, 60–150 s |
|---|---|---|---|
| Claude Code | mean 0.026, max 0.135, 4 of 19 ≥ 0.03 | mean 0.052, max 0.277, 12 of 29 ≥ 0.03 | mean 0.013, max 0.392, 3 of 87 ≥ 0.03 |
| OpenCode | mean 0.024, max 0.139, 3 of 17 ≥ 0.03 | mean 0.071, max 0.301, 22 of 27 ≥ 0.03 | mean 0.013, max 0.280, 4 of 79 ≥ 0.03 |
| Codex | mean −0.011, max 0.096, 1 of 19 ≥ 0.03 | mean 0.034, max 0.362, 11 of 28 ≥ 0.03 | mean 0.005, max 0.296, 1 of 86 ≥ 0.03 |

Codex has its own threshold, 0.01. Against that value: idle median 0.0096 (3 of 19 samples ≥ 0.01), answering median
0.0195 (20 of 28), after median 0.0 (2 of 86). The idle baseline sits right at the Codex threshold, so in this run the
threshold leaves little margin. This is one run, recorded for T041; nothing was changed.

The first 10 s are left out of the idle column: they hold the start-up spike (Claude reached 1.78 in one second at about
6 s). Isolated samples above the threshold after the answer are what the one-busy-sample rule is meant to absorb.

## Not usable in this environment

- The `session_age` column. The newest write under each agent's session folder was 0–21 s old for Claude and 0.1–82 s
  old for OpenCode, because this account writes there all the time (including the conversation that produced this run).
  The column is not used to decide anything.
- Negative `cpu_rate` values: the subtree total drops when a child process exits (spec 015 records this too). Codex had
  one such sample in each of the first two phases; its subtree had up to 14 processes.
