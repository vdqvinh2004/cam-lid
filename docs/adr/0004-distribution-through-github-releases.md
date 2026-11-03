# ADR 0004: Distribution through GitHub releases, ad-hoc signed, no notarization, no in-app updater

- **Status:** Accepted (owner decision, 2026-11-03)
- **Affects:** README, `scripts/release.sh`, the Updates window; supersedes the signed-beta plan (spec 006, M5–M7)
- **Builds on:** [ADR 0001](0001-persistent-helper-and-strict-experimental-mode.md) (no Apple-side registration)

## Context
CamLid is open source (MIT). The owner will not publish through the App Store and has no Apple Developer account, so
there is no Developer ID certificate and no notarization. Users download a release from GitHub. Three facts shape the
release:

1. A downloaded, ad-hoc signed app is quarantined and Gatekeeper rejects it until the user approves it (*Open Anyway*
   or `xattr -dr com.apple.quarantine`). That friction cannot be removed without Apple's certificate.
2. The root helper pins the code hash (CDHash) of the exact app and helper it was installed with. A released zip is
   therefore self-consistent: the pin is made on the user's Mac at install time. It also means every update needs the
   helper reinstalled (one administrator prompt), which the app already offers.
3. The previous updater (Sparkle) could not be used: it needs a Developer ID to be eligible, its framework failed a
   deep signature check inside an ad-hoc bundle (`codesign --verify --deep --strict`), which would make a downloaded
   copy read as "damaged" (not bypassable) instead of "unidentified developer" (bypassable), and it forced a
   library-validation exception on the app.

## Decision
1. **Releases are zips on GitHub Releases**, built on the owner's Mac by `scripts/release.sh` (the project needs
   Xcode 27) and uploaded deliberately. Early versions are marked pre-release. Apple silicon, macOS 14 or later.
2. **Ad-hoc signed, hardened runtime, no entitlements, no nested code.** The script fails the build unless
   `codesign --verify --deep --strict` passes before and after the zip, the app is arm64 only, carries no entitlements
   or frameworks, and its version matches. A Debug build keeps the library-validation exception for Xcode's debug dylib.
3. **Trust comes from verification, not from a vendor:** each release note lists the zip's SHA-256 and the CDHash of the
   app and of the helper, the source is public, and anyone can build the same thing.
4. **Sparkle is removed.** *Check for Updates…* asks GitHub's public releases API (pre-releases included) only when
   clicked, compares versions, and offers to open the Releases page. The app never downloads or installs an update.
5. **Open source hygiene:** SECURITY.md (a root helper deserves a reporting path), CONTRIBUTING.md (including how to
   qualify another Mac), the MIT licence, and a note that bundled agent marks stay with their owners.

## Consequences
- Users see a one-time Gatekeeper prompt and update by hand. The README and every release note say so up front.
- No Apple dependency, no certificate to guard, no appcast, no update signing key.
- Smaller app (the 19 MB Sparkle framework is gone) and less code running as the user.
- There is no notarization scan: the SHA-256 and CDHash checks, and the public source, are the only assurance. A build
  from a modified source has a different CDHash and is not accepted by a helper installed from another build.
- If the owner later obtains a Developer ID, notarization and an in-app updater can be added without changing the helper
  pinning model.

## Not decided here
Intel Macs (the support rows are Apple silicon), a Homebrew cask, and CI builds (a GitHub runner with Xcode 27 is
needed first). The `camlid` command-line tool ships inside the app bundle (Contents/Helpers/camlid), sealed by the
app's signature.
