# Isolated recovery broker

Non-actuating macOS Swift package. It depends on the sibling experimental journal (`LidRecoveryJournal`). The app and the
helper do not import it; `LidNativeAdapter` depends on it, so it builds with that package. It has no power API,
assertion, helper registration, launchd job or installed monitor. Owned finite-lived fixtures exercise independent
recovery scheduling.

## Public seam

- `RecoveryBroker(directory:trustedClients:trustedMonitors:)` opens the private journal and samples the real boot UUID/continuous clock. A saved record always requires reconciliation, even if it claims acknowledgment. Startup never re-arms anything.
- `serveConnection(_:)` handles one request on a caller-owned connected Unix socket. Caller must serialize access to each broker instance, own the listener/endpoint lifecycle and close every accepted descriptor on success or error. This library does not listen or schedule work.
- `BrokerConnection.exchange(path:serverPin:request:)` pins the server before sending a request. Both peers use kernel socket audit tokens, Security code validity checks, exact executable CDHashes and matching effective UID. No PID-only, bundle-ID-only or unsigned-build fallback.
- `admitInertLease`, `renewInertLease`, `finishInertLease` require a client executable pin. Admission binds effective UID/PID/PID version/CDHash from the actual socket peer, never claimed ownership. Renew/finish additionally require matching session, generation and revision with a strictly increasing sequence. All acknowledgments follow journal commits.
- Renewal duration is positive and at most 30 seconds, capped at the original session deadline. Requested session duration is positive and at most one experimental hour; arithmetic overflow is refused. Short durations are for inert tests, not measured assertion expiry. One episode per journal: terminal state stays unresolved and blocks rearming.
- `poll()` lets the caller schedule deadline checks without client IPC. `status` also refreshes expiration; it can persist unresolved expiry intent, but cannot request arbitrary monitor recovery. Missing/corrupt/changed active records invalidate the in-memory lease; repaired storage does not resurrect it.
- `recordRestoreIntent` requires a separately configured monitor executable pin and exact expected revision. It preserves prior identity/deadline metadata and writes `restoreLidPolicy` / `unresolved`. It never executes restoration or clears the record.
- `InertRecoveryExecutor.reconcile(brokerPath:serverPin:)` is a separately scheduled journal-only seam. It authenticates the broker before observing a still-valid lease. Deadline/previous-boot/broker-unresponsive or mismatching observations record unresolved restore intent using compare-and-replace. Clock/corruption/publication faults latch; missing previously observed state is not clean. Cooperative lock/revision contention irreversibly requires unresolved restore intent: later attempts may retry only that recording, never return to waiting on the old lease. A suspended writer retaining the lock prevents publication until it releases the lock. It does not authenticate stored owner claims or restore kernel policy.

Client and monitor pin sets must be disjoint. Empty configuration denies all callers. Pins are owner-supplied local configuration, never request fields. Ad-hoc builds still require valid exact pins; rebuilding changes the pin. A journal owner string or checksum is not IPC authentication.

Replies always report `powerActuation=false` and `protectionAvailable=false`. `accepted=true` means status, inert lease bookkeeping or acknowledged unresolved intent, never admission to physical protection. Unauthorized replies expose no startup/reconciliation state.

## Fail-closed behavior

- Framing: four-byte big-endian body length; 1–32,768 bytes; one JSON request per connection; protocol version 1. Unsupported operations, malformed JSON and invalid lengths cannot mutate the journal.
- Frame read/write uses nonblocking I/O and one three-second total deadline. Slow partial input cannot extend it. This is **not** a time bound on connect, Security calls, journal I/O or the complete operation.
- Saved intent is classified as previous boot, deadline expired, saved intent or unresolved restoration. Classification is diagnostic, not ownership or physical-policy evidence.
- Boot changes, continuous-clock regression or unavailable clock readings latch a fault until a new broker instance. They prevent monitor writes as well as status success. Recorded old-boot intent can still be recorded for recovery; it cannot become a new lease.
- Corrupt/future/unsafe journal storage prevents startup or a successful request. Revision conflicts/replays cannot erase existing intent. All persistence errors propagate without a success reply; publication uncertainty requires reconciliation.
- Once reconciliation is observed it stays required for that instance, including after unexpected record disappearance. No API here certifies recovery or returns it to clean.

## Verification

```sh
swift test --no-parallel --package-path Packages/LidRecoveryBroker

swift test --no-parallel --configuration release --package-path Packages/LidRecoveryBroker
```

Test-only executables: `LidBrokerFixture` (one-shot or persistent client), `LidBrokerServerFixture` (owned listener and polling loop), `LidRecoveryMonitorFixture` (separate journal-only executor). Tests own all private roots/sockets/processes; signals target only these explicitly launched children, never another app. Clock/filesystem injection is trusted SPI, not IPC configuration or an authentication bypass.

## Remaining boundaries

Inert leases and finite owned recovery fixtures are **not** a production power backend or installed watchdog. There is no physical setter/getter, writer fencing, sleep/panel acceptance, automatic restart supervision, helper installer, signed lifecycle or original milestone pass. Monitor readiness is not required for inert bookkeeping; a live adapter would need separately qualified readiness and supervision.

Exact main-executable pins plus code validity do not establish hardened-runtime/library integrity, defeat a compromised trusted process or cooperative descriptor passing, authenticate journal contents, prevent same-user filesystem tampering or create ownership/expiry for the shared lid bit. Signed production trust policy and host qualification remain separate work. A process or filesystem stall can prevent recovery regardless of the frame deadline.
