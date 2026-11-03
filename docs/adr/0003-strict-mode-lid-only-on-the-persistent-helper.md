# ADR 0003: Strict mode is lid-only sleep control run by the persistent helper

- **Status:** Accepted (owner decision, 2026-10-31)
- **Amends:** [ADR 0001](0001-persistent-helper-and-strict-experimental-mode.md) decision 2 (Strict frozen with
  exclusive-create / one-use admission)
- **Affects:** spec 014 (persistent helper), specs 012/013 (Strict history); new spec for Strict (planned)

## Context
ADR 0001 kept Strict as an experimental mode, frozen until an admission mechanism existed for its exclusive-create
and one-use rules. None exists without Apple-side registration, so Strict has never run.

Strict's power mechanism is separate from its admission rules. It disables only lid-close sleep through the
root-domain selector `kPMSetClamshellSleepState` (12) and covers idle sleep with a `PreventUserIdleSystemSleep`
assertion that has an OS timeout. On 2026-10-31 the owner chose to research the mechanism on its own, reusing the
helper Standard already installs once. Attended experiments on Mac17,3 / macOS 26A434 (kernel xnu-13432; details in
the local research note `docs/research/strict-lid-mechanism-2026-10-31.md`) found:

| | Result |
|---|---|
| E1 | Selector 12 succeeds from an unprivileged process. There is no read-back: `AppleClamshellCausesSleep` does not follow the bit. |
| E2 | With the bit and the idle assertion, the Mac stayed awake 80 s with the lid closed; `SleepDisabled` untouched. |
| E3 | Clearing the bit with the lid closed slept the Mac within 6 s (`Clamshell Sleep`), with no sleep request. |
| E4 | The bit outlives the process that set it (SIGKILL). Another process cleared it and the closed Mac slept within 5 s. |
| E6 | A restart clears the bit: after reboot a closed lid slept the Mac at once. |
| E5 | Not run. From source, powerd writes the same shared bit and clears it when its own reason ends (display hot-plug, first update after a dark wake). |

Compared with Standard (`pmset disablesleep`): Strict leaves Apple menu › Sleep and idle sleep working, survives no
restart, and sleeps the Mac by itself when cleared with the lid closed. It is weaker in three ways: no read-back, a
shared bit powerd may clear, and an undocumented interface that a macOS update may change.

## Decision
1. **Strict uses the persistent helper.** The helper installed once by Standard's install also serves Strict. The
   exclusive-create, no-adoption and one-use admission requirements are dropped for Strict, as ADR 0001 dropped them
   for Standard. There is no separate install, daemon, label or approval per session.
2. **The helper owns the bit.** Although the selector works unprivileged, only the helper sets and clears it, so one
   process holds the lease, the journal and the recovery path. The app never calls the selector.
3. **Mechanism per session.** A lease names its mechanism (Standard or Strict). The helper holds at most one lease,
   so the two modes never hold at once. The journal records the mechanism of every enable.
4. **Recovery.** When a Strict lease ends (release, expiry, client death, guard trip, helper stop), the helper clears
   the bit and releases the idle assertion. The recovery job clears the bit for an orphaned Strict record. Because
   there is no read-back, clearing is unconditional and idempotent, and "verified" means the call succeeded, not a
   read-back. A restart needs no recovery for the bit.
5. **Re-assertion.** Each lease renewal (every 10 s) sets the bit again, so a clear by powerd while the lid is open
   heals within one renewal. A clear while the lid is closed sleeps the Mac; CamLid reports that the session was
   interrupted by the system rather than ending silently.
6. **Guards.** AC power only; no external display at start; the battery, thermal, CPU, lease and session caps of
   Standard. A session starts only with the lid open (as for Standard).
7. **Support rows per mechanism.** Strict is offered only on a qualified row for Strict, kept separate from Standard's
   rows. Mac17,3 / 26A434 qualifies on E1–E4 and E6, with E5 recorded as not run. Untested Macs cannot accept Strict
   as an untested configuration (unlike Standard, ADR 0001 amendment), because the interface is undocumented.
8. **Experimental and opt-in.** Standard stays the default. Strict is chosen in Settings › Safety, labelled
   experimental, with text that names its limits (may be interrupted by the system, undocumented interface).
