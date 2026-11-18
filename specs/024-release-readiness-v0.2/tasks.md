# Tasks: release gate for v0.2

**Feature context:** `024-release-readiness-v0.2` · **Status:** see the counts line below. Risks are in [spec.md](spec.md).

Evidence: full runs of the three test targets on 2026-11-16, after the muted-playback change (288, 397 and 68 tests pass, no failures), and on 2026-11-10 (288, 371 and 68 tests pass, after the music hold change), and the 2026-11-09 full run (358 tests in 69 suites, also under CPU load); the ad-hoc 0.2.0 build,
the tag refusal, and the skill command check on the installed build. Items marked owner need a real Mac or an owner
decision.

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
- [~] G12 R9 Display hold: done on the QA build (2026-11-09). The display assertion appears only with the option off and is released on stop (023 T013). R10 Music hold: Brave's "Playing audio" assertion appears and is released (023 T034). Brave, Spotify and Apple Music were measured with a read-only probe on 2026-11-10 and replayed through the hold logic. Music per source, QA copy, 2026-11-16 (Auto session, Claude Code selected, music sources on): Spotify and Apple Music were detected while playing and released after pause (popover reason and chip). Google Chrome and Brave, each playing a 3-minute test file, were detected as "Music is playing in Chromium browsers." (chip "Chromium browsers playing"), and each was paused and released: Chrome paused about 11:35:35, the reason and the "Sleep when done" countdown (After 2 min) appeared within 8 s, and the hold released at 11:37:44; Brave paused about 11:38:35, same sequence, released at 11:40:40. The owner's own paused playback in Brave was not resumed; the test file was opened in a new Brave tab and closed afterwards. Safari, 2026-11-16 after the signal fix (macOS 27.0.1, QA copy): a local audio file and a YouTube video were detected as "Music is playing in Safari."; each was paused and released (audio 12:10:57 to 12:13:08, video 12:19:12 to 12:21:20; the reason clears about 9 s after pause). Muted Safari playback counts (2026-11-16 test). Muted Chromium, Spotify and Apple Music playback is not verified: on 2026-11-16 the owner decided these tests are not needed, and accepted that a track which starts muted is not detected. Details in 025.
- [~] G13 R12 Settings General and Sleep diagnostics: the General top section and the Sleep diagnostics window were checked on the QA build. The lower sections (AI agents, Updates) need scrolling, which background input could not do; 2026-11-16 (QA copy): light appearance checked on the General pane (top sections and Updates) and on the Agents pane; dark restored. The AI agents section below Updates could not be scrolled (background wheel, keys and foreground keys did not move the pane), so its clipping was not checked visually; its controls are present in the accessibility tree. VoiceOver excluded by the owner's request. Decision D3.
- [ ] G14 R13 Owner reviews the privacy wording in README and SECURITY.md (021 T032).
- [x] G15 R14 One short closed-lid session with the replacement build, then restore (safety). Passed; the owner confirmed it on 2026-11-18.
- [x] G16 R15 Launch at login after the app was replaced. Passed; the owner confirmed it on 2026-11-18.
- [~] G17 R16 Turning the skill on writes `~/.agents/skills/camlid/SKILL.md` with no privacy prompt on the installed build, and turning it off removes the file (location changed 2026-11-09). 2026-11-16 (QA copy): on writes the file into the QA home (matches the bundled file), off removes it; a file CamLid did not write gives the alert "Replace the skill file that already exists?": Cancel keeps it, Replace overwrites it. Not checked: the installed build's path and privacy prompt (owner).
- [~] G18 R19 Update switch on the QA build: on writes the setting, off clears it. 2026-11-16 (QA copy): the manual "Check for Updates" ran and reported "You're up to date" (installed 0.2.0); no deferral while agents work was seen. The scheduled request was not observed. Owner: confirm one request a day on the installed build (021 T051).
- [ ] G19 R22 An agent reads the skill and keeps a build awake with `camlid run` (022 SC-001).
- [x] G20 R21 Skill command check (spec 022 FR-004), run on 2026-11-09 with the release zip's CLI against the isolated QA instance: `status`, `helper status`, `diagnose`, refused `start --duration 2m`, `stop` with no session, `run -- /usr/bin/true` (exit 0), and exit 4 when CamLid is not running. Also run earlier on the installed build. Repeated 2026-11-16 on the final release zip (commit 76cfa90, SHA-256 841954fe…; the earlier zip from d982ac1 gave the same results) against an isolated instance with its own state folder: status 0, helper status 0 (installed), diagnose 0, start --duration 2m refused (exit 2, invalidDuration), stop with no session 0, run -- /usr/bin/true 0, and exit 4 when CamLid is not running. Repeated again on 2026-11-16 on the zip from d052f2e (SHA-256 99d2f1ab…) with the same results, against an isolated instance started from the unzipped copy.
- [x] G21 R17 The release zip's SKILL.md equals `.agents/skills/camlid/SKILL.md`; the zip's SHA-256 verifies (2026-11-09).
- [ ] G26 R25 Owner check after the next update of the skill manager: the CamLid folder in `~/.agents/skills` stays, and the manager's update or removal does not touch it. CamLid never edits `.skill-lock.json`.

## Decisions
- [x] G22 D1 Commit the v0.2 work on branch `v0.2`, as one commit on 2026-11-16. `release.sh` refuses a dirty tree.
- [x] G23 D2 Version 0.2.0 in `project.yml` and the project file. Set in commit `66b3aaf`; the owner confirmed 0.2.0 on 2026-11-16.
- [ ] G24 D3 How to run the GUI check (isolated QA state directory, or the owner). The isolated directory worked for the checks; the owner decides.
- [ ] G25 D4 Whether the v0.1.0 carry-over items (R23) block v0.2. Recommendation: no.

## Release steps (after the gate)
- [x] S1 `CAMLID_SIGN_IDENTITY=<release certificate> sh scripts/release.sh 0.2.0` on the owner's Mac. Built and checked 2026-11-16 from commit d052f2e: dist/CamLid-0.2.0-macos-arm64.zip, SHA-256 99d2f1ab…, App CDHash 611d1944…, bundled helper CDHash cf33ff7f…, CLI CDHash 443dfc53…; signature, helper pin (the certificate, not a CDHash), skill file, notes and the G20 skill command check on this zip. The zip's app was installed over /Applications/CamLid.app the same day; the helper was not reinstalled (same certificate, helper version 1). The owner's checks G15 and G16 passed on 2026-11-18. Fixed 2026-11-16: release builds map the temporary build folder and strip the debug map (-oso_prefix, -S), so two builds of one commit give identical executables and CDHash.
- [x] S2 Owner uploads the zip, checksum and notes as a GitHub pre-release, then tags `v0.2.0` (ADR 0004). Done 2026-11-18 at the owner's request: branch `v0.2` pushed (to 8384162); annotated tag `v0.2.0` at d052f2e, the built commit; pre-release "CamLid 0.2.0 beta" published at https://github.com/vdqvinh2004/cam-lid/releases/tag/v0.2.0 with the zip and its checksum. The zip downloaded from the release is byte-identical to the built one. The notes can still be edited with `gh release edit` (021 T050).
- [x] S3 Moved specs 021, 022, 023, 024 and 025 from "implemented" to "released", and updated the spec index, on 2026-11-18.

Counts: 17 done, 4 partly (G12, G13, G17, G18), 5 open (G14, G19, G24–G26), 3 release steps done (S1 2026-11-16; S2 and S3 2026-11-18).
