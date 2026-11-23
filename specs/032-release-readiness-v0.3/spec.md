# Release readiness: CamLid 0.3.0

**Status:** In progress · **Date:** 2026-11-23 · **Gate for:** the v0.3 release, as [spec 024](../024-release-readiness-v0.2/spec.md) was for 0.2.0.

## Scope

- Version **0.3.0, build 2** in `project.yml` and `CamLid.xcodeproj/project.pbxproj`. Build 1 was the local install before this gate. No `v0.3.0` tag exists yet; the tags are `v0.1.0` and `v0.2.0`.
- Contents: specs [026](../026-in-app-update/spec.md) to [031](../031-cli-parity/spec.md) (in-app update, update notice and helper, Vietnamese UI, general audio hold, About panel, CLI parity with the app), and the status menu's Timed item (commit `a566c67`).
- Release notes: the status menu and the command-line changes are listed in `scripts/release.sh`.

## Decisions

- **D1. Version.** The owner confirms it, as for 0.2.0. Proposed: 0.3.0, because 0.3 has no release yet. To change it, set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` before the build.

## Not in scope

- Uploading the zip, its checksum and the notes to GitHub, and tagging `v0.3.0` (ADR 0004). The owner does that.
- Moving specs 026 to 031 to "released" before the release is published (as spec 024, S3).
