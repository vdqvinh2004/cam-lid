# Tasks: Persistent Helper (Standard Mode)

**Feature context:** `014-persistent-helper` · **Status:** 0/20 checked. Sources: [spec.md](spec.md), [plan.md](plan.md), [ADR 0001](../../docs/adr/0001-persistent-helper-and-strict-experimental-mode.md).

## Phase 0 — Alignment
- [ ] T001 Mark admission / one-use sections of specs 012 and 013 as superseded by 014 (keep evidence).
- [ ] T002 Update `specs/README.md`, `docs/planning/limitations.md` and `roadmap.md` for the new deployment model.
- [ ] T003 Resolve ADR open questions: identity pinning for contributors, historical 012/013 on GitHub, Strict helper arguments.

## Phase 1 — Helper core
- [ ] T101 Startup restart recovery from the journal before listening (test with injected fake backend and clock).
- [ ] T102 Fix reference plist `ProgramArguments`; make backend selection explicit instead of empty-argv default.
- [ ] T103 Prototype and choose the independent recovery path (D4); document the choice.
- [ ] T104 Implement independent recovery; test helper kill, helper hang, reboot with record.

## Phase 2 — Installer
- [ ] T201 `camlid helper install|uninstall|trust|status` (fixed command, refuses non-admin).
- [ ] T202 cdhash pin write at install; `trust` re-pin; refuse commands on mismatch.
- [ ] T203 App install/uninstall action with the administrator prompt; status shown in Settings.
- [ ] T204 Uninstall restores owned policy and removes plist, binary, socket; reports leftovers.

## Phase 3 — Modes
- [ ] T301 `PowerMode` with separate endpoints and storage; mutual-exclusion lock.
- [ ] T302 Settings: Standard default; Strict under an advanced "experimental" section; Dashboard shows mode.
- [ ] T303 User-facing text for FR-012.

## Phase 4 — Fake-backed tests
- [ ] T401 Peer rejection: invalid signature, wrong pin, replaced binary, other user.
- [ ] T402 Ownership and foreign `SleepDisabled`; Unknown vs Off; guard fail-closed cases.
- [ ] T403 Concurrent clients; clock change; corrupt journal.

## Phase 5 — Physical qualification (owner-approved, attended; not started)
- [ ] T501 Sustained closed-lid progress, manual Sleep, app kill, helper kill, reboot with record, low battery, thermal pressure on the exact hardware/OS row.

## Phase 6 — Integration
- [ ] T601 App/CLI integration sign-off after T501; replaces the blocked 013 T502 path.
