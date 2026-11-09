# Plan: agent skill for the CamLid command (v0.2)

**Spec:** [spec.md](spec.md) · **Tasks:** [tasks.md](tasks.md)

## Approach

The skill is a plain file. CamLid writes it only when the user asks, into one project folder the user chooses, and
removes it only if it wrote it and it is unchanged.

- **Skill:** `.agents/skills/camlid/SKILL.md` (51 lines). Every command in it exists in `Commands.swift`; the release
  check below also compares the bundled copy with this file.
- **Writer:** `AgentSkillInstaller` (`Packages/CamLidCore/Sources/CamLidApp/AgentSkillInstaller.swift`). It runs in the
  persistent app, which owns files and preferences, as `UtilityUIProcess.swift` requires. It keeps one record in the
  app's preferences: the folder and the SHA-256 of the file it wrote (`CamLidAgentSkillInstall`).
- **Ownership:** a file belongs to CamLid only if CamLid wrote it. Any other `SKILL.md` needs a second confirmation before
  it is replaced. Off removes the file only while its SHA-256 matches the record, and never removes a directory.
- **Settings window:** a toggle, "Let AI agents use CamLid", in Settings › General. The window picks the folder with an
  open panel, sends the request, and shows the conflict and failure alerts. It writes nothing itself.
- **Bundle:** `scripts/embed-helper.sh` copies the skill into `Contents/Resources` before the app is signed, so the
  signature covers it. The build fails if the source is missing.
- **Release check:** `scripts/release.sh` compares the bundled copy with the repository file in `verify()`, for the
  built app and for the app unpacked from the zip.

## Decisions taken without the owner

- The record stores one installation. A second folder is refused until the first one is turned off, because the first
  file would otherwise have no way to be removed.
- An identical `SKILL.md` that CamLid did not write is treated like any other: it needs confirmation, and CamLid does
  not claim it. Removing a file the user copied by hand would break FR-008.
- Turning Off leaves the `.agents/skills/camlid/` folders in place. FR-008 says to remove only the file.

## Not in this change

- SC-001 (an agent that reads the skill keeps a build awake). It needs an agent run on the owner's Mac.
- The release-time command check (FR-004) runs against the installed binary before each release. It is recorded in the
  tasks, not automated.
