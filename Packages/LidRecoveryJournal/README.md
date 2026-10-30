# Experimental lid-recovery journal

First separately approved implementation slice of the [independent open-source path](../../../docs/research/open-source-closed-lid-path-2026-10-09.md). This is real disk-persistence infrastructure, not another inert recovery model and **not a power backend**.

## Boundary

- Standalone Swift 6 / macOS 13+ package, Foundation/CryptoKit/Darwin only; no third-party dependencies or connection to shipping targets.
- No IOKit, assertions, lid/display/power setters, helpers, login registration, sudoers or Apple account/contact activity.
- Tests create private temporary roots, run only the package's own fixture processes and remove those owned roots. SIGKILL targets an owned fixture, never installed CamLid, LidRun or a foreign process.
- There is no IPC admission, authenticated broker, clock/boot identity provider, physical recovery, automatic rearm, production enable switch or schema migration here. Existing model and Preview refusal remain separate.

## API

```swift
let journal = try DurableRecoveryJournal(directory: privateDirectory)
let previous: JournalEntry? = try journal.load()
try journal.commit(nextEntry, replacing: previous?.revision)
```

The parent must already exist. A missing final journal directory is created 0700; an existing directory must be owned by the effective user and exactly 0700. The implementation retains its opened directory FD, verifies its parent entry, and checks file metadata through that FD. It does not repair unsafe shared storage or adopt another owner's files.

`JournalEntry` records revision, claimed session/owner/boot identity, generation, operation ID, intent (`enableLidOverride` / `restoreLidPolicy`), disposition (`pending` / `acknowledged` / `unresolved`) and absolute continuous deadline. These are caller-supplied data. The journal does not authenticate those identities, compare a deadline to a clock, establish restoration, or prevent admission on its own. A future governor must do that before any actuation. `acknowledged` is not a physical observation.

- `replacing: nil`: create revision 1 **only if no authoritative record exists**.
- `replacing: n`: require an existing revision n and proposed revision n+1; reject stale/skipped/overflowing revisions. No deletion or fault-erasure API is provided.
- A schema-1 envelope uses canonical sorted-key entry encoding and a SHA-256 digest. Recognized payload corruption, malformed records and future schemas fail closed rather than appearing absent. SHA-256 is an integrity checksum, **not a signature/MAC or anti-replay mechanism**.
- A 65,536-byte envelope limit bounds disk reads and publication. Nonempty identities and positive revision/generation/deadline are required; that is structural validation, not identity or lease qualification.

## Publication and errors

1. Sync the journal directory and its parent before opening the seam successfully. A newly created directory's parent entry must not be left outside the synchronization boundary.
2. Use a separate stable `.journal.lock` with nonblocking shared/exclusive `flock`. Busy readers/writers fail with `.busy`; they do not wait behind a paused writer. Lock files and authoritative records must be same-user 0600 regular files with one link; final symlinks are rejected.
3. Under the exclusive lock, check existing record/revision, validate and encode the replacement.
4. Write a unique 0600 temporary file completely, handling partial writes and EINTR; synchronize the file, atomically publish with descriptor-relative `renameat`, then synchronize the directory.
5. Return success only after these calls acknowledge success. Ordinary handled failures remove their own temporary file. A killed writer can leave a temporary file, but it is never interpreted as authoritative or silently promoted.

`JournalFailure` separates revision conflict, invalid entry, busy, unsafe storage, corrupt/future/oversized data, I/O errors and `.publicationUncertain`. A publication or post-publication flush error can leave the new record visible without a durability acknowledgment. **Do not treat any thrown error as successful admission, nor assume the old record necessarily remains.** Re-read/reconcile under governor policy. The SPI fault seam can model publish-then-error responses; that is not proof such a response occurred on this host.

## Limits that matter

- `fsync` acknowledgments and atomic namespace visibility do not prove power-loss durability on every filesystem/device. There is no `F_FULLFSYNC`, drive-cache/power-cut test or filesystem support qualification yet. No power-loss guarantee is made.
- Filesystem reads/writes/sync may still block despite nonblocking lock acquisition. There is no writer execution deadline, cancellation guarantee or independent recovery process. A future broker must isolate/fence that execution path; a journal cannot fix an in-flight OS power write.
- Cooperative locking depends on participants preserving the lock inode. It does not defeat a same-user process that rewrites a record, replaces lock files or replays an older valid envelope. A test deliberately demonstrates a forged identity with a recomputed valid checksum being accepted as data.
- POSIX metadata/last-component no-follow checks are not a complete ACL, ancestor-path or malicious-same-user security audit. The caller must choose a trusted private storage parent; a production storage policy remains pending.
- Claimed boot/deadline values need a real provider and restart reconciliation. A previous-boot deadline or valid old record must never silently rearm a session. None of those policies is implemented by this storage API.
- No kernel ownership/TTL, panel-sleep verification, preserved manual Sleep or joint-failure cleanup is supplied. No M1/M2 completion follows from these tests.

## Verification

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --no-parallel --package-path Tests/Experiments/LidRecoveryJournal

env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --no-parallel --configuration release \
  --package-path Tests/Experiments/LidRecoveryJournal
```

The test-only `LidJournalFixture` executable supports load/commit and a bounded pause immediately before publication for deterministic process contention/crash tests. It receives only owned temporary paths. It is not an installed helper, recovery monitor or production service. Tests locate it from the test bundle rather than assuming Swift Testing's `CommandLine.arguments[0]` is an `.xctest` executable.

See [journal development evidence](../../../docs/qa/lid-recovery-journal-2026-10-09.md): 21 test declarations / 36 scenarios, 11 behavioral red/green cycles, real cross-process reopen/contention/crash and controlled filesystem faults. Release/Debug test results qualify this seam only. Licensing selection and any experimental actuation/hardware lane remain separate decisions.
