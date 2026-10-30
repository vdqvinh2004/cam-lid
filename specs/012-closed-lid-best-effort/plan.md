# Implementation Plan: Closed-Lid Best-Effort Mode (experimental product track)

> **SUPERSEDED for product deployment (2026-10-30):** the exclusive-create / no-adoption / one-use admission requirements in this document are replaced by the persistent-helper model of [spec 014](../014-persistent-helper/spec.md) and [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md). The mechanism described here remains as the experimental **Strict** mode, frozen. Evidence and dated records below are kept as history; per-episode approval is now an owner QA discipline, not a product requirement. No gate passed by this change.


**Feature context:** `012-closed-lid-best-effort`
**Status:** Design only. Offline work may proceed; R0 and every native/integration step need
separate approvals. See [decision memo](../../docs/planning/closed-lid-product-path-2026-10-19.md).
**Scope source:** [spec.md](spec.md); [proposal](../../docs/planning/closed-lid-best-effort-proposal-2026-10-18.md) §5/§7C.

## 1. Technical context

- The shipping model requires verified restoration:
  `RestoreState` (`pending/verified/failed/conflict/unknown`), `PowerController.restorationRequired`,
  `PowerBackend.verifyRestoration()`, and `ProtectionEffectiveState.protected` gated on
  `backendVerified`/`leaseVerified` facts.
- The best-effort lab backend can only produce `cleanupAcknowledged`: the helper's clear
  returns `callsAcknowledgedOnly`, and `LidControlReceipt.restorationVerified` is hard-coded
  `false` because the shared selector has no trustworthy getter
  (`LidSpecificMechanism.swift`).
- The lab's post-cleanup policy read remained `AppleClamshellCausesSleep = No` until the next
  boot. That is the R0 question.
- Existing artifacts: `PowerLeaseService.restore()` (journal intent before clear, one clear),
  `LidSpecificMechanism`, the frozen QA client, the v9 recorders and evidence.

## 2. Design decisions

### D1 — A separate, acknowledgement-aware state axis

Do **not** overload `RestoreState` or `ProtectionEffectiveState`. Introduce a parallel model
(working names):

```swift
public enum BestEffortSessionState: String, Codable, Sendable {
    case off, ready, active, cleanupAcknowledged, recoveryRequired, sleepingTerminated
}

public enum BestEffortClearEvidence: String, Codable, Sendable {
    case none, callsAcknowledgedOnly, unknown
}
```

Rules:

- `verified` is unrepresentable for this backend.
- `cleanupAcknowledged` is terminal for the session; re-arm requires a fresh start check.
- `recoveryRequired` blocks every new start until reconciliation; no blind reset.
- The shipping `PowerController` and `PowerBackend` are unchanged; the best-effort mode gets
  its own projection and is selected by an explicit mode, not by weakening the shipping path.

### D2 — Readiness projection

A separate `BestEffortReadinessFacts`/projection with stable refusal codes:
`experimentalFlagOn`, `consent` (versioned), `supportRowQualified`, `helperTrusted`,
`helperAvailable`, `journalReady`, `pendingCurrentBootRecovery`, `currentState`, `rearmAllowed`,
`onAC`, `batteryPercent`, `lidState`, `externalDisplayCount`, `globalSleepDisabled`,
`clamshellCausesSleep`, `baselineWarningAcknowledged`.

`SleepDisabled` true/unknown is a hard refusal. `AppleClamshellCausesSleep` is an **advisory
indicator**: true → no warning; false/unreadable → an explicit baseline acknowledgement is
required (stale publication and a foreign writer cannot be distinguished). It is never a
verified baseline.

Presentation mapping:

| Facts | State |
|---|---|
| flag off / no consent / precondition fail | `Off/Ready` + stable reason |
| all preconditions, no session | `Ready` (warning if baseline unverified) |
| lease held | `Active` (banner: best effort, unverified) |
| clear attempted, calls acknowledged | `Cleanup acknowledged` |
| clear unknown / crash / journal error | `Recovery required` |
| qualified sleep event | `Cleanup acknowledged` or `Recovery required` |

