# Tasks: Persistent Helper (Standard Mode)

**Feature context:** `014-persistent-helper` · **Status:** 16/25 checked. Sources: [spec.md](spec.md), [plan.md](plan.md), [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md).

## Phase 0 — Alignment
- [x] T001 Mark admission / one-use sections of specs 012 and 013 as superseded by 014 (keep evidence). — done 2026-10-30 (notice added to 012/013 spec, plan, tasks).
- [x] T002 Update `specs/README.md`, `docs/planning/limitations.md` and `roadmap.md` for the new deployment model. — done 2026-10-30 (`specs/README.md`; local planning docs).
- [x] T003 Resolve ADR open questions: identity pinning for contributors, historical 012/013 on GitHub, Strict helper arguments. — resolved by default 2026-10-30, owner may override: see ADR 0001 "Resolved defaults".

## Phase 1 — Helper core
- [x] T101 Startup restart recovery from the journal before listening (2026-10-30). Same-boot recovery already existed and runs first on the serial queue; added cross-boot restore for the persistent global policy (Standard only; Strict unchanged). Tests: `PowerServiceTests` (4 new/changed).
- [x] T102 Explicit backend selection (2026-10-30). New `HelperLaunchMode`: `--standard-v1`, `--lid-specific-v1`, `--lid-specific-best-effort-v1`; empty argv is refused. Reference and local plists and `stage-local-candidate.py` pass `--standard-v1`; README updated; 2 new tests.
- [x] T103 Prototype and choose the independent recovery path (D4); document the choice. — chosen: a second launchd job `com.camlid.power-recovery` runs `--recover-v1` every 15 s without taking the helper lock (see plan D4).
- [x] T104 Implement independent recovery; test helper kill, helper hang, reboot with record. — `recoverOrphanedPolicy` + 7 `IndependentRecoveryTests` (helper hang, other boot, racing writer, idempotent). Fake-backed only; not run on hardware.

## Phase 2 — Installer
- [x] T201 `camlid helper install|uninstall|trust|status` (fixed command, refuses non-admin). — `camlid helper install|uninstall|trust|status` (`HelperInstaller` in CamLidCore, 10 + 2 tests with a fake runner). Not run as root.
- [x] T202 cdhash pin write at install; `trust` re-pin; refuse commands on mismatch. — pin written at install from `codesign` CDHash; `trust` re-pins and kickstarts; status reports `needsReauthorization` / `helperIdentityMismatch`.
- [x] T203 App install/uninstall action with the administrator prompt; status shown in Settings. — Settings › Safety › Closed lid: status, Install/Reinstall/Remove via the macOS administrator prompt running `CamLid --helper-admin install|uninstall`. `scripts/embed-helper.sh` (Xcode post-build) builds, embeds and ad-hoc signs the helper and app with distinct identities. Not exercised with a real admin prompt; install never run.
- [x] T204 Uninstall restores owned policy and removes plist, binary, socket; reports leftovers. — `uninstall` runs `--release-v1` first, refuses while restore is unresolved unless `--force`, removes plists, binary, pins; journal left in place.

## Phase 3 — Modes
- [x] T301 `PowerMode` with separate endpoints and storage; mutual-exclusion lock. — `PowerMode` + `PowerModeSwitch.decide`. Both modes share one label and Mach service, so only one daemon can be installed; switching = reinstall.
- [x] T302 Settings: Standard default; Strict under an advanced "experimental" section; Dashboard shows mode. — Standard shown as the mode; Strict listed as experimental and Unavailable; Dashboard footer shows "Closed lid: Standard, helper …". Checked by offscreen render (light/dark); not checked in the running app, with keyboard/VoiceOver, or at small window sizes.
- [x] T303 User-facing text for FR-012. — `PowerMode.disclosure` shown for both modes in Settings.

## Phase 4 — Fake-backed tests
- [ ] T401 Peer rejection: invalid signature, wrong pin, replaced binary, other user. — PARTIAL: wrong pin, cross-user and replaced-binary cases covered; a peer with a genuinely invalid signature is not tested.
- [x] T402 Ownership and foreign `SleepDisabled`; Unknown vs Off; guard fail-closed cases. — covered by existing ownership/foreign/Unknown/guard tests plus the restart and recovery tests above.
- [x] T403 Concurrent clients; clock change; corrupt journal. — added `SessionIsolationTests` (second client, unreadable journal); clock regression test already existed.

## Phase 5 — Physical qualification (owner-approved, attended; not started)
- [ ] T501 Sustained closed-lid progress, manual Sleep, app kill, helper kill, reboot with record, low battery, thermal pressure on the exact hardware/OS row.

## Phase 7 — Wiring Auto, Timed and Manual to the helper (design in plan D7; none started)
Open owner decisions, recommended defaults used until changed: (1) closed lid stays AC-only (helper requires AC, battery at least 20%, nominal thermal); battery sessions remain preview. (2) An external display refuses closed-lid use for now, with a visible reason; revisit after G2 data. (3) Sessions with closed lid are capped at 4 h; Auto does not extend past it.
- [ ] T701 Extract `CamLidPowerWire` (PowerRequest, PowerReply, XPC protocol, peer requirement) from `CamLidPowerService`; helper, QA client and app share it.
- [ ] T702 `PowerLeaseClient` (XPC, helper identity pinned from `identity.json`) with a fake client for tests.
- [ ] T703 `PowerHoldReconciler`: pure step function `(desired, last reply, now) -> acquire | renew | release | none`; table tests for acquire, renew every 10 s, release, refusal, lost connection, cap reached, unreadable reply.
- [ ] T704 Call the reconciler at the end of each `AppCoordinator` tick after `PolicyEngine`; feed helper stop reasons into `SafetySignal` / `recoveryConflict`, restoration evidence into `RestoreState`, and clamp the cap to 4 h.
- [ ] T705 Truthful UI: Protected only when the lease is held and read back (`leaseVerified`, `powerActuationAvailable`); show the specific reason when closed lid is unavailable (no opt-in, helper missing, battery, external display, helper refused).
- [ ] T706 Attended physical qualification of Auto with a real agent: start, hold, completion grace, release, Sleep after verified restore; app kill and helper kill mid-session. Owner-approved, not started.

## Phase 6 — Integration
- [ ] T601 App/CLI integration sign-off after T501 and T706; replaces the blocked 013 T502 path.
