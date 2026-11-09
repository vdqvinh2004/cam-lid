# Feature Specification: Agent skill for the CamLid command

**Status:** Planned for the release after 0.1.0. Not in 0.1.0. No code and no file yet.

## Context

- The `camlid` command inside the app is already on the Mac. It is the control surface for AI agents. An MCP server is
  out of scope.
- [ADR 0002](../../docs/adr/0002-observer-only-agent-activity.md): CamLid installs no hooks, plugins or wrappers and never
  edits an agent's configuration.

## Goal

Give AI agents one short skill file that says when and how to use `camlid`: keep the Mac awake for one command, check
the state, start or stop a session, and diagnose.

## Requirements

- **FR-001** One skill file in the SKILL.md format, in English, under 80 lines, with no secrets.
- **FR-002** It covers only these commands: `camlid status --json`, `camlid run -- <command>`,
  `camlid start --mode auto|timed --duration <value>`, `camlid stop`, `camlid diagnose --json`, `camlid helper status`.
- **FR-003** It tells agents not to change CamLid's settings, not to install or remove the helper (that needs an
  administrator password), not to stop a session they did not start, and not to retry a refused `start` in a loop.
- **FR-004** Before each release, every command in the file is checked against the installed `camlid` binary.
- **FR-005** CamLid never writes the skill into an agent's folder by itself. The user copies it.

## Success criteria

- **SC-001** An agent that reads the skill keeps a build awake with `camlid run` and reports the result, without asking
  the user how.
- **SC-002** Each command in the skill gives the output the file describes, checked on the release build.

## Decisions (owner)

1. **Where the file ships:** in the repository only, or also in the app bundle. Proposed: repository, and the README
   links to it.
2. **A `camlid skill` command** that prints the file. It adds code and needs a new version. Proposed: not in the first
   version of the skill.
3. **Amend ADR 0002** so that CamLid can install the skill on request. Proposed: no. Keep the observer-only rule.

## Out of scope

- An MCP server, a plugin or a hook. The owner has decided that the CLI is enough.
- Automatic installation into an agent's folder. It conflicts with ADR 0002 unless decision 3 changes.
