# Tasks: Closed-Lid Best-Effort Hardening

**Feature context:** `013-closed-lid-hardening`
**Status:** Offline tasks T001–T004, T101–T104, T201–T203, T301–T302 and T401–T403 are
complete (2026-10-20). T501/T502 remain blocked on separate approvals. No native action,
install, app integration or shipping-gate change was performed.
**Sources:** [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md),
[data-model.md](data-model.md), [status contract](contracts/status.md).

## Phase 0 — Decisions and audit (offline, no code)

- [x] **T001 — Confirm the read-only policy observation source.**
  Verify that the existing `IOPMrootDomain` `SleepDisabled` boolean is the right read-only
  source for active-session foreign-policy observation. Document refresh/type/failure behavior
  and why `AppleClamshellCausesSleep` is not used. *Done when:* the decision and rejected
  alternatives are recorded in `research.md` and the plan.

- [x] **T002 — Fix the state/reason mapping.**
  Decide that a foreign global policy and an unreadable observation map to
  `recoveryRequired` with specific reasons; confirm no new state is needed. *Done when:*
  `data-model.md` and `contracts/status.md` agree and the precedence order is explicit.

- [x] **T003 — Record the helper-hang boundary.**
  Document that an in-helper watchdog cannot recover from a helper hang/kill, that no second
  watchdog is added in M9, and that reboot guidance remains the fallback. *Done when:* the
  risk is in the plan and the user copy is defined.

- [x] **T004 — Freeze the status contract.**
  Add `foreignPolicy`, `recoveryReason` and `rearmBasis` to the contract with stable values and
  invariants. *Done when:* the contract has no `Protected`/`verified` path and is ready for
  model tests.

## Phase 1 — Foreign-policy probe and stop (P1 / MVP)

- [x] **T101 — Add the observation boundary.**
  Add `ForeignPolicyObservation` and a required `readForeignPolicy()` method on
  `LeasePowerMechanism` in
  `Packages/CamLidPowerHelper/Sources/CamLidPowerService/LeasePowerMechanism.swift`.
  *Done when:* `GlobalSleepMechanism` explicitly returns `.clear`, all test mechanisms compile,
  and no mechanism can silently omit the observation.

- [x] **T102 — Implement the lid-specific read-only probe.**
  Add a read-only `SleepDisabled` accessor in
  `Packages/CamLidPowerHelper/Sources/CamLidPowerService/NativeHelperEnvironment.swift` and
  inject it into `LidOnlyLeaseMechanism`. Preserve the existing admission check and
  `AppleClamshellCausesSleep` advisory behavior. *Done when:* fake probes return
  clear/conflicted/unreadable without a subprocess and no global setter exists.

- [x] **T103 — Stop the active session on a foreign/unreadable policy.**
  Extend `PowerLeaseService.poll()` to check the probe, call the existing one-shot restore,
  and map the final state/reason. Ensure the global policy is never written or cleared.
  *Done when:* active clear → no stop; active conflicted/unreadable → recoveryRequired with
  the exact reason; own clear happens at most once.

- [x] **T104 — Add fake tests for the probe and stop path.**
  Cover clear, conflicted, unreadable, clear-again, disabled-at-start, own clear once, no
  global write, and reason/status precedence in
  `Packages/CamLidPowerHelper/Tests/CamLidPowerServiceTests/`.
  *Done when:* all new tests pass in Debug and Release.

## Phase 2 — Recovery explainability (P1)

- [x] **T201 — Add journal intent to the offline projection.**
  Add `intent` to `BestEffortJournalEntry` and specific reasons
  `pendingCurrentBootEnable`, `pendingCurrentBootRestore`, `previousBootAbnormalBaseline` and
  `previousBootSuperseded` in
  `Tests/Experiments/BestEffortLidSession/Sources/BestEffortLidSession/BestEffortProductModel.swift`.
  *Done when:* the model can distinguish the four cases without reading the clamshell property.

- [x] **T202 — Prove no blind clear/retry on pending states.**
  Add fake tests for current-boot pending enable, current-boot pending restore, previous-boot
  abnormal baseline and acknowledged clear. Assert that pending states produce recoveryRequired
  and zero clear calls. *Done when:* the tests fail if a blind clear or silent ready state is
  introduced.

