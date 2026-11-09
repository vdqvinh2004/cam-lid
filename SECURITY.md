# Security policy

CamLid installs a small **root helper** (a LaunchDaemon) that changes the Mac's sleep settings, so a flaw in it matters
more than in an ordinary menu bar app. Please report problems privately.

## Reporting a vulnerability
Use either private channel:
- GitHub's private vulnerability reporting: **Security › Report a vulnerability** on the repository
  (<https://github.com/vdqvinh2004/cam-lid/security/advisories/new>).
- Email to vdqvinh2004@gmail.com.

Please do not open a public issue for a security problem. Include the version, what you did, and what happened. This is a one-person project: expect a first answer
within about a week.

## What is in scope
- The helper accepting a caller it should refuse. It is meant to obey only an app signed with the project's release
  certificate under the identifier `com.camlid.CamLid`, or, for an ad-hoc local build, only the exact code hashes it
  was installed with.
- A way to leave the sleep setting changed after a session, an app crash, a helper crash or a restart.
- The installer or uninstaller doing more than its fixed operations, or touching files it should not.
- Anything that makes the app send data off the Mac (it should not; the only request is the update check, which you click or, if you turn it on, once a day).

## What the helper is meant to guarantee
It accepts a fixed set of operations (inspect, acquire, renew, release) from the pinned app only; it holds a 30-second
lease that the app renews every 10 seconds and restores the sleep setting when the lease lapses; an independent
recovery job restores it if the helper itself is gone; and a restart clears the Strict mechanism. The design is in
[ADR 0001](docs/adr/0001-persistent-helper-and-strict-experimental-mode.md) and
[ADR 0003](docs/adr/0003-strict-mode-lid-only-on-the-persistent-helper.md); the trials that tested it are in
[specs/014-persistent-helper/g2-trial.md](specs/014-persistent-helper/g2-trial.md).

## Known limits
- Installing or reinstalling the helper asks for your administrator password, then runs CamLid's own binary as root.
  That binary is not checked against its signature at that moment. A program running as your user that changes
  `CamLid.app` before you approve can therefore have its code run as root. Before you install or reinstall the helper,
  check the app with `codesign --verify --deep --strict /Applications/CamLid.app` and compare its certificate with the
  one in the release notes (`codesign -d -r- /Applications/CamLid.app`).
- The helper trusts only the certificate it was installed with. An ad hoc build is trusted by its exact code hash, so
  each rebuild needs a reinstall.
- The local control socket accepts commands from programs running as your user, as designed. It refuses other users.

## Verifying a download
Releases are signed with the project's own certificate, not an Apple Developer ID, and are not notarized. Compare the
SHA-256 of the zip, the certificate fingerprint and the code hashes of the app and helper with the release notes
(commands are in each release), or build it yourself from the tagged commit.

## Supported versions
Only the newest release.
