# Feature Specification: v1.0 gates

**Status:** Planned. This record adds no features. It states the conditions for calling the product 1.0.

## Gates

- **G1 Signing.** Release certificate in use (done for 0.1). Decide whether to buy a Developer ID and notarize; ADR 0004 currently excludes it. Without notarization, the README documents the Gatekeeper step.
- **G2 Strict.** Remove the "experimental" label only with all of: E5 observed (T305); the S5 battery stop-level run (T306); trials on a second Mac or macOS build; five days of real use with no stuck state. Record the decision in an ADR 0003 amendment.
- **G3 Qualification.** At least two supported rows with evidence in the sensor matrix.
- **G4 Safety.** Lid-sensor policy decided and implemented (017 User Story 2). The recovery job's battery branch exercised live.
- **G5 Accessibility.** VoiceOver walkthrough complete; notch and second-display checks complete (019 FR-008).
- **G6 Documentation.** README, release notes and specs match the evidence; no Preview wording; no references to ignored paths.

## Out of scope (permanent or deferred)

- Fan control (excluded by the project constitution).
- Webhooks and push notifications (privacy; they would need a separate threat model).
- Weekly reports and Smart Rules (deferred until a concrete user question).

## Success Criteria

- **SC-001** Each gate has a recorded pass with a link to its evidence.