No projection may render `Protected`; a UI test asserts the string is unreachable. The offline
implementation lives in
`Tests/Experiments/BestEffortLidSession/Sources/BestEffortLidSession/BestEffortProductModel.swift`
with `BestEffortProductModelTests.swift` (51 tests in the package pass, including these).

### D3 — Session lifecycle

1. **Start check** (read-only): flag, consent, support row, AC, battery floor, lid open, no
   external display, helper trust/availability, journal ready, `SleepDisabled = false`.
   `AppleClamshellCausesSleep` is an **indicator, not a gate**: `true` → no warning; `false` or
   unreadable → require an explicit "baseline unverified" acknowledgement, because stale
   publication and a foreign writer cannot be distinguished. "No known foreign override" is a
   disclosure, not a provable fact.
2. **Acquire**: exactly one best-effort acquisition (24 s lease, 10 s heartbeat, 900 s cap).
   Mutation only after the journal intent commit, as today.
3. **Active**: owned assertion; renewals; safety checks (AC loss, battery floor, thermal,
   stale sensors, foreign override) stop the session.
4. **Stop/quit/safety**: journal `restoreLidPolicy` intent → one clear → release owned
   assertion → store receipt → `cleanupAcknowledged` (or `recoveryRequired`).
5. **Crash**: lease expiry terminates the session in the helper; next launch reports the real
   state and never auto-re-arms.
6. **Manual Sleep**: never veto; the qualified sleep event terminates the session with no
   resume; the mode's gate requires the full-Sleep qualification.

### D4 — Journal and boot reconciliation (reusability design)

- The helper already runs as root and owns its journal; a product must not require a host-side
  root reset packet per boot.
- **Boot reconciliation (design):** on daemon start, read the journal.
  - acknowledged restore record → archive/mark handled; `ready` (the OS baseline is restored
    at boot; do not claim the clear did it).
  - unknown/pending restore → `recoveryRequired`; keep the record; do not auto-clear.
  - no record → `ready`.
- **Same-boot re-arm:** allowed only after G1/R0 proves the clear **behaviourally** effective.
  If the property republished `true` after a lid cycle, normal start checks apply. If it stays
  stale `false`, re-arm requires a behavioural lid-cycle proof (the machine slept on the last
  close, recorded from the OS sleep log) or a reboot; the property alone never authorizes
  re-arm. If the last close did not sleep, `recoveryRequired` + reboot guidance.
- The journal remains the write-ahead authority; no guessed resets, no repeat clears to fish
  for a reply.

### D5 — UI/UX

- Experimental flag in Settings (off by default), clearly labelled "Best effort — experimental".
- First-use consent sheet with the three accepted residual risks, versioned; revocation.
- Persistent banner while active: "Best effort. Restoration is not verified. If the app
  crashes, closing the lid may not sleep your Mac until you reboot."
- Stop/recovery sheet: reopen the lid, restart/recover, reboot guidance; no blind reset.
- No green shield, no "Protected", no implication of safety/thermal guarantees.
- Disabled controls when preconditions fail, with the exact reason.

### D6 — CLI

- `status --json` gains best-effort fields: mode, state, cap remaining, lease remaining,
  clear evidence, recovery reason, consent version.
- Start/stop only behind the same flag and consent; refusals match the GUI reason codes.
- CLI tests assert no `protected`/`verified` keys for this backend.

### D7 — Tests (offline first)

- Pure state-machine tests for every transition, including unknown clear, crash, journal
  failure, manual sleep, AC loss, thermal, foreign override and reboot-with-journal.
- Fake transport for the helper; fault injection at journal commit/clear/release points.
- UI projection tests: `Protected` unreachable, banner always present while active, consent
  enforcement.
- CLI/GUI parity tests.
- No test may create an assertion, write a selector or touch protected paths.

