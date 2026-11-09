# Feature Specification: Agent skill for the CamLid command

**Status:** Decided 2026-11-09; implemented for v0.2, the release after 0.1.0, not released yet. The skill file, the Settings
button, the bundled copy and the release check are in place. The file goes to the home folder (changed 2026-11-09 from a project folder). Open: SC-001 (an agent run) and the GUI check. Plan:
[plan.md](plan.md). Tasks: [tasks.md](tasks.md).

## Context

- The `camlid` command inside the app is the only control surface for AI agents. An MCP server is out of scope.
- [ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md) forbids CamLid from editing an agent's configuration.
  Decision 3 below amends it for one file.
- Agents that follow the `.agents/skills/<name>/SKILL.md` convention read skills from that folder. The spec-kit skills of
  this repository are in the project's `.agents/skills/`; the owner's other skills are in `~/.agents/skills/`.

## Goal

Give AI agents one short skill that says when and how to use `camlid`. Let each user choose whether the skill is added for
their Mac.

## Requirements

- **FR-001** The skill lives at `.agents/skills/camlid/SKILL.md` at the repository root. It is in English, under 80 lines,
  and has no secrets. Done: 51 lines.
- **FR-002** It covers `camlid status --json`, `camlid run -- <command>`, `camlid start --mode auto|timed --duration <value>`,
  `camlid stop`, `camlid diagnose --json` and `camlid helper status --json`. It does not cover installing or removing the
  helper.
- **FR-003** It tells agents not to change CamLid's settings, not to stop a session they did not start, not to retry a
  refused `start` in a loop, and to ask the user to run helper commands that need an administrator password.
- **FR-004** Before each release, each command in the file is run or parsed against the installed `camlid` binary.
  Checked on 2026-11-09: `run`, `stop` (no session), `status`, `helper status`, `diagnose`, and a refused
  `start --duration 2m`.
- **FR-005** Settings › General gets a button, "Let AI agents use CamLid". It is off by default.
- **FR-006** Turning the button on writes `~/.agents/skills/camlid/SKILL.md` in the user's home folder. No folder is asked
  for. CamLid writes only after the user presses the button, and never at launch.
- **FR-007** CamLid never overwrites a `.agents/skills/camlid/SKILL.md` it did not write. It asks first.
- **FR-008** Turning the button off removes only the file CamLid wrote, and only if its contents are unchanged.
- **FR-009** The app bundles the same SKILL.md, copied from the repository at build time, so the button works for users who
  downloaded the zip. The release script fails if the bundled copy differs from the repository file.
- **FR-010** The only file CamLid may write is that one skill file. No hooks, plugins, wrappers or agent settings.

## Success criteria

- **SC-001** An agent that reads the skill keeps a build awake with `camlid run` and reports the result, without asking
  the user how.
- **SC-002** Turning the button on writes exactly one file, and turning it off removes only that file.
- **SC-003** The bundled skill matches the repository file in every release.

## Decisions (owner, 2026-11-09)

1. **Location:** the repository root `.agents/` folder, not `.agent`. It is the folder the existing skills use. Done.
2. **Opt-in button** in Settings › General, off by default. It writes one file, `~/.agents/skills/camlid/SKILL.md`, in the
   user's home folder. Changed on 2026-11-09 at the owner's request; the first version asked for a project folder each time.
3. **ADR 0002 amended** for that one file. Hooks, plugins, wrappers and agent settings stay forbidden.
4. **No `camlid skill` command.** The app bundles the file (FR-009), so one is not needed.

## Tradeoff

- An agent that reads only its own folder (for example `.claude/skills`) will not see a skill that lives in `.agents`.
  Copying the file into agent folders would change agent configuration, which ADR 0002 forbids. That is a separate
  decision.
- The file is in the home folder, so every project on this Mac sees it, not one project. Turning the button off removes
  it for all of them.

## Out of scope

- An MCP server, a plugin or a hook.
- Writing into any agent's own configuration folder.