- [x] **T203 — Add re-arm basis and stale-property tests.**
  Add `rearmBasis` (`none`, `behaviouralLidCycle`, `reboot`, `explicitQualification`) and tests
  that true/false/unreadable `AppleClamshellCausesSleep` never authorizes a start after cleanup.
  *Done when:* `cleanupAcknowledged` + `none` refuses re-arm; only the explicit path changes the
  basis.

## Phase 3 — Helper availability and docs (P2)

- [x] **T301 — Map helper unavailability/timeout to stable reasons.**
  Add fake-client tests for no connection, timeout, invalid reply and restart; map them to
  `helperUnavailable` / `helperTimeout` with recovery guidance. Do not add retries or a new XPC
  operation. *Done when:* no missing reply can produce active/cleanup success.

- [x] **T302 — Write the failure-class note.**
  Add a short QA/planning note recording the foreign-policy row, pending-enable/restore cases,
  helper-hang limitation and the fact that G2 native evidence is separate. *Done when:* the note
  links to the plan and does not claim a pass.

## Phase 4 — Regression and handoff (offline)

- [x] **T401 — Run the full offline suites.**
  Run helper and best-effort tests in Debug and Release; record counts and any skips.
  *Done when:* both suites pass and no native action/install occurred.

- [x] **T402 — Check the contract invariants.**
  Verify no global setter, no admin fallback, no new watchdog, no `Protected`/`verified` claim,
  and GUI/CLI reason parity at the model/contract level. *Done when:* the checks are recorded in
  the QA note.

- [x] **T403 — Update roadmap and handoff.**
  Link M9 from the roadmap and closed-lid product path; record that G2/G3 remain separately
  blocked and that R0 was accepted on 2026-10-20 (with re-arm still an explicit qualification
  input). *Done when:* links resolve and no qualification is implied.

## Phase 5 — Native/G3 handoff (blocked; separate approvals)

- [ ] **T501 — G2 native foreign-policy failure row.**
  Under a new explicit one-use approval, test that a foreign global policy during a real
  session stops CamLid without clearing the foreign flag and produces the expected recovery
  state. *Blocked:* native action approval; not part of M9's offline exit.

- [ ] **T502 — G3 app/CLI integration.**
  Wire the M9 contract into the app behind the experimental flag, with consent/banner/recovery
  copy and CLI parity. *Blocked:* separate app-integration approval; no shipping-gate change.

## Dependencies and Ordering

- T001–T004 are decisions; no code.
- T101–T103 depend on T001–T002; T104 follows T101–T103.
- T201–T203 can run in parallel with T101–T104, but the contract from T004 is authoritative.
- T301–T302 follow the contract; T401–T403 require all offline tasks.
- T501–T502 are not part of the M9 exit gate and must not be started without explicit approval.

## Blocked / Out of Scope

Global `pmset disablesleep` writes, administrator fallback, a second watchdog, same-bit foreign
writer detection, app integration, helper install, native qualification, shipping-gate change,
Auto/Timed/battery/background start, completion sleep, bag/sleeve use and verified restoration
are outside M9.


## Completion Record — 2026-10-20

Offline exit gate met at the model/helper/test level. Evidence:
[offline QA note](../../docs/qa/m9-closed-lid-hardening-offline-2026-10-20.md).

- Helper package: 49 tests / 5 suites pass in Debug and Release.
- Best-effort package: 62 tests / 2 suites pass in Debug and Release.
- T001–T004: decisions and contract frozen in `research.md`, `plan.md`, `data-model.md` and
  `contracts/status.md`; `currentBootEnableAcknowledged` and helper-failure mapping recorded.
- T101–T104: required read-only `readForeignPolicy()`, lid-specific probe, one-shot stop,
  same-boot restart re-observation (including one own clear after an acknowledged enable) and
  fake tests (clear/conflicted/unreadable/throwing, clear-again, no foreign write).
- T201–T203: journal intent, pending/acknowledged reasons, boot foreign observation, explicit
  `rearmBasis`, stale property tests.
- T301–T302: helper failure mapping and failure-class note; no retry or new XPC operation.
- T401–T403: full suites, contract checks and roadmap/product-path handoff.

T501 (G2 native row) and T502 (G3 app/CLI wiring) remain **blocked** and are not part of this
offline completion. `qualifiedClosedLidProtection=false`; full system Sleep and verified
restoration remain unqualified.
