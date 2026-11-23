# Feature Specification: in-app update (v0.3)

**Status:** Released in 0.3.0 beta on 2026-11-23. The owner chose D1, D3–D5 as recommended, and D2 was tested (see "Decided"). It changes ADR 0004 decision 4 and spec 021 decision 3 ("install mode: deferred"), so both are amended only if the owner approves. Builds 0.1 and 0.2 have no installer: their users update by hand once, and in-app updates start with 0.3.

## Goal

When "Check for Updates" finds a newer release, the app shows an "Update to <version>" button. A click downloads that release from GitHub, checks it, replaces the app and starts the new one. Nothing is downloaded or installed without the click.

## Today (0.2)

The check is information only: `GitHubReleaseDriver` reads the releases API, and `UpdateController` has no download or install command. The button opens the Releases page. The release zip is signed with the release certificate (leaf SHA-1 f13e5527…). The helper and the install record (`identity.json`) pin that certificate, so an app that keeps it keeps the helper. ADR 0004 says an in-app updater waits for a Developer ID; this spec asks the owner whether to change that.

## Decisions for the owner

- **D1. Install without a Developer ID.** Spec 021 waited for gate G1 (spec 020), and ADR 0004 names a Developer ID as the precondition. Recommended for v0.3: install with the certificate checks in FR-004 and keep G1 open. The alternative is to buy a Developer ID and notarize first.
- **D2. Gatekeeper on the installed copy.** Not verified: whether an app downloaded by the app itself carries the quarantine attribute. If it does not, the new app starts with no prompt, and the trust rests on FR-004 alone. If it does, the first launch of each update shows the Gatekeeper prompt, which undoes the feature. Test this before the plan; D1 covers the result.
- **D3. Pre-releases.** The check counts pre-releases (0.2.0 is one). Recommended: install whatever the check offers, pre-releases included, until 1.0.
- **D4. Confirmation.** Recommended: one sheet with "Install and Restart" or "Cancel", because the app quits. Without it, the click starts the install at once.
- **D5. Rollback.** Recommended: manual. The old app stays in the backup folder (FR-005), and the release notes say how to restore it. An automatic rollback is not planned.

## Decided 2026-11-18

- **D1.** Install without a Developer ID, with the certificate checks in FR-004. Gate G1 stays open. The owner's decision amends ADR 0004 decision 4 and spec 021 decision 3 in the same change.
- **D2.** Tested on macOS 27.0.1. A zip that an app downloads with `URLSession` (as a data task or a download task), or writes itself, and the app unpacks with `ditto`, carries no `com.apple.quarantine` attribute. This held for a bundle with `LSFileQuarantineEnabled` and for one without it, in `~/Library/Caches` and in `/private/tmp`. A control shows the attribute can be set and read. So the new app starts without the Gatekeeper prompt, and FR-004 is the only check. The QA run repeats this on the real app.
- **D3.** As recommended: pre-releases are installed until 1.0.
- **D4.** As recommended: one confirmation sheet before the app restarts.
- **D5.** As recommended: rollback is manual, from the backup folder.
- **D6.** 2026-11-18, owner: agent activity never blocks an install, because CamLid only observes agents (ADR 0002). A running session asks first. When the user agrees, the session is stopped right before the restart, after the download and checks have passed. If they fail, the session keeps running and nothing is changed.

## Requirements

- **FR-001** The button appears only after a check finds a newer compatible release, and it names that version.
- **FR-002** A click starts downloading the release's zip and its `.sha256` asset from GitHub. The request has no cookies and no account, as the check has (spec 021 FR-002).
- **FR-003** Install waits while a recovery is running or Settings have unsaved changes. Agent activity never blocks it (D6). A running session does not block it either: the confirmation asks whether to stop the session, and the session is stopped only after the user agrees and only when the restart starts, after the download and checks have passed. It uses the reasons in `UpdateSafetyContext` and says the reason in words.
- **FR-004** Before anything is replaced, all of these pass: the zip's SHA-256 matches the `.sha256` asset; `codesign --verify --deep --strict` passes on the new app; its signer leaf equals the running app's leaf; its identifier is `com.camlid.CamLid`; its version is newer than the running app's and equals the release tag. A failed check deletes the download, changes nothing, and names the check that failed.
- **FR-005** The app replaces its own bundle only after it has quit. A small script run by the app, without administrator rights, waits for the app to exit, moves the old app to a backup folder, moves the new one into place and starts it. The backup stays until the next update. If the app's folder cannot be written, the button falls back to "Open Releases".
- **FR-006** An update never changes the root helper. If the new app bundles a newer helper version, the app shows the existing "Reinstall helper…" state, which asks for an administrator password, as today.
- **FR-007** The README privacy section and SECURITY.md name the download, as spec 021 FR-006 names the check.

## Success criteria

- **SC-001** Unit tests give each check in FR-004 a fixture that fails: a wrong checksum, a missing `.sha256` asset, a different signer, a wrong identifier, an equal or older version.
- **SC-002** While a session is active, the button starts no download.
- **SC-003** A QA run from a 0.3 candidate to a newer candidate, with the release feed set to a local fixture, installs, restarts, keeps the helper and leaves the backup.

## Reuse

`UpdateController` (phases and safety), `GitHubReleaseDriver` (the releases API and version order), `UpdateSafetyContext` (blocking reasons), `HelperInstaller` and `HelperController` (helper state and the reinstall path), and the Updates view (the button).

## Out of scope

Delta updates, a download without a click, a silent install, Sparkle, Intel Macs, and an in-app rollback.

## Verification (2026-11-18)

- Unit tests: `UpdatePackageTests` (5) and `UpdateInstallTests` (6), plus the updated update-check tests. The full CamLidCore run passes: 293, 403 and 68 tests, with no failures.
- End to end, once (`UpdateInstallE2ETests`, opt-in with `CAMLID_E2E_UPDATE=1`): a release-signed build labelled 0.1.0 found the real 0.2.0 release, downloaded it from GitHub, checked its SHA-256 and its signature against the release certificate (`f13e5527…`), and replaced itself after its process quit. It then started 0.2.0 with the QA folder as its argument, and the 0.1.0 app was kept in the QA backup folder. The relaunched app kept running; the screen was not checked for a Gatekeeper prompt.
- Not verified: pressing the Update button and its confirmation (the menu-bar item is not reachable by the automation used here, so the view is checked by its build and by reading the code); an update that bundles a newer helper (helper version 1 is unchanged from 0.1).

## Before release

Done: ADR 0004 and spec 021 amended; the privacy text (FR-007) in README and SECURITY.md.

Decided by the owner (2026-11-18): the admin-install gap in SECURITY.md under "Known limits" is accepted for 0.3, with no code change. The helper's installer runs CamLid's own binary as root before that binary's signature is checked. The release notes for 0.3 keep it as a known limit.

Open:
- Release notes for 0.3: in the `scripts/release.sh` template (2026-11-19). The version bump to 0.3.0 happens at release time.

## Verification (2026-11-19)

- A session that starts while an update downloads is no longer ended by the restart. The install is cancelled with the reason "sessionNotAgreed", and the user checks for updates and clicks Update again to agree (`SessionConsentTests`, `UpdateInstallTests`).
- `camlid status` reports `updates.installationAvailable` from the installer (`canInstall`). It was a constant `false`.
- The update window states render in light and dark (`UpdatesRenderTests`, opt-in).
- Still open: the SC-003 QA run with a local fixture feed; the FR-006 case of a bundled newer helper; a live click through the Update button and its confirmation.

