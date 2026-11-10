# Tasks: release gate for v0.2

**Feature context:** `024-release-readiness-v0.2` · **Status:** see the counts line below. Risks are in [spec.md](spec.md).

Evidence: full runs of the three test targets on 2026-11-10 (288, 371 and 68 tests pass, after the music hold change), and the 2026-11-09 full run (358 tests in 69 suites, also under CPU load); the ad-hoc 0.2.0 build,
the tag refusal, and the skill command check on the installed build. Items marked owner need a real Mac or an owner
decision. Live checks of 2026-11-09 and 2026-11-10 are in [qa-evidence.md](qa-evidence.md).

## Code and tests (done)
- [x] G01 R1 Settings write budget injected for tests; full suite passes under CPU load (previously failed).
- [x] G02 R2 `Info.plist` version follows the build setting; the 0.2.0 ad-hoc candidate passes `verify`.
- [x] G03 R3 `release.sh` refuses a version whose tag exists (checked with `0.1.0`).
- [x] G04 R4 Release notes: "new in 0.1.0" and "new in 0.2" labels, three v0.2 features, one known limit (checked in the candidate notes).
- [x] G05 R5 Audio hold is bounded by the Auto run cap (`runCapMinutes`, non-resetting cap in `PolicyEngine`).
- [x] G06 R6 Audio reads at most every 2 s while a hold is in force and every 5 s otherwise (spec 025 FR-003; `theReadsAreEveryFiveSecondsWhenIdleAndEveryTwoWhileHolding`).
- [x] G07 R7 The skill refuses links on the path; three tests.
- [x] G08 R8 SKILL.md: a run can leave the Mac awake while agents work.
- [x] G09 R11 Diagnostics report allow-list test (`excludedDetailNeverAppears`).
- [x] G10 R24 Dashboard reason during the audio hold.
- [x] G11 R18 Helper guard passes (`ok: helper version 1` in the candidate build).

## Checks that need a real Mac or the owner
- [~] G12 R9 Display hold: done on the QA build (2026-11-09). The display assertion appears only with the option off and is released on stop (023 T013). R10 Music hold: Brave's "Playing audio" assertion appears and is released (023 T034). Brave, Spotify and Apple Music were measured with a read-only probe on 2026-11-10 and replayed through the hold logic. Not done: a full CamLid run per source, and the other Chromium browsers. See [qa-evidence.md](qa-evidence.md).
- [~] G13 R12 Settings General and Sleep diagnostics: the General top section and the Sleep diagnostics window were checked on the QA build. The lower sections (AI agents, Updates) need scrolling, which background input could not do; light and dark, and a VoiceOver walkthrough, were not run. Decision D3.
- [ ] G14 R13 Owner reviews the privacy wording in README and SECURITY.md (021 T032).
- [ ] G15 R14 One short closed-lid session with the replacement build, then restore (safety).
- [ ] G16 R15 Launch at login after the app was replaced.
- [ ] G17 R16 Turning the skill on writes `~/.agents/skills/camlid/SKILL.md` with no privacy prompt on the installed build, and turning it off removes the file (location changed 2026-11-09).
- [~] G18 R19 Update switch on the QA build: on writes the setting, off clears it. The first scheduled request (next hourly tick) and the manual check (deferred while agents work) were not observed. Owner: confirm one request a day on the installed build (021 T051).
- [ ] G19 R22 An agent reads the skill and keeps a build awake with `camlid run` (022 SC-001).
- [~] G20 R21 Skill command check (spec 022 FR-004), run on 2026-11-09 with the release zip's CLI against the isolated QA instance: `status`, `helper status`, `diagnose`, refused `start --duration 2m`, `stop` with no session, `run -- /usr/bin/true` (exit 0), and exit 4 when CamLid is not running. Also run earlier on the installed build. Repeat on the release zip before publishing (S1).
- [x] G21 R17 The release zip's SKILL.md equals `.agents/skills/camlid/SKILL.md`; the zip's SHA-256 verifies (2026-11-09).
- [ ] G26 R25 Owner check after the next update of the skill manager: the CamLid folder in `~/.agents/skills` stays, and the manager's update or removal does not touch it. CamLid never edits `.skill-lock.json`.

## Decisions
- [ ] G22 D1 Commit the v0.2 work on branch `v0.2`. `release.sh` refuses a dirty tree.
- [ ] G23 D2 Version 0.2.0 in `project.yml` and the project file. Set in commit `66b3aaf`; the owner confirms the number.
- [ ] G24 D3 How to run the GUI check (isolated QA state directory, or the owner). The isolated directory worked for the checks in qa-evidence.md; the owner decides.
- [ ] G25 D4 Whether the v0.1.0 carry-over items (R23) block v0.2. Recommendation: no.

## Release steps (after the gate)
- [ ] S1 `CAMLID_SIGN_IDENTITY=<release certificate> sh scripts/release.sh 0.2.0` on the owner's Mac. Then repeat the skill command check (G20) on the release zip.
- [ ] S2 Owner uploads the zip, checksum and notes as a GitHub pre-release, then tags `v0.2.0` (ADR 0004).
- [ ] S3 Move specs 021, 022, 023, 024 and 025 from "implemented" to "released"; update the spec index.

Counts: 12 done, 4 partly (G12, G13, G18, G20), 10 open (G14–G17, G19, G22–G26), 3 release steps.
