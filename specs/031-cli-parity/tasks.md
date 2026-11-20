# Tasks: CLI parity for every interface function (v0.3)

**Feature context:** `031-cli-parity` · **Status:** 32/36 checked. Sources: [spec.md](spec.md), [contracts/cli-v0.3.md](contracts/cli-v0.3.md).

D1–D7 are accepted (the owner asked for every recommendation), so the optional tasks T023, T060 and T061 are built. Four tasks stay open, and this environment cannot finish them: T050 and T051 need an available update (the recovery refusal, the session refusal, and the install itself), which needs a real GitHub release; T060 and T073 need a GUI pass on a QA copy, to see the windows and the rows that open them. `specs/031-cli-parity/qa-record.md` says what each check covers and what is still to run by hand.

## Phase 1: Decide and lock the scope

- [x] T001 Owner confirms or changes D1–D7 in [spec.md](spec.md). Update the contract where a decision changes a shape.
- [x] T002 Parity inventory (SC-001): turn the audit tables into a checked list, one row per function with its CLI route, and add a test that fails when a route is missing from the CLI dispatch table.

## Phase 2: Reads (G3, G4 reads, G6 status, G7, G8, G11, G12, G15)

- [x] T010 G3: `agents list --json` returns the contract shape. It stops returning the status object (FR-004).
- [x] T011 G15: add the status keys (`version`, `language`, `music`, `audioHold`, `updates.automaticChecks`, `skill`, `welcome`). Keep the existing keys. Test each new key (SC-004).
- [x] T012 G12: `camlid version --json` with the CLI, app and helper versions. `app` and `helper` are `null` when unreachable.
- [x] T013 G7: `language get`, which returns the saved choice and what it resolves to.
- [x] T014 G8: `skill status`.
- [x] T015 G11: `welcome status`.
- [x] T016 G6: `update status`.
- [x] T017 G4: `music list` and `audio-hold` read; the `music` and `audioHold` status keys.

## Phase 3: Session controls (G1, G16; D3, D4, D7)

- [x] T020 G1: `session duration`. Use the same change the Dashboard makes for the running Timed session. Test the refusals in the contract.
- [x] T021 G1: `session sleep-delay`, with the same tests.
- [x] T022 D4: `start --replace`. Tests for recovery and safety refusals.
- [x] T023 G1 (D3): `start --save-mode`. Test that the saved mode changes and the session starts, and that plain `start` saves nothing.
- [x] T024 G16 (D7): the duration unit rule. Test that `--duration 60` is refused and `--duration 60m` starts a 60-minute session (SC-005).

## Phase 4: Activity (G2)

- [x] T030 `logs list` with filters and cursor. Test that output has no prompts, transcripts or task identifiers.
- [x] T031 `logs delete --session` and `--all`, each with `--confirm` and the receipt. Test the refusals.

## Phase 5: Writes through the app (G3, G4, G5, G7, G8, G9, G10, G11, G14)

- [x] T040 G3: `agents enable` and `agents disable`, for one provider or `--all`. Revision tests.
- [x] T041 G4 (D2): `music set` and `audio-hold on|off`, as preference-backed writes over the control socket.
- [x] T042 G5: `watch enable` and `watch disable` by id.
- [x] T043 G7: `language set`. The running app changes at once; test with the Vietnamese catalogue suite.
- [x] T044 G8: `skill install` and `skill remove`. They write only `~/.agents/skills/camlid/SKILL.md`. Test the QA refusal.
- [x] T045 G9: `closed-lid acknowledge-untested --confirm` and `--revoke`. Without `--confirm`, the warning is printed and nothing is recorded.
- [x] T046 G10: `notifications request`, with the three permission results.
- [x] T047 G11: `welcome complete`, which sets the same flag as Finish.
- [x] T048 G14: `login apply`.

## Phase 6: Updates (G6; D5)

- [ ] T050 `update check`: asks GitHub once. Refused on a QA copy and during recovery.
- [ ] T051 `update install [--stop-session]`: refused with a session running unless `--stop-session` is given. Tests for the checksum and writable-folder refusals.
- [x] T052 `update auto on|off`.

## Phase 7: Windows and shorthand (G13 for D1; D6)

- [ ] T060 G13 (D1): `open <window>`. Only if D1 is accepted.
- [x] T061 D6: `config set <key> <value>` for the 19 keys. Only if D6 is accepted.

## Phase 8: Documentation and proof

- [x] T070 FR-005: update the agent skill source `.agents/skills/camlid/SKILL.md` and the copy the app writes (spec 022).
- [x] T071 Add a pointer from [003 contracts/cli.md](../003-native-foundation/contracts/cli.md) to [contracts/cli-v0.3.md](contracts/cli-v0.3.md).
- [x] T072 Run `swift test --package-path Packages/CamLidCore` and `python3 scripts/check-spec-links.py`.
- [ ] T073 QA copy (SC-003): run each ✗ and ◐ row once in the app and once through the CLI, from the same state. Record the result.
- [x] T074 Update the audit rows in [spec.md](spec.md) to ✔ where done, and the totals line.
