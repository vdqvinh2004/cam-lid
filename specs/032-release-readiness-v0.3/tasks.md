# Tasks: release readiness for 0.3.0

`[x]` done. `[ ]` still open. Modelled on [spec 024](../024-release-readiness-v0.2/tasks.md).

## Code and build

- [x] R1 Version 0.3.0, build 2 in `project.yml` and the project file.
- [x] R2 Full suite: 499 tests, 0 failures, on commit `a566c67`.
- [x] R3 Helper guard: `ok: helper version 1`. The helper sources are unchanged.
- [x] R4 `scripts/test-release-arguments.sh` and `scripts/test-check-helper-version.sh` pass.
- [x] R5 Release notes list the status menu and the command-line changes.
- [ ] R6 `CAMLID_SIGN_IDENTITY="CamLid Release Signing" scripts/release.sh` from a clean commit: signature, hardened runtime, one certificate for app and helper, bundled SKILL.md equal to the repository's.
- [ ] R7 The zip's SHA-256 verifies.
- [ ] R8 The release build installed on the owner's Mac: the app runs, and `camlid version`, `status` and `helper status` read correctly.

## Checks for the owner

- [ ] O1 Status menu on the installed build: no Show Dashboard in the icon menu; Timed starts with the Settings duration; Auto and Stop still work.
- [ ] O2 One short closed-lid session with this build, then restore (as in spec 024, G15).
- [ ] O3 Upload the zip, its checksum and the notes as a GitHub pre-release, then tag `v0.3.0` (ADR 0004).
- [ ] O4 After the release is published: move specs 026 to 031 to "released" (as in spec 024, S3).
- [ ] O5 Read the release notes wording.
