# Tasks: Strict mode, lid-only

**Feature context:** `016-strict-lid-only` · **Status:** 9/15 checked. Sources: [spec.md](spec.md), [plan.md](plan.md).

## Phase 0 — Decision
- [x] T001 ADR 0003 accepted; ADR 0001 amended. — `85bae08`.

## Phase 1 — Helper
- [x] T101 `PowerRequest.mechanism` (optional, default `standard`) with wire round-trip tests, old-client decode test. — `PowerRequest.Mechanism` (`standard` | `strict`); round-trip, old-client and unknown-value tests.
- [x] T102 `ClamshellBitMechanism` with an injected native interface; tests: apply order (assertion then bit), renewal re-sets the bit and extends the assertion, clear is idempotent, failed apply discards both, `readApplied` nil. — `ClamshellBitMechanism.swift` (`ClamshellBitCalls.native`), 5 tests with fake calls.
- [x] T103 `PowerLeaseService` selects the mechanism per acquire; one lease across mechanisms; journal family prefix; tests for each mechanism and for refusing a second lease. — `strict:` init parameter, `mechanism(for:)` by owner-identity prefix (`clamshell-bit-v1:`), new protocol properties `restartClearsPolicy` and `acknowledgedClearIsRestore`; `StrictLeaseTests`.
- [x] T104 Recovery job and boot handling by family: orphaned Strict record → clear bit; previous-boot Strict record → acknowledged without a write. Tests. — Same-boot helper restart also clears the bit; the recovery job and uninstall get the Strict mechanism in `main.swift`.
- [x] T105 Interruption: system sleep observed during a Strict lease ends it with `systemSleptWhileHeld`; no own sleep request after a Strict restore. Tests. — `observeSystemSleep()`; the Standard daemon now runs the passive root-domain observer (Standard leases ignore it). The observer has not been exercised physically in Standard mode.

## Phase 2 — App
- [x] T201 `PowerMode.strict` availability (helper installed, Strict row, AC), remove `helperArgument`/reinstall switching; `QualifiedSupportRows` per mechanism with row `mac17-3-26a434` for Strict; tests. — `Configuration.powerMode` (older files mean Standard), `QualifiedSupportRows.strictRows`, `closedLidAllowed`; a switch is refused while a session or hold exists and to Strict without a Strict row (`PowerModeSwitch`). AC is enforced by the helper.
- [x] T202 Reconciler sends the mechanism; Strict admission reasons (battery, external display, lid closed) and `systemSleptWhileHeld` text; tests. — `HoldAction.acquire(sessionSeconds:strict:)`; the helper answers the first renewal after an interruption with `systemSleptWhileHeld`; texts for it and `mechanismUnavailable`. Battery/display/lid reasons reuse `safetyRefused`.
- [x] T203 Settings › Safety Strict choice and disclosure; Dashboard shows the mode. Build, run and inspect the app (light/dark, keyboard, VoiceOver labels). — "Closed-lid mode" pop-up (Strict selectable only with a Strict row), per-mode disclosure and Testing row; the Dashboard line reads "Closed lid ready · Strict (experimental)". Inspected in the running app (dark appearance, VoiceOver labels); light appearance and keyboard order not checked.

## Phase 3 — Attended trials (owner go-ahead each time)
- [ ] T301 Strict trial S1: Auto with Claude Code, lid closed, Sleep when done (as trial 8); `SleepDisabled` stays 0; Mac sleeps at the end.
- [ ] T302 S2: app kill during a Strict session with the lid closed; helper clears the bit; Mac sleeps.
- [ ] T303 S3: helper kill during a Strict session; recovery job clears the bit.
- [ ] T304 S4: restart during a Strict session; nothing to recover after boot.
- [ ] T305 E5 observation (optional): display plug/unplug and a 15-minute hold; record whether powerd clears the bit.

## Phase 4 — Close
- [ ] T401 Record results, update ADR 0003 consequences if trials change them, update spec 014 cross-references.