9. **History kept.** The frozen `--lid-specific-v1` code, its storage `CamLidPowerHelperLidSpecific` and all QA
   evidence stay untouched. The new spec decides whether to reuse `LidSpecificMechanism` or replace it; either way
   the old single-episode admission path is not the product path.

## Consequences
**Positive**
- A closed-lid mode that changes no persistent setting: a crash, hang or lost power can at worst leave the Mac
  unable to sleep on lid close until the recovery job clears the bit or the Mac restarts.
- Ending a session with the lid closed sleeps the Mac through the kernel's own clamshell path.
- No new install or trust boundary; the existing XPC identity pinning, journal and recovery job are reused.

**Negative / risks**
- An undocumented selector: a macOS update may change or remove it. Mitigated by per-row qualification; an update
  removes the row match and Strict becomes unavailable.
- No read-back: the helper cannot prove the bit is set. A silent failure shows up as the Mac sleeping on lid close,
  which fails safe.
- Shared bit: powerd may clear it (E5 not run), interrupting work; clearing it can also remove powerd's own reason
  until powerd's next transition (the kernel checks external-display desktop mode separately, so a docked Mac does
  not sleep because of this).
- More helper code and a second mechanism to keep tested.

## Not decided here
This ADR grants no authority to install, run root code or change power state. Each attended trial still needs the
owner's go-ahead at the time. Implementation follows a new spec and its tasks; E5 becomes a post-release
observation unless the spec makes it a gate.

## Amendment (2026-11-01): battery sessions
Owner decision: decision 6 no longer requires AC power for either mode. When the user allows battery sessions
(Settings › Closed Lid: "Allow on battery"; Settings was reorganised on 2026-11-01 and the two switches became one), the app names the battery stop level in the
acquire request and the helper holds on battery while the battery stays at or above it (10–50%), stopping by itself
below it. Without that request the helper still requires the charger. The app keeps the battery entry level and the
battery session limit.

## Outcome (2026-11-03): attended trials of the implementation
Strict was implemented per [spec 016](../../specs/016-strict-lid-only/spec.md) and tried on Mac17,3 / macOS 26A434
(trials S1–S4, owner attended; details and timestamps in the spec's tasks). The decisions above stand; nothing in the
results called for changing them.

| Trial | Result |
|---|---|
| S1 Auto with Claude Code, lid closed, on battery (48%) | Held with the lid closed, `SleepDisabled` 0 throughout, released after "Sleep when done", the kernel slept the Mac 5 s later (`Clamshell Sleep`). |
| S2 app killed (SIGKILL) with the lid closed | Helper saw the disconnect and cleared the bit within 1 s; the Mac slept 5 s later. |
| S3 helper killed (SIGKILL) with the lid closed, on battery (78%) | launchd restarted the helper within about 1 s; it cleared the bit as `helperRestart`; the Mac slept 5 s later. |
| S4 restart during a session, on battery | The dying helper could not clear the bit (IOKit was going away) and ended `recoveryRequired`; the restart cleared the kernel bit anyway and the new helper acknowledged the previous boot's record as restored. Nothing to clear by hand. |

Consequences confirmed or revised by the trials:
- **Recovery without read-back works as designed.** Every ending, clean or not, ended with the Mac asleep through the
  kernel's own clamshell path, and the helper never needed its own sleep request for Strict.
- **Shutdown is the one place a Strict restore fails.** The restore returns `backend` while IOKit shuts down. It is
  harmless because the bit lives in kernel memory and a restart clears it; it is the reason a record from another
  boot is acknowledged without a write.
- **The recovery job's Strict branch was not exercised.** In S3 launchd brought the helper back before the job's
  15 s interval, so the helper's own restart did the clearing. That branch is covered by unit tests only.
- **Battery:** Strict on battery passed in S1, S3 and S4. Standard on battery with the lid closed, and a session ending
  at the battery stop level, were not tried.
- **E5 (powerd interference) is still not run** and remains a post-release observation. No trial saw powerd clear the
  bit during a hold (the longest was about 4.5 minutes with the lid closed).
- **Support row:** Mac17,3 / 26A434 stays the only Strict row; it now rests on E1–E4, E6 and S1–S4.
- Trials also found two defects outside the mechanism, both fixed: a single CPU burst made an idle agent read as
  working (spec 015), and a plugin's headless `claude` process was counted as an agent.
