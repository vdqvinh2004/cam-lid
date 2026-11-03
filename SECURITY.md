# Security policy

CamLid installs a small **root helper** (a LaunchDaemon) that changes the Mac's sleep settings, so a flaw in it matters
more than in an ordinary menu bar app. Please report problems privately.

## Reporting a vulnerability
Use GitHub's private vulnerability reporting: **Security › Report a vulnerability** on the repository
(<https://github.com/vdqvinh2004/cam-lid/security/advisories/new>). Please do not open a public issue for a security
problem. Include the version, what you did, and what happened. This is a one-person project: expect a first answer
within about a week.

## What is in scope
- The helper accepting a caller it should refuse (it is meant to obey only the exact app code hash it was installed with).
- A way to leave the sleep setting changed after a session, an app crash, a helper crash or a restart.
- The installer or uninstaller doing more than its fixed operations, or touching files it should not.
- Anything that makes the app send data off the Mac (it should not; the only request is the update check you click).

## What the helper is meant to guarantee
It accepts a fixed set of operations (inspect, acquire, renew, release) from the pinned app only; it holds a 30-second
lease that the app renews every 10 seconds and restores the sleep setting when the lease lapses; an independent
recovery job restores it if the helper itself is gone; and a restart clears the Strict mechanism. The design is in
[ADR 0001](docs/adr/0001-persistent-helper-and-strict-experimental-mode.md) and
[ADR 0003](docs/adr/0003-strict-mode-lid-only-on-the-persistent-helper.md); the trials that tested it are in
[specs/014-persistent-helper/g2-trial.md](specs/014-persistent-helper/g2-trial.md).

## Verifying a download
Releases are ad-hoc signed, not notarized. Compare the SHA-256 of the zip and the code hashes of the app and helper
with the release notes (commands are in each release), or build it yourself from the tagged commit.

## Supported versions
Only the newest release.
