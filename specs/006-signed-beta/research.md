# Research: M5 Signed Beta and Updates

**Decision**: Sparkle update integration, signing/notarization, helper lifecycle, migrations and supported build revalidation.
**Rationale**: Distribution trust and owned-state cleanup verified before external test; unresolved recovery prevents installer/removal success claims.
**Alternatives considered**: Keep all milestones in one feature (poor scope/dependency ownership);
copy every shared contract into every feature (drifting defaults); execute future work during
planning (outside authorization). Scoped features reference single shared product/limitation sources.

Inherited evidence: research decisions,
power sources, agent sources,
UX investigation. No new API/hardware behavior inferred by migration.

**Evidence still required**: Signed candidate install/upgrade/remove and update trust tests on supported rows. L07–L12, L17, L19; OS/helper change invalidates unsupported closed-lid capability.
M0 is documentation completion; all future implementation/physical/quality/user-test evidence
remains unexecuted. Unknown backend/toolchain/provider versions are resolved by predecessor gate
or scoped validation task, never hidden as a runtime compatibility promise.

## Implementation research 2026-10-05

Pinned [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0), released 2026-09-13; SwiftPM verifies the binary artifact checksum and resolved revision. The [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/) provides a main-thread updater; CamLid starts it only for an eligible manual information check. The [updater delegate](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html) gates check types and exposes valid/no-compatible results and cycle errors. Missing compatibility information must not become “up to date.”

Sparkle’s relaunch-postponement callback is not a complete install-safety gate: its documented exceptions mean installation remains absent here until integrated owned-resource/recovery validation. [Security guidance](https://sparkle-project.org/documentation/security-and-reliability/) motivates current-version pinning, Ed25519 update verification and signed candidate trust cases. Checksum/build tests are not tampered-update acceptance. No signing identities with Developer ID Application were found by a read-only local identity query; no certificates/keys were created.
