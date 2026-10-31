# Implementation Plan: Strict mode, lid-only

**Spec:** [spec.md](spec.md)

## Design
- **Wire (`CamLidPowerWire`):** optional `mechanism` on `PowerRequest`; decoding a missing value gives `standard`.
- **Helper mechanism (`CamLidPowerService`):** new `ClamshellBitMechanism: LeasePowerMechanism`, family
  `clamshell-bit-v1`, `restoresOwnedPolicyAfterReboot = false`, `readApplied() = nil` (no getter). Native calls behind
  a small injected interface (open root-domain user client, selector 12, assertion create/extend/release) so tests use
  fakes. `readForeignPolicy` reuses `LidOnlyLeaseMechanism.observeNativeGlobalPolicy`.
- **Lease service:** `PowerLeaseService` keeps a mechanism per family and selects it at `acquire` from the request.
  The journal's `ownerIdentity` prefix names the family (the existing `lid-specific-v1:` prefix pattern). All later
  operations use the mechanism of the current lease or record. `sleepIfLidClosed` is skipped for Strict (FR-007).
- **Interruption:** the standard daemon also runs `RootDomainGeneralInterestObserver` (today only in best-effort lid
  mode). `sleepObserved` during a Strict lease ends it with `systemSleptWhileHeld`; during a Standard lease the
  existing handling is kept.
- **Recovery job:** `recoverOrphanedPolicy` picks the mechanism from the record's family; for Strict it clears the
  bit (no assertion to release in another process) and journals the restore.
- **App (`CamLidCore`/`CamLidApp`):** `PowerMode.strict` no longer means a separate daemon: `helperArgument` and the
  reinstall-to-switch rule go; availability = helper installed + Strict row match (power source checked by the helper; battery allowed with a floor
  since 2026-11-01). `QualifiedSupportRows` gains a
  mechanism. The reconciler sends the mode's mechanism with `acquire`. Settings › Safety gets the Strict choice and
  new disclosure text; the Dashboard banner explains `systemSleptWhileHeld`.

## Risks
- Undocumented selector; per-row qualification makes a macOS update turn Strict off rather than misbehave.
- No read-back; tests can only prove calls were made. Physical trials are the evidence.
- powerd may clear the shared bit (E5 not run); re-set at each renewal and report interruptions.
