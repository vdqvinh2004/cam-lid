# M8 integration readiness — 2026-10-08

Source baseline: AppCoordinator explicitly reports powerActuation=false, leaseVerified=false, backendVerified=false and backendPendingM1. PowerBackend is a contract, not a qualified live executor. No accepted closed-lid/display/sleep support row is present.

Read-only diagnostics, alerts and login integration may proceed. Live US2/3/4/5 acceptance remains blocked by M1/M2. No host power mutation or LidRun changes authorized by this evidence. Existing modes, pickers, safety policy, passive agent observation and history are reused.

The explicit display preference amendment preserves default display sleep and closed-lid internal panel-off behavior.


Implementation handoff: shared diagnosis, alerts/login adapters and Preview guards are implemented. Final Debug/Release builds and 437 executed Swift tests pass; three opt-in live probes remain skipped. Native Notification Center failure delivery, permission grant/readback/revoke, and the Settings refresh fix were verified in isolated ad-hoc QA. The subsequent T035/T041 continuation completed Preview/native-adapter alerts and affected UI acceptance, recorded in the M8 QA report. Signed login/lifecycle and live power acceptance remain open. No accepted backend/support row or signed lifecycle gate was added.

## Readiness reassessment — 2026-10-09

Source/host/signing audit and isolated refusal integration confirm the existing blocked-core decision remains in force. Fresh host identification matches Mac16,12 / macOS 27.0.1 / 26A434; signing discovery still reports 0 valid identities. Real CLI/coordinator transport tests for active Auto and Timed Preview deny start/admit/renew/finish, prevent protected child launch, block both sleep paths with `previewOnly`, preserve session/deadline/revision, and stop without claiming real-resource restoration. Full serial regression passes 438 executed / 441 cases, 3 optional live skips. No backend was implemented or actuated; M8 remains 33/43 and M1/M2/signed gates remain open.
