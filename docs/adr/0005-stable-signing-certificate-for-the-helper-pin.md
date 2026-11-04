# ADR 0005: A stable signing certificate for the helper pin, and a helper version

- **Status:** Accepted in principle (owner direction, 2026-11-04); the release certificate is created by the owner
- **Affects:** `LocalIdentityPins`, `PowerHelperIdentity`, `HelperInstaller`, `scripts/embed-helper.sh`,
  `scripts/release.sh`, `scripts/make-signing-identity.sh`, README, the Updates window
- **Builds on:** [ADR 0001](0001-persistent-helper-and-strict-experimental-mode.md) (no UID-only trust, no Apple
  account), [ADR 0004](0004-distribution-through-github-releases.md) (ad-hoc releases)

## Context
Releases were signed ad hoc, and the helper pinned the exact CDHash of the app and of itself. An ad-hoc signature names
no identity, so every build has a new CDHash and every app update needed **Reinstall helper…** (an administrator
password) even when the helper had not changed. The owner wants a reinstall only when the helper changes.

Identifier-only trust is not an option: any local program can be ad-hoc signed with the identifier
`com.camlid.CamLid`. A paid Developer ID (Team ID) is excluded by ADR 0001.

## Decision
1. **Sign releases with one project-owned self-signed code-signing certificate.** App, helper and command-line tool use
   the same certificate (`CAMLID_SIGN_IDENTITY`, created once by `scripts/make-signing-identity.sh`).
2. **Pins version 2.** When app and helper share a leaf certificate, the installer writes
   `{version: 2, signerLeaf: <SHA-1>, helperVersion: N}`. Each side then requires its peer to satisfy
   `identifier "<id>" and certificate leaf = H"<signerLeaf>"` plus the existing no-`get-task-allow` rule. Ad-hoc builds
   still write version 1 (exact CDHashes), and existing version 1 installs keep working until they are reinstalled.
3. **`PowerHelperVersion.current`.** Bump it whenever the helper's behavior changes. The pins record the version
   installed. An app that ships a higher one reports `needsHelperUpdate` and asks for a reinstall; the same version asks
   for nothing, even though the rebuilt helper binary differs byte for byte.
4. **Reinstall is still required** for the first install, when the helper version rises, when the signing certificate
   changes, and for any ad-hoc rebuild. It always needs the administrator password.

## Verified (2026-11-04, throwaway certificate)
- `codesign` signs only with a certificate trusted for code signing, so the signing machine needs that trust.
- A Mac that only *runs* the app needs none: `certificate leaf = H"…"` is satisfied by `codesign --verify -R` with the
  trust removed and the signing keychain deleted.
- An ad-hoc program with the same identifier fails the requirement; the helper's requirement does not accept the app's
  identifier and vice versa.
- The release build verifies that app, helper and tool share one certificate (`scripts/release.sh`).

## Consequences
- **The private key is the root of trust.** Whoever holds it can sign an app the helper obeys. Keep the `.p12` and its
  password outside the repo; losing it means a new certificate and one reinstall for every user.
- **Forgetting to bump `PowerHelperVersion`** after a helper change would leave the old helper installed without
  warning. Treat the bump as part of any change under `Packages/CamLidPowerHelper`.
- Someone who builds from source keeps ad-hoc pins and a reinstall after every rebuild, or signs with their own
  certificate and pins that one.
- Gatekeeper behavior is unchanged: the app is still not notarized and needs *Open Anyway* on first launch.
- Not decided here: rotating the certificate, and a CI-held key.
