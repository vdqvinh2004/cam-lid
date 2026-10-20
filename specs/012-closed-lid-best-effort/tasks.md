# Tasks: Closed-Lid Best-Effort Mode

**Feature context:** `012-closed-lid-best-effort`
**Status:** Phase 0 offline complete (2026-10-19). The model, readiness projection, consent,
presentation and JSON contract are implemented with fake-only tests (51 tests in the package
pass). Native tasks below still require their own one-use approvals.
**Source:** [spec.md](spec.md), [plan.md](plan.md), [decision memo](../../docs/planning/closed-lid-product-path-2026-10-19.md).

## Phase 0 — Offline (no power, no service, no protected-path writes)

- [x] **T001 — Audit the clear/suppression path.**
  Read `LidSpecificMechanism`, `LeasePowerMechanism`, `PowerLeaseService.restore()`, the
  native selector binding and the v8/v9 receipts. Document what the selector does with
  `enabled: true/false`, what a successful clear receipt looks like, and whether any code path
  could explain the observed `AppleClamshellCausesSleep = No` after cleanup. Output: a short
  findings note appended to the plan or a new `docs/qa/` note. *Done when:* the R0 design has
  a named hypothesis and the exact receipt fields to capture.

- [x] **T002 — State model types.**
  Add `BestEffortSessionState` and `BestEffortClearEvidence` (working names) with unit tests
  covering every transition. No changes to `RestoreState`. *Done when:* exhaustive
  transition tests pass, including unknown clear/crash paths.

- [x] **T003 — Readiness projection.**
  Add the best-effort facts/projection with stable reason codes. Assert
  `ProtectionEffectiveState.protected` is unreachable for this backend. *Done when:* unit tests
  cover every precondition and the unreachable-protected test passes.

- [x] **T004 — Fake backend and fault injection.**
  Fake acquire/stop transport; inject journal commit failure, clear failure/unknown, release
  failure, lease expiry, app crash, helper crash, AC loss, thermal and foreign override.
  *Done when:* every case maps to a defined state and never silent-ready.
  *Offline result:* the existing `SimulatedLidSession` fakes cover journal/lease/assertion
  failures; the new product model covers clear partial/unknown/not-attempted, crash, sleep,
  boot reconciliation and readiness faults. No new transport abstraction until G3.

- [x] **T005 — Consent model and copy.**
  Versioned consent record, exact risk copy (crash/indefinite override, unverified restoration,
  hidden writers), revocation and re-consent rules. *Done when:* tests enforce consent before
  any start and re-consent on version change.

- [x] **T006 — UI projection and copy.**
  Banner, state labels, disabled reasons and recovery sheet copy; Settings experimental flag.
  No green shield/"Protected". *Done when:* snapshot/state tests cover every state and the
  forbidden-string test passes.

- [x] **T007 — CLI contract.**
  Status fields (mode, state, cap/lease remaining, clear evidence, recovery reason, consent
  version) and start/stop refusals behind the flag. *Done when:* GUI/CLI parity tests pass and
  no `protected`/`verified` key exists for the backend.

- [x] **T008 — Documentation links.**
  Link this spec from the roadmap M1 section, the proposal §7C and the decision memo.
  *Done when:* links resolve and the roadmap states M1 remains blocked until G1/G2/G3.

## Phase 1 — R0 native experiments (one-use approval per boot)

- [x] **T100 — R0 preparation (offline).** Pinned journal resets
  (`reset-r0-clear-episode-journal-qa.py`, `reset-r0-attempt2-clear-episode-journal-qa.py`,
  `reset-r0-attempt3-clear-episode-journal-qa.py`), open-lid session hold
  (`r0-session-hold.py`), post-cleanup observer (`observe-r0-post-cleanup-sleep.py`) and
  [runbook](../../docs/qa/r0-behavioural-clear-runbook-2026-10-19.md).
  *Done when:* self-tests and read-only preflights pass with no native action.
  *Result:* all self-tests pass; attempt #1 and #2 reset preflights passed on their fresh
  boots; each later reset correctly refuses on the consumed previous boot. Nothing actuated
  during preparation.

