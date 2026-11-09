# Feature Specification: Automatic update setting

**Status:** Planned for the release after 0.1.0. Not in 0.1.0. Shipping it requires an amendment to
[ADR 0004](../../docs/adr/0004-distribution-through-github-releases.md) first, because that decision says the check runs
only when clicked.

## Context (0.1.0)

- CamLid looks for a new release only when you click *Check for Updates…*. That asks GitHub's public releases API for
  the newest releases and offers to open the Releases page. It never downloads or installs anything (ADR 0004,
  decision 4).
- The README and SECURITY.md promise that this is the only network request CamLid makes, and that you start it.
- The helper is pinned to the release certificate. An app update signed with the same certificate keeps the helper
  working. A helper change needs an administrator reinstall ([spec 014](../014-persistent-helper/spec.md); the version
  guard is `scripts/check-helper-version.sh`).

## Goal

Let the owner choose whether CamLid looks for new releases on its own. The default is never, so the promise above holds
for everyone who does not turn the setting on.

## Modes

| Mode | Behaviour | Network requests |
|---|---|---|
| Off (default) | Only *Check for Updates…*, as in 0.1.0. | Only when you click. |
| Check | CamLid asks the same GitHub endpoint about once a day while it runs. A newer release shows "Update available" in the Updates window, with the Releases link. It never downloads or installs. | At most one per day. |
| Install | Not in this spec (see Out of scope). | — |

## User stories

1. **Keep the current behaviour.** As someone who does not want background network traffic, I leave the setting Off.
   - Off makes no request at launch, on a timer, after wake, or on any other trigger. Only *Check for Updates…* does.
2. **Hear about a new release.** I choose Check.
   - At most one request per day. A newer release appears in the Updates window with the Releases link.
   - Offline, nothing is shown outside the Updates window.
   - Switching back to Off stops scheduled checks at once.
3. **Not disturbed while the Mac is held awake.** Check does not run during a session or a sleep hold. It waits and
   tries again later.

## Requirements

- **FR-001** The setting has two values, Off and Check. Off is the default for new installs and for upgrades. An upgrade
  never turns Check on.
- **FR-002** Check uses the same request as the manual check: the same endpoint, no cookies, no account, and an
  ephemeral session.
- **FR-003** Check runs at most once per 24 hours, and not while a session or hold is active.
- **FR-004** Check never downloads a file and never changes the app or the helper.
- **FR-005** The setting is in Settings › General, with a plain description of the request it makes. It persists across
  restarts.
- **FR-006** When this ships, the Privacy section of the README and SECURITY.md name the setting and the one daily
  request that Check makes.

## Success criteria

- **SC-001** With the setting Off, a test shows no request except the manual check.
- **SC-002** With Check on, a test shows at most one request per 24 hours, and none while a session is active.
- **SC-003** Switching to Off stops scheduled checks immediately.

## Prerequisites

- An accepted amendment to ADR 0004 (decision 4 and its consequences) that allows one daily check. Without it this spec
  cannot ship.
- Owner review of the privacy wording.

## Out of scope

- **Install mode.** ADR 0004 excludes an in-app updater until the owner has a Developer ID (see
  [spec 020](../020-v1-gates/spec.md), gate G1). Installing also has to handle helper reinstalls. The admin-install gap
  in SECURITY.md under "Known limits" must be closed before that.
- Beta or pre-release channels.
- Notifications outside the Updates window and Settings.

## Open decisions (owner)

1. **Amend ADR 0004 to allow a daily check?** Proposed: yes, Check only. It sends one request a day, and the owner can
   turn it off.
2. **Interval.** Proposed: once a day. The alternative is once a week.
3. **Install mode.** Proposed: not in the next version. Decide after the Developer ID question (spec 020, gate G1).
