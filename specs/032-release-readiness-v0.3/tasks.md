# Tasks: release readiness for 0.3.0

`[x]` done. `[ ]` still open. Modelled on [spec 024](../024-release-readiness-v0.2/tasks.md).

## Code and build

- [x] R1 Version 0.3.0, build 2 in `project.yml` and the project file.
- [x] R2 Full suite: 499 tests, 0 failures, on commit `a566c67`.
- [x] R3 Helper guard: `ok: helper version 1`. The helper sources are unchanged.
- [x] R4 `scripts/test-release-arguments.sh` and `scripts/test-check-helper-version.sh` pass.
- [x] R5 Release notes list the status menu and the command-line changes.
- [x] R6 Built and checked 2026-11-23 from commit `e6f3d4c` with `CAMLID_SIGN_IDENTITY="CamLid Release Signing" scripts/release.sh`: signature, hardened runtime, one certificate for app and helper, bundled SKILL.md equal to the repository's (the script's own checks, all passed). App CDHash `5a1dfe97b78e51b3a3e706b7d93244fc9f9eefab`; helper CDHash `7d3263f82ef1d8a6701099b756eab80ea31cb115`.
- [x] R7 The zip's SHA-256 verifies: `4ab8f6e0965269478fcd4dd3f950d92af86d6aa949a076f540b0db29d9e82eda` (the release's `.sha256` asset). An independent extraction also passes `codesign --verify --deep --strict`.
- [x] R8 Installed on the owner's Mac on 2026-11-23; build 1 is kept in `~/Library/Application Support/CamLid/Update/before-0.3.0-b2-install-20261123-111237`. The app runs (one process). `camlid version` reports app and CLI 0.3.0 build 2 and helper `installed`; `status` reports `Ready` with no session and an unchanged revision (297); `helper status` reports `installed`.

## Checks for the owner

- [x] O1 Status menu on the installed build: no Show Dashboard in the icon menu; Timed starts with the Settings duration; Auto and Stop still work. Owner check passed (2026-11-23).
- [x] O2 One short closed-lid session with this build, then restore (as in spec 024, G15). Owner check passed (2026-11-23).
- [x] O3 Done 2026-11-23: the zip, its checksum and the notes are on the pre-release https://github.com/vdqvinh2004/cam-lid/releases/tag/v0.3.0, and the annotated tag `v0.3.0` points to `e6f3d4c`, the build commit (ADR 0004).
- [x] O4 Done 2026-11-23, in the commit after the release: specs 026 to 031 are "released" in their status lines and in the index (as in spec 024, S3).
- [ ] O5 Read the release notes wording.