- [x] **T101 — R0 attempt #1.** Executed on boot `1002AE9A-…` with one-use approval. The v9
  recorder's close cue was missed (its 6 s window), so it aborted after acquire/renew and
  cleaned up (`cleanupAcknowledged/userStop`). The post-cleanup observer then closed the lid:
  `Clamshell Sleep` at 19:08:29, Wake 19:08:55, property `true` before close / `false` after
  wake. Result **`R0_POST_CLEANUP_SLEEP_OBSERVED`** — clear behaviourally effective; property
  stale after wake. Record: [attempt #1](../../docs/qa/r0-behavioural-clear-attempt1-2026-10-19.md).
  *Deviation:* no closed interval during the session (recorder mismatch), not a clear failure.

- [x] **T102 — R0 attempt #2** executed on boot `FD97CCAF-…`: reset the attempt #1 journal
  (`1002AE9A-…` / `2C31C3C6-…`), one open-lid session hold (active 10.42 s, lid open, no
  sleep/wake, exit 5, `cleanupAcknowledged/userStop`), then the observer. The observer's
  strict output was **`R0_POST_CLEANUP_NO_SLEEP`**, but the raw pmset log shows
  `Entering DarkWake state due to 'Clamshell Sleep'` at 19:32:41, `Display is turned off`,
  and a full wake at 19:33:22 on lid open. This is a **false negative** in the observer's
  classifier, not a suppression event. Record:
  [attempt #2 adjudication](../../docs/qa/r0-attempt2-adjudication-2026-10-19.md).
  *Deviation:* observer counted only `Entering Sleep state`; fixed to count clamshell
  DarkWake and store raw pmset lines; self-test passes.

- [x] **T103 — R0 adjudication and go/no-go.** Attempt #3 executed on boot `A9BC665D-…`:
  reset the attempt #2 journal; session hold clean (10.54 s, `cleanupAcknowledged/userStop`);
  observer retry #1 timed out at the Continue dialog; retry #2 closed the lid and the Mac
  produced a full `Clamshell Sleep` at 22:11:13 (display off 22:11:08), but the operator
  missed the spoken “Open now” cue and the observer wrote no `result.json`. Raw evidence is
  **`R0_POST_CLEANUP_SLEEP_OBSERVED` (full)**. Three-boot record: #1 full sleep, #2 clamshell
  DarkWake, #3 full sleep (raw). The owner accepted the raw #3 evidence on 2026-10-20; R0 is
  met for behavioural same-boot clear effectiveness. The observer's open cue is fixed to a
  visible dialog (self-test passes). No further native action on this boot; reboot. G2/G3
  still need separate approvals; M1 remains BLOCKED. Record:
  [attempt #3 adjudication](../../docs/qa/r0-attempt3-adjudication-2026-10-20.md) and
  [owner acceptance](../../docs/qa/r0-owner-acceptance-2026-10-20.md).
  *Done when:* the memo records the decision and the roadmap reflects it.

## Phase 2 — G2 native qualification (separate approvals per episode/boot)

- [ ] **T201 — Full system Sleep repeats** (proposed ≥3 across ≥2 boots): clean termination,
  zero unexplained darkwakes, operator attestation. Failure rejects the backend.
- [ ] **T202 — Sustained closed-lid sessions** with independent progress and honest display
  scope.
- [ ] **T203 — Failure classes:** app crash, helper crash/hang, journal corruption/permission,
  AC loss, thermal, foreign override, manual Sleep, reboot with pending journal.
- [ ] **T204 — Hardware rows:** target MacBook Air first; additional rows only if shipping
  scope expands.

## Phase 3 — G3 app integration (separate approval)

- [ ] **T301 — Wire the best-effort projection behind the experimental flag** without changing
  the shipping backend or the `protected` state.
- [ ] **T302 — Consent, banner and recovery UX** in the app.
- [ ] **T303 — CLI parity** and refusal reason codes.
- [ ] **T304 — Regression + M6:** existing suites, Debug/Release builds, UI/accessibility,
  CLI integration, M6 evidence pack.

## Phase 4 — G4 release gates (separate)

- [ ] **T401 — M5** signing/notarisation/SMAppService install/remove/update.
- [ ] **T402 — M7** supervised real users after M6 PASS.

## Blocked / explicitly out of scope

Auto, Timed, battery, background/login start, completion sleep, bag/sleeve use, verified
restoration, `Protected` state, shipping-gate change, Intel/multi-display rows. Any native
action, root install, app integration or entitlement change requires a new explicit approval.