## 3. R0 — same-boot clear experiment (native; separate one-use approvals)

**Question:** after a suppression, does the helper's clear call restore **normal lid-close
sleep** without a reboot? The public `AppleClamshellCausesSleep` property is derived policy and
may be stale (T001 audit), so it is a secondary observation, not the criterion.

**Design (per attempt, one per fresh boot):**

1. Fresh-boot, open-lid, AC baseline; read policy, boot, battery, thermal and topology.
2. Approved one-use session acquisition; hold ~10 s; verify the property is `false` while the
   lid stays open.
3. Stop through the normal path; capture the journal disposition and client exit code (the
   exact selector/service/close codes are not persisted; an acknowledged state implies the
   calls returned 0).
4. Sample the property every 2 s for 60 s after cleanup.
5. **Behavioural test:** close the lid for ~10 s. Use the OS sleep log plus operator report to
   decide whether the machine actually slept; wake and reopen.
6. Sample the property again; run one extra close/open cycle to see whether the notification
   path republishes a normal policy.
7. Operator attestation; then reboot.

**Criterion:** clear effective if the machine sleeps on the lid-close test in two independent
boots with an acknowledged cleanup (structural success; the codes are not persisted). Property
republishing `true` is desirable but not required; if it stays stale, re-arm must use behaviour
or a reboot. If the machine does not sleep, R0 fails and the product track stops
(reboot-per-session is not a product).

**Safety:** same attended baseline as the v9 episodes (AC, ≥20 %, lid open, ventilated desk,
no bag, no external display); one attempt per boot; stop on any anomaly; no intentional
kernel hangs.

