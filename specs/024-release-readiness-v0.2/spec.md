# Feature Specification: release readiness for v0.2

**Status:** In progress, 2026-11-09. Code for specs 021, 022 and 023 is complete and tested. Nothing is released or
committed. The gate is in [tasks.md](tasks.md).

## Scope

The v0.2 release contains the work in:

- [spec 021](../021-automatic-updates/spec.md): once-a-day update check, off by default.
- [spec 022](../022-agent-skill/spec.md): agent skill file and its Settings button.
- [spec 023](../023-feature-parity/spec.md): display option, copyable diagnostics, Chromium audio hold.

Not in scope: the carry-over verifications of v0.1.0 (spec 018 T016, T022 to T024, T031; spec 017 T015). They stay listed
as known limits in the release notes.

## Risk register

Severity is the harm to a user or to the release if the risk happens. "Closed" means a change or a test removes the risk.
"Open" means an owner action or a live check is still needed.

| # | Risk | Evidence | Severity | Status and action |
| --- | --- | --- | --- | --- |
| R1 | Settings saves fail under CPU load because the write budget is a fixed 0.7 s; two tests failed at random | Reproduced under 8 CPU-burning processes (PreferenceDeadlineTests, UIUXRefinementTests). The budget is in `applySettingsPatchAsync` | High: tests unreliable; a real save can fail on busy storage | Closed for tests: the fixture sets a 10 s budget through `settingsWriteBudget`. Production keeps 0.7 s and shows the existing "storage is busy, retry" message. Residual: watch for that message in use |
| R2 | A new version cannot be released: `Info.plist` hard-coded `0.1.0` | An ad-hoc 0.2.0 build failed at `verify`, "bundle version" | High: blocks the release | Closed: `Info.plist` reads `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`. The 0.2.0 ad-hoc build passes |
| R3 | `release.sh` run again with a published version overwrites that zip | The script deletes and rewrites `dist/CamLid-<version>.zip`; tag `v0.1.0` exists | High: silent change to a published artifact | Closed: refuses when the tag exists (not for `--adhoc`). Checked: `release.sh 0.1.0` is refused |
| R4 | Release notes call 0.1.0 features "new" and omit v0.2 features | Template in `scripts/release.sh` | Medium | Closed: labels say "new in 0.1.0" or "new in 0.2"; v0.2 features and a known limit added. Owner read-through still needed |
| R5 | A stuck "Playing audio" assertion keeps an Auto session awake for a long time | Auto sessions get a cap of `runCapMinutes` (default 120, max 480); the cap does not reset (`PolicyEngine`) | Medium | Accepted and bounded by the cap. Lower the run cap if the owner wants a shorter limit |
| R6 | The audio reader costs CPU on every policy tick | Each read is IOKit's copy of all assertions | Low | Closed: at most one read every 5 s (test `thePowerManagerIsReadAtMostEveryFiveSeconds`) |
| R7 | The skill writes through a symbolic link and could change a file outside the chosen folder | Code review of `AgentSkillInstaller` | Medium (security) | Closed: writes and removals refuse links on the path. Tests `aLinkOnThePathIsNeverWrittenThrough`, `aLinkedFolderIsRefused`, `aFileReplacedByALinkIsNeverRemoved` |
| R8 | An agent reads the skill and assumes `camlid run` lets the Mac sleep at once | Observed on this Mac: after `run` exited, the session stayed protected because Orca reported two working tasks. That is Auto's designed behaviour | Low to medium (agent behaviour) | Closed: SKILL.md says the Mac may stay awake while agents work |
| R9 | The display hold drains the battery | Default is "display may sleep" (D1). The hold applies only when the owner turns the option off | Medium | Mitigated by the default. Open: a live check that the assertion appears and is released (023 T013, T034) |
| R10 | The Chromium audio hold works for other browsers, or misses them | Research (spec 019 T070) checked Brave only | Medium | Open: a live check per browser. Release notes already say "checked on Brave only" |
| R11 | Copied diagnostics contain private data | Allow-list in `DiagnosticReport`; test `excludedDetailNeverAppears` | Low | Closed by test. The copy button is not clicked on a live app yet (023 T021) |
| R12 | The Settings General pane (four new sections) and the Sleep diagnostics header (two buttons) clip, scroll badly, or read badly with VoiceOver | Code only; the window height is fixed per pane (`preferredHeight` 520) | Medium | Open: GUI validation. Not run; see decision D3 |
| R13 | The privacy wording in README and SECURITY.md is wrong or not approved | The daily request changes what the docs promise | High: trust and accuracy | Open: owner review (021 T032). Nothing is published before it |
| R14 | A closed-lid session with the replacement build does not hold or restore | The helper pins the release certificate; the replacement is signed with it. Not exercised in a session | High: safety | Open: owner runs one short closed-lid session before release |
| R15 | Launch at login needs approval again after the app was replaced | Not tested | Medium | Open: owner check |
| R16 | Writing `~/.agents/skills/camlid/SKILL.md` triggers a macOS privacy prompt, or fails silently | The home folder is not Documents, Desktop or Downloads, so no prompt is expected. Not run on the installed build | Low | Open: owner check (G17). A refused write shows a message, not a silent failure |
| R17 | The installed app still carries the old skill text in its bundle | The bundle is copied at build time | Low | Closed by the next build. The release build copies the current file |
| R18 | The helper changed without a version bump | `check-helper-version.sh` passes; helper version 1; no helper source changed in this release | Low | Closed by the guard |
| R19 | The daily update check makes too many requests, or shows errors when offline | Unit tests cover once a day, sessions, relaunches | Low | Closed by tests. Open: the toggle on the installed build (021 T051) |
| R20 | Release built from uncommitted changes, or the tree is dirty at release time | `release.sh` refuses a dirty tree unless `ALLOW_DIRTY=1` | Process | Open: commit on `v0.2` before the release build (decision D1) |
| R21 | The spec 022 command check goes stale before release | FR-004 requires a check before each release | Process | Partly done: the command check ran on the installed build (see tasks). Repeat on the release build |
| R22 | The agent-run success criterion (022 SC-001) is untested | Needs an agent on the owner's Mac | Medium | Open: owner |
| R23 | v0.1.0 carry-over verifications stay open (018 T016, T022 to T024, T031; 017 T015) | Tasks files | Medium | Accepted for v0.2 as known limits; decision D4 |
| R24 | The Dashboard does not say why the Mac stays awake during an audio hold | `statusReason` | Low | Closed: "A Chromium browser is playing audio." |
| R25 | The skill sits in `~/.agents/skills`, where a skill manager keeps `.skill-lock.json` for 49 skills. The CamLid folder is not in that file | 16 of the 65 folders there were already untracked, so untracked folders are normal here. Whether the manager's update or removal touches an untracked folder is not tested | Medium | Open: owner check after the next update of the manager. CamLid never edits `.skill-lock.json` |

## Decisions the owner must make

- **D1. Commit.** Commit the v0.2 work on branch `v0.2` before the release build. `release.sh` refuses a dirty tree, and
  the commit is the reference for the release notes.
- **D2. Version.** Use 0.2.0. Set `MARKETING_VERSION` in `project.yml` and the project file to 0.2.0. The release script
  already passes the version to the build, and `Info.plist` now follows the build setting.
- **D3. Live checks and the GUI.** Each check in the gate needs a real Mac. The GUI check would start a second copy of
  CamLid next to the one running now. Say whether to run it in an isolated QA state directory or leave it to the owner.
- **D4. Carry-over items.** Decide whether the v0.1.0 verifications (R23) block v0.2. The recommendation is no: keep them
  as known limits, as the release notes already do.

## Out of scope for this gate

- Publishing the GitHub release. Upload is a separate, deliberate step (ADR 0004).
