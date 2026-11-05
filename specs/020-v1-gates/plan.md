# Plan: v1.0 gates

Each gate is checked against recorded evidence, not against a feeling of readiness.

| Gate | Evidence location | Owner action |
|---|---|---|
| G1 Signing | ADR 0004 (and an amendment if the decision changes); release notes | Decision |
| G2 Strict | Spec 016 trial record; ADR 0003 amendment | Trials on hardware |
| G3 Qualification | Sensor matrix in the QA addendum | Trials on a second row |
| G4 Safety | Spec 017 User Story 2 record; recovery-job log | Live test |
| G5 Accessibility | Spec 019 FR-008 record | Walkthroughs |
| G6 Documentation | Scripted check from spec 019 (FR-006) | None |

A gate closes only when its evidence is written and linked. A failed trial reopens the gate; it does not get a note.
