# Tasks: Closed-Lid Best-Effort Hardening

> **SUPERSEDED for product deployment (2026-10-30):** the exclusive-create / no-adoption / one-use admission requirements in this document are replaced by the persistent-helper model of [spec 014](../014-persistent-helper/spec.md) and [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md). The mechanism described here remains as the experimental **Strict** mode, frozen. Evidence and dated records below are kept as history; per-episode approval is now an owner QA discipline, not a product requirement. No gate passed by this change.


**Feature context:** `013-closed-lid-hardening`
**Status:** Offline tasks T001–T004, T101–T104, T201–T203, T301–T302 and T401–T403 are
complete (2026-10-20). Reproducibility/install-packet follow-up T601–T605 is complete (2026-10-21);
22/23 total tasks checked. The owner-approved M9 install and native foreign-policy retry
completed; driver row PASS plus explicit operator attestation complete T501. T502 remains
blocked; full G2, app integration and shipping/qualification gates are unchanged.
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

## Reproducibility follow-up — 2026-10-21 (offline)

Original M9 exit is unchanged (16/18 original tasks); these additional tasks repair the
clean-checkout/handoff gaps without authorizing T501/T502.

- [x] **T601 — Make Preview regressions reproducible from Git.** Reuse the committed benchmark
  fixtures for mandatory stream/runtime checks; separate opt-in 40-run archive verification.
  Explicit missing-archive requests must fail. Run full Debug/Release Swift suites and Xcode
  builds, isolated binary integration and packaging; record skips and source fingerprints.
- [x] **T602 — Rebuild and freeze the actual M9 candidate.** Use the existing local staging
  script, exact role-separated hashes and hardened-runtime signatures; verify sources unchanged
  during the build. Replace the missing private readiness probe with a read-only QA command.
  No registration/install/IPC/acquisition occurs in staging.
- [x] **T603 — Repair and fake-test the G2 handoff.** Pin the new candidate, verify signatures,
  preserve PTY EOF/final replies, use monotonic waits and fresh post-cleanup status. Add offline
  PTY/fake-episode/identity-refusal regressions. Native entry stays blocked without a newly
  approved boot; do not reuse attempt #3's pins/latch or old approval.
- [x] **T604 — Reconcile docs and prepare the human gate.** Record actual host inventory and
  the unreadable root journal; provide a fixed-path, read-only allowlisted audit with inert
  self-tests. Update README/roadmap/spec index and handoff evidence. No journal deletion,
  root install packet or native action is inferred from an unknown journal.

- [x] **T605 — Prepare the lock-only auth installation packet.** After the owner-provided
  root audit confirms only the two safe lock files/no journal, freeze a boot/profile-specific
  first-install packet and short hash-checked launcher. Preserve locks, refuse any journal or
  existing destination/loaded job, validate ACL/role/signature/source inputs, publish exclusively
  without overwrite, report partial uncertainty, and test the root path with fakes/owned temps
  only. Packet prepared; owner subsequently approved and returned successful auth-only
  install/bootstrap/one-inspect receipts. No native power action or G2 approval follows. Evidence: [auth-only packet](../../docs/qa/m9-lock-only-install-packet-2026-10-21.md).

## Phase 5 — Native/G3 handoff (blocked; separate approvals)

- [x] **T501 — G2 native foreign-policy failure row.**
  Under a new explicit one-use approval, test that a foreign global policy during a real
  session stops CamLid without clearing the foreign flag and produces the expected recovery
  state. *PASS with operator attestation:* separately approved retry `b81e0919a`
  acquired the frozen M9 helper, observed foreign-policy recovery without clearing the foreign
  flag, then fresh final recovery after operator cleanup. Evidence:
  [row result](../../docs/qa/g2-m9-foreign-policy-result-2026-10-21.md). Owner reported reboot;
  independent boot metadata confirms a new boot. The owner selected “Đúng, không có sai lệch”,
  confirming cue timing, AC/open-lid attendance and no unexpected Sleep/wake/anomaly.
  Driver disarmed; latch preserved, no further retry authority.
  Earlier preflight rejection remains recorded, not overwritten. Not overall G2 qualification.

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

### Reproducibility completion — 2026-10-21

T601–T604 complete; [handoff and exact evidence](../../docs/qa/reproducible-m9-handoff-2026-10-21.md).
Full Preview Swift Debug/Release (519 declarations/config, four explicit skips), both Xcode
builds, actual CLI integration and packaging/read-only preflight pass. Final helper 49 and
best-effort 62 tests pass per configuration; 25 fake hardware Python tests pass, including
the paste-safe hash-checked read-only audit launcher and root lock-metadata cases (no sudo
in tests). The new
candidate was initially staged/signed/hash-pinned only. The second owner root audit confirmed
both safe lock files/no journal/no unknown entry. T605's packet passed 45 offline tests, then
received separate owner approval and owner-returned successful installation/one-inspect
receipts. Root payloads/daemon are now installed per that receipt; original locks were preserved
and no journal was deleted. The one positive inspect reports `ready/noPendingIntent`, no
mutation or lease. Independent read-only disk hashing matches the frozen helper. Post-install
G2 metadata guidance/strict CLI-entry regressions bring the fake hardware suite to 47 tests.
Those offline/auth-only checks performed no native power action. A later separately approved
retry produced the [foreign-policy driver row PASS](../../docs/qa/g2-m9-foreign-policy-result-2026-10-21.md),
with explicit operator attestation. Owner reboot is confirmed by a new boot ID. Driver is
disarmed; latch retained, no repeat or reset authority. T501 complete, T502 remains
blocked and all overall native/shipping qualification flags remain unchanged.