**Execution:** the executed attempt #3 packet was
[`reset-r0-attempt3-clear-episode-journal-qa.py`](../../Tests/Hardware/reset-r0-attempt3-clear-episode-journal-qa.py)
(reset of the attempt #2 journal; already used on boot `A9BC665D-…`),
[`r0-session-hold.py`](../../Tests/Hardware/r0-session-hold.py) (open-lid acquire/hold/stop),
and [`observe-r0-post-cleanup-sleep.py`](../../Tests/Hardware/observe-r0-post-cleanup-sleep.py)
(post-cleanup observer). A future attempt needs a new pinned reset packet and a new explicit
one-use approval. Steps, operator actions and approval text are in the
[R0 runbook](../../docs/qa/r0-behavioural-clear-runbook-2026-10-19.md).

**Attempt #1 (2026-10-19):** `R0_POST_CLEANUP_SLEEP_OBSERVED` on boot `1002AE9A-…` — the
first post-cleanup lid close produced `Clamshell Sleep`; the property read `false` after the
wake (stale). The v9 recorder's close cue was missed, so its closed-interval gate did not run;
that is a procedural deviation, not a clear failure. Record:
[`r0-behavioural-clear-attempt1-2026-10-19.md`](../../docs/qa/r0-behavioural-clear-attempt1-2026-10-19.md).

**Attempt #2 (2026-10-19, boot `FD97CCAF-…`):** reset of the attempt #1 journal succeeded; the
open-lid session hold was clean (active 10.42 s, no sleep/wake, exit 5,
`cleanupAcknowledged/userStop`). The observer's strict output was `NO_SLEEP`, but raw pmset
shows `Entering DarkWake state due to 'Clamshell Sleep'` at 19:32:41, `Display is turned off`,
and a full wake at 19:33:22 on lid open — a normal clamshell sleep cycle, not suppression. The
observer missed it because it counted only `Entering Sleep state`; the classifier is fixed to
count clamshell DarkWake and store raw pmset lines. Record:
[`r0-attempt2-adjudication-2026-10-19.md`](../../docs/qa/r0-attempt2-adjudication-2026-10-19.md).

**Attempt #3 (2026-10-20, boot `A9BC665D-…`):** reset of the attempt #2 journal succeeded;
the open-lid hold was clean (10.54 s, no sleep/wake, exit 5,
`cleanupAcknowledged/userStop`). Observer retry #1 timed out at the Continue dialog; retry #2
closed the lid and the Mac produced `Entering Sleep state due to 'Clamshell Sleep'` at
22:11:13, display off 22:11:08, and a lid-open wake at 22:17:07. The operator missed the
spoken “Open now” cue, so the observer wrote no `result.json`; raw evidence is
`R0_POST_CLEANUP_SLEEP_OBSERVED` (full). The owner accepted the raw #3 evidence on 2026-10-20;
R0 is met for behavioural same-boot clear effectiveness. The observer now has a visible open
cue (self-test passes). Record:
[`r0-attempt3-adjudication-2026-10-20.md`](../../docs/qa/r0-attempt3-adjudication-2026-10-20.md)
and [`r0-owner-acceptance-2026-10-20.md`](../../docs/qa/r0-owner-acceptance-2026-10-20.md).

## 4. G2 — native qualification (after R0)

- Full system Sleep: owner froze ≥3 independent observations across ≥2 boots on
  2026-10-21, with clean termination, zero unexplained darkwakes and operator attestation.
  A genuine backend failure under a valid procedure rejects the backend (proposal §9.3).
  Invalid/incomplete procedures do not count as PASS and never authorize automatic retry.
  This policy decision is not native episode authority; wake/cue/window timing and each
  one-use live scope still need separate review/approval. The current
  [offline timing/evidence packet](../../docs/qa/m9-manual-sleep-timing-draft-2026-10-21.md)
  keeps qualification false and records the separately approved passive grammar snapshot.
- Closed-lid continuity: sustained attended sessions with independent progress; no seconds-long
  claim; display behaviour within the current continuity-first scope.
- Failure classes: app crash, helper crash/hang, journal corruption/permission error, AC loss,
  thermal stop, foreign override, manual Sleep, reboot with pending journal.
- Hardware rows: the target MacBook Air first; additional rows separately approved.

## 5. G3 — app integration (separate approval)

- Wire the separate projection into the app behind the experimental flag; no change to the
  shipping backend or the `protected` state.
- Consent, banner, recovery UX, Settings flag and CLI parity.
- Regression: full existing test suites, Debug/Release builds, UI/accessibility pass,
  CLI integration; M6 evidence.
- Rollback: flag off restores the current preview behaviour; no persisted arming.

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Clear ineffective on the same boot | R0 gate before any UI promotion; stop the track if it fails |
| Crash strands the override | Persistent warning, recovery state, reboot guidance; no auto-re-arm |
| Hidden foreign writer | Start check refuses known conflicts; risk disclosure; no ownership claims |
| Journal corruption/disk full | Refuse before mutation; preserve evidence; recovery required |
| Manual Sleep not qualified | Full-Sleep gate; repeat observations; reject on failure |
| User treats best effort as safety | No `Protected` state; consent; banner; no bag/battery/Auto scope |
| Scope creep into Auto/Timed | Requirements and tests forbid those paths |

## 7. Sequencing

| Gate | Work | Approval |
|---|---|---|
| G0 | Offline spec/plan/tasks, model, fake tests, UI copy, CLI contract | none (offline) |
| G1 | R0 experiment ×2 fresh boots + adjudication | one-use native per boot |
| G2 | Full-Sleep repeats, sustained closed-lid, failure classes, hardware rows | one-use native per episode |
| G3 | App integration behind flag, regression, M6 | separate integration approval |
| G4 | M5 signing/notarisation/SMAppService, M7 users | separate, per milestone |

## 8. Go / no-go

- **R0 fails → stop the best-effort product track.** The app keeps the current preview; the
  lab stays as research. No reboot-per-session product.
- **R0 passes but G2 full-Sleep fails → reject the backend** (proposal §9.3).
- Only G0+G1+G2 passing enables a G3 integration request; nothing here changes the shipping
  gate by itself.
