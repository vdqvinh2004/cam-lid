# Implementation Plan: Persistent Helper (Standard Mode)

**Feature context:** `014-persistent-helper` · **Spec:** [spec.md](spec.md) · **Decision:** [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md)

## Summary
Reuse the existing `PowerLeaseService`, `PMSetBackend`, journal, safety and XPC identity code. Add an installer, an independent recovery path, restart recovery from the persisted record, and a mode layer. No new power mechanism.

## Source touchpoints (existing)
- `Packages/CamLidPowerHelper/Sources/camlid-power-helper/main.swift`: selects the backend from argv (empty = global pmset; `--lid-specific-*` = Strict).
- `Packages/CamLidPowerHelper/Sources/CamLidPowerService/`: `PowerLeaseService`, `PMSetBackend`, `LeasePowerMechanism`, `PowerXPC`, `LocalIdentityPins`, `StoragePermissions`.
- `Packages/CamLidPowerHelper/Support/com.camlid.power-helper.plist`: reference plist (lacks explicit lid-specific arguments).
- `Packages/CamLidCore/Sources/CamLidCore/PowerController.swift` and `CamLidApp/AppCoordinator.swift`: app-side backend use.

## Design decisions
- **D1 Installer.** CLI `camlid helper install|uninstall|trust|status` plus an app action using a fixed-command administrator prompt. Installs the binary to `/Library/PrivilegedHelperTools/` and a LaunchDaemon plist with `RunAtLoad` and `KeepAlive`. The same code path serves both entry points.
- **D2 Identity.** Keep peer requirement checks. Without a Developer ID, pin the exact cdhash at install time; `trust` re-pins after a rebuild. Pins are written by root only.
- **D3 Restart recovery.** On startup the helper reads the journal before listening; an expired or orphaned owned policy is restored and verified first.
- **D4 Independent recovery.** A separate root-owned scheduled job (launchd timer or detached worker) holds the persisted deadline and restores without the helper. It restores only an owned record and verifies by read-back. Exact form is chosen in T103 after a short comparison.
- **D5 Modes.** `PowerMode { standard, strict }` selects helper endpoint and storage directory. A small lock refuses a switch while a lease or unresolved journal exists in either.
- **D6 Strict.** Unchanged and frozen; surfaced only under an experimental setting.

## Phases
0. Spec and decisions (this folder, ADR). 1. Helper core: restart recovery, independent recovery, plist fix. 2. Installer and trust. 3. Mode layer and UI. 4. Fake-backed tests for all failure classes. 5. Controlled physical qualification (owner-approved, attended). 6. Integration sign-off (G3).

## Risks
- Independent recovery design is unproven; D4 may need a prototype first.
- Persistent root daemon raises the attack surface; peer rejection must be tested with real invalid signatures.
- cdhash pinning makes contributor builds awkward (open ADR question).
- Unsigned binaries are blocked by Gatekeeper when downloaded.
