# Plan: v0.3 — coverage, Vietnamese, maintenance

## Work packages

| Package | Files | Notes |
|---|---|---|
| Localization | New `Localizable.xcstrings` in the app target; `Text(...)` call sites | Inventory first: about 62 `Text("…")` literals in `CamLidApp`, plus menu, notification and help strings. Keep keys stable |
| Helper guard | `scripts/check-helper-version.sh`, called from `release.sh` | Compares helper sources with the last tag |
| Simulate | `CamLidCLI/Commands.swift` (`simulate`), `Simulator.swift` | Read the stored configuration with the existing reader |
| Start mode | `Commands.start` and the mode handling | Stop writing the mode; keep `config set mode` |
| Spec hygiene | `specs/*/tasks.md`, `specs/README.md` | Scripted link check for ignored paths |
| Audio hold | New rule type next to watched programs; signal reader behind a protocol, with a fake for tests | Built only if T070 finds a reliable signal |
| Audio research | `docs/research/` (ignored; kept local) | Result recorded in a spec note; code only if the research says yes |

## Test strategy

- Localization: a test that every key has a Vietnamese value; a screen-by-screen check in Vietnamese.
- Guard: run on a clean tree and on a branch with a deliberate helper edit.
- Simulate: one recorded session replayed with the stored configuration.
- Spec check: the script returns zero matches.

## Risks

- Translation drift → keys reviewed for each release.
- Guard false positives when only tests change → the guard covers `Sources` only.
