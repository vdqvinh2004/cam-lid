# Feature Specification: update notice and closed-lid helper onboarding (v0.3)

**Status:** Released in 0.3.0 beta on 2026-11-23. Open: whether the daily update check is on by default for new installs (see D4).

## Goal

A newer release shows on the Dashboard, and one click opens the Updates window with the install button (spec 026). The closed-lid option cannot leave the Mac unprotected without the helper, and the next step is always one click away.

## Before this change (read in the code, 2026-11-18)

- Without the helper, the Dashboard showed "Can’t keep your Mac awake · helper not installed" with "Install Helper…" as a small link.
- The Settings toggle "Keep awake with the lid closed" could be turned on without the helper. A session still started. Closing the lid was not protected by the helper, and the only signal was a note inside the session.
- With the helper installed and the option off, the Dashboard offered only "Open Closed Lid Settings…", not a direct way to turn it on.

## Decisions

- **D1.** While the option is off and the helper is not ready, the toggle is disabled. A one-line hint below it says what to install or reinstall. An option that is already on can always be switched off.
- **D2.** When the helper is ready and the option is off, Settings shows "Turn On" under the toggle, and the Dashboard offers "Turn On" in the same place as the other fixes. Both use the same validated settings write as the toggle.
- **D3.** A newer release shows on the Dashboard as "CamLid X is available". The link opens the Updates window, where "Update to X" installs it (spec 026).
- **D4.** The existing daily check (spec 021) runs a due check soon after launch, or after it is turned on, instead of an hour later. **Open:** the setting is still off by default for new installs, as spec 021 decided. Turning it on by default changes a privacy default, so the owner decides.

## Requirements

- **FR-001** `ClosedLidOffer` is the one rule for the Dashboard and Settings, so they cannot disagree.
- **FR-002** A session may still start with the option on and no helper, because the lid-open hold works without it. The session then says that closing the lid sleeps the Mac until the helper is installed.
- **FR-003** "Turn On" from the Dashboard is refused, with the same message as the toggle, when the write fails.
- **FR-004** The update notice appears only while the last check found a newer release. A deferred or failed check shows nothing.

## Not verified

- A visual check of the Dashboard notice and the disabled toggle in the running app. The menu-bar item is not reachable by the automation used here.
- That closing the lid sleeps the Mac in the FR-002 case. The code path was read, not tested with the lid closed.
