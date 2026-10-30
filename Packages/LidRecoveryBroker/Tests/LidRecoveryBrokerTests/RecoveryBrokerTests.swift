import Foundation
import Darwin
import Testing
@_spi(FaultInjection) import LidRecoveryJournal
@_spi(TestInputs) @testable import LidRecoveryBroker

@Suite("Experimental broker — no host power", .serialized)
struct RecoveryBrokerTests {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clrb-\(UUID().uuidString.prefix(12))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("journal"))
    }

    private func savedIntent() -> JournalEntry {
        JournalEntry(revision: 1, sessionID: "previous-session", ownerIdentity: "claimed-owner",
            bootID: "previous-boot", generation: 7, operationID: "previous-operation",
            intent: .enableLidOverride, disposition: .acknowledged, continuousDeadlineNanos: 1)
    }

    private final class BundleLocator: NSObject {}

    private func fixtureExecutable() throws -> URL {
        let bundle = Bundle(for: BundleLocator.self).bundleURL
        for base in [bundle.deletingLastPathComponent(), bundle] {
            let candidate = base.appendingPathComponent("LidBrokerFixture")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw BrokerFailure.transport(ENOENT)
    }

    private func exchange(_ broker: RecoveryBroker, directory: URL,
                          serverPin: CodeIdentityPin? = nil,
                          request: BrokerRequest = BrokerRequest()) throws -> BrokerReply {
        let parent = directory.deletingLastPathComponent()
        let path = parent.appendingPathComponent("socket").path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BrokerFailure.transport(errno) }
        defer { Darwin.close(fd); unlink(path) }
        var address = try socketAddress(path)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 4) == 0 else {
            throw BrokerFailure.transport(errno)
        }
        let input = parent.appendingPathComponent("request.json")
        let output = parent.appendingPathComponent("reply.json")
        try JSONEncoder().encode(request).write(to: input)
        let client = Process()
        client.executableURL = try fixtureExecutable()
        client.arguments = [path, try (serverPin ?? CodeIdentityPin.currentProcess()).cdhash, input.path, output.path]
        try client.run()
        defer {
            if client.isRunning {
                kill(client.processIdentifier, SIGKILL)
                client.waitUntilExit()
            }
        }
        let readiness = FrameIO(fd: fd)
        try readiness.wait(Int16(POLLIN))
        let peerFD = accept(fd, nil, nil)
        guard peerFD >= 0 else { throw BrokerFailure.transport(errno) }
        defer { Darwin.close(peerFD) }
        try broker.serveConnection(peerFD)
        let limit = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while client.isRunning, DispatchTime.now().uptimeNanoseconds < limit {
            Thread.sleep(forTimeInterval: 0.005)
        }
        guard !client.isRunning else { throw BrokerFailure.timeout }
        #expect(client.terminationStatus == 0)
        return try JSONDecoder().decode(BrokerReply.self, from: Data(contentsOf: output))
    }

    private func localExchange(_ broker: RecoveryBroker, request: BrokerRequest) throws -> BrokerReply {
        var reply: BrokerReply?
        try withSocketPair { server, client in
            try FrameIO(fd: client).write(JSONEncoder().encode(request))
            try broker.serveConnection(server)
            reply = try JSONDecoder().decode(BrokerReply.self, from: FrameIO(fd: client).read())
        }
        return try #require(reply)
    }

    @Test func inertAdmissionPersistsPeerBoundIntentBeforeAcknowledgment() throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            environment.nowNanos = 100
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()], environment: environment)
            let reply = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 30, sessionDurationNanos: 90))
            #expect(reply.accepted && reply.reason == "inertLeaseAdmitted")
            #expect(!reply.powerActuation && !reply.protectionAvailable)
            let lease = try #require(reply.lease)
            #expect(lease.deadlineNanos == 130 && lease.capNanos == 190)
            #expect(lease.sequence == 1 && lease.revision == 1 && lease.generation > 0)
            let saved = try #require(try DurableRecoveryJournal(directory: directory).load())
            #expect(saved.sessionID == lease.sessionID && saved.generation == lease.generation)
            #expect(saved.continuousDeadlineNanos == 130 && saved.disposition == .pending)
            #expect(saved.ownerIdentity.contains("pid:\(getpid()):"))
            #expect(saved.bootID == "previous-boot")
        }
    }

    @Test func renewalRejectsReplayAndCannotExtendSessionCap() throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            environment.nowNanos = 100
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()], environment: environment)
            let first = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 30, sessionDurationNanos: 90))
            let original = try #require(first.lease)
            let renewal = BrokerRequest(operation: .renewInertLease, expectedRevision: 1,
                sessionID: original.sessionID, generation: original.generation, sequence: 2, durationNanos: 40)
            environment.nowNanos = 120
            let reply = try localExchange(broker, request: renewal)
            let renewed = try #require(reply.lease)
            #expect(reply.accepted && reply.reason == "inertLeaseRenewed")
            #expect(renewed.deadlineNanos == 160 && renewed.capNanos == 190 && renewed.revision == 2)
            let replay = try localExchange(broker, request: renewal)
            #expect(!replay.accepted && replay.reason == "invalidLeaseRequest")
            environment.nowNanos = 150
            let capped = try localExchange(broker, request: BrokerRequest(operation: .renewInertLease,
                expectedRevision: 2, sessionID: original.sessionID, generation: original.generation,
                sequence: 3, durationNanos: 80))
            let finalLease = try #require(capped.lease)
            #expect(capped.accepted && finalLease.deadlineNanos == 190 && finalLease.capNanos == 190)
            let stored = try #require(try DurableRecoveryJournal(directory: directory).load())
            #expect(stored.revision == 3 && stored.continuousDeadlineNanos == 190)
            #expect(!capped.protectionAvailable && !capped.powerActuation)
        }
    }

    @Test(arguments: ["finish", "expiry"])
    func terminalLeasePreservesUnresolvedIntentAndNeverRearms(_ trigger: String) throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            environment.nowNanos = 100
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()], environment: environment)
            let first = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 30, sessionDurationNanos: 90))
            let lease = try #require(first.lease)
            if trigger == "expiry" { environment.nowNanos = 130 }
            let terminal = try localExchange(broker, request: trigger == "expiry" ? BrokerRequest() :
                BrokerRequest(operation: .finishInertLease, expectedRevision: 1,
                    sessionID: lease.sessionID, generation: lease.generation, sequence: 2))
            #expect(terminal.lease == nil && !terminal.protectionAvailable && !terminal.powerActuation)
            let saved = try #require(try DurableRecoveryJournal(directory: directory).load())
            #expect(saved.revision == 2 && saved.intent == .restoreLidPolicy && saved.disposition == .unresolved)
            #expect(saved.sessionID == lease.sessionID && saved.continuousDeadlineNanos == 130)
            let late = try localExchange(broker, request: BrokerRequest(operation: .renewInertLease,
                expectedRevision: 1, sessionID: lease.sessionID, generation: lease.generation,
                sequence: 3, durationNanos: 30))
            #expect(!late.accepted)
            let rearm = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 30, sessionDurationNanos: 90))
            #expect(!rearm.accepted && rearm.reason == "reconciliationRequired")
            #expect(try DurableRecoveryJournal(directory: directory).load() == saved)
        }
    }

    @Test func unreadableActiveJournalCannotResumeAfterRepair() throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()], environment: environment)
            let first = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 100, sessionDurationNanos: 200))
            let lease = try #require(first.lease)
            let path = directory.appendingPathComponent("recovery.json")
            let original = try Data(contentsOf: path)
            try Data("{".utf8).write(to: path)
            #expect(throws: JournalFailure.corrupt) { try localExchange(broker, request: BrokerRequest()) }
            try original.write(to: path)
            let resumed = try localExchange(broker, request: BrokerRequest(operation: .renewInertLease,
                expectedRevision: 1, sessionID: lease.sessionID, generation: lease.generation,
                sequence: 2, durationNanos: 100))
            #expect(!resumed.accepted && resumed.lease == nil)
            let saved = try #require(try DurableRecoveryJournal(directory: directory).load())
            #expect(saved.revision == 1)
        }
    }

    @Test(arguments: ["owner", "session", "generation", "sequence", "revision", "duration"])
    func invalidRenewalCannotChangeDurableDeadline(_ invalid: String) throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess(), CodeIdentityPin(executable: fixtureExecutable())],
                environment: environment)
            let first = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 100, sessionDurationNanos: 200))
            let lease = try #require(first.lease)
            let before = try DurableRecoveryJournal(directory: directory).load()
            let request = BrokerRequest(operation: .renewInertLease,
                expectedRevision: invalid == "revision" ? 2 : 1,
                sessionID: invalid == "session" ? "foreign-session" : lease.sessionID,
                generation: invalid == "generation" ? lease.generation ^ 1 : lease.generation,
                sequence: invalid == "sequence" ? 1 : 2,
                durationNanos: invalid == "duration" ? 0 : 150)
            let reply = try invalid == "owner" ? exchange(broker, directory: directory, request: request) :
                localExchange(broker, request: request)
            #expect(!reply.accepted && reply.reason == "invalidLeaseRequest")
            #expect(try DurableRecoveryJournal(directory: directory).load() == before)
        }
    }

    @Test(arguments: ["zeroLease", "longLease", "zeroCap", "longCap", "sequence", "overflow"])
    func invalidAdmissionNeverCreatesIntent(_ invalid: String) throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            if invalid == "overflow" { environment.nowNanos = UInt64.max - 5 }
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()], environment: environment)
            let duration: UInt64 = invalid == "zeroLease" ? 0 :
                invalid == "longLease" ? 30_000_000_001 : 100
            let cap: UInt64 = invalid == "zeroCap" ? 0 :
                invalid == "longCap" ? 3_600_000_000_001 : 200
            #expect(throws: BrokerFailure.protocolViolation) {
                try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                    sequence: invalid == "sequence" ? 0 : 1, durationNanos: duration, sessionDurationNanos: cap))
            }
            #expect(try DurableRecoveryJournal(directory: directory).load() == nil)
        }
    }

    @Test func restartAndMonitorCommitInvalidateLeaseWithoutRearming() throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            let clients: Set<CodeIdentityPin> = [try CodeIdentityPin.currentProcess()]
            let monitors: Set<CodeIdentityPin> = [try CodeIdentityPin(executable: fixtureExecutable())]
            let broker = try RecoveryBroker(directory: directory, trustedClients: clients,
                trustedMonitors: monitors, environment: environment)
            let first = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 100, sessionDurationNanos: 200))
            let lease = try #require(first.lease)
            let restart = try RecoveryBroker(directory: directory, trustedClients: clients, environment: environment)
            let renewal = BrokerRequest(operation: .renewInertLease, expectedRevision: 1,
                sessionID: lease.sessionID, generation: lease.generation, sequence: 2, durationNanos: 150)
            let resurrected = try localExchange(restart, request: renewal)
            #expect(!resurrected.accepted && resurrected.lease == nil)
            let restored = try exchange(broker, directory: directory,
                request: BrokerRequest(operation: .recordRestoreIntent, expectedRevision: 1))
            #expect(restored.accepted && restored.lease == nil)
            let late = try localExchange(broker, request: renewal)
            #expect(!late.accepted && late.lease == nil)
            let stored = try #require(try DurableRecoveryJournal(directory: directory).load())
            #expect(stored.revision == 2 && stored.intent == .restoreLidPolicy && stored.disposition == .unresolved)
        }
    }

    @Test func scheduledPollExpiresWithoutClientIPC() throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            environment.nowNanos = 100
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()], environment: environment)
            _ = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 30, sessionDurationNanos: 90))
            environment.nowNanos = 130
            try broker.poll()
            let saved = try #require(try DurableRecoveryJournal(directory: directory).load())
            #expect(saved.revision == 2 && saved.intent == .restoreLidPolicy && saved.disposition == .unresolved)
        }
    }

    @Test func independentExecutorRecordsUnresponsiveBrokerWithoutClaimingRestoration() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let executor = try InertRecoveryExecutor(directory: directory, environment: TestEnvironment())
            let missingSocket = directory.deletingLastPathComponent().appendingPathComponent("missing.sock").path
            let result = try executor.reconcile(brokerPath: missingSocket, serverPin: CodeIdentityPin.currentProcess())
            #expect(result.reason == "brokerUnresponsiveUnresolved" && result.revision == 2)
            #expect(!result.powerActuation && !result.protectionAvailable)
            let record = try #require(try journal.load())
            #expect(record.intent == .restoreLidPolicy && record.disposition == .unresolved)
            #expect(record.sessionID == "previous-session" && record.ownerIdentity == "claimed-owner")
            #expect(record.generation == 7 && record.continuousDeadlineNanos == 1)
            let again = try executor.reconcile(brokerPath: missingSocket, serverPin: CodeIdentityPin.currentProcess())
            #expect(again.reason == "alreadyUnresolved" && again.revision == 2)
            #expect(try journal.load() == record)
        }
    }

    private final class PublicationFault: JournalSystemCalls {
        let environment: TestEnvironment
        var mode: String
        init(environment: TestEnvironment, mode: String) { self.environment = environment; self.mode = mode }
        func write(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {
            if mode == "writeFailure" { errno = ENOSPC; return -1 }
            return Darwin.write(fd, bytes, count)
        }
        func synchronize(_ fd: Int32) -> Int32 { Darwin.fsync(fd) }
        func publish(directoryFD: Int32, temporaryName: String, finalName: String) -> Int32 {
            let result = Darwin.renameat(directoryFD, temporaryName, directoryFD, finalName)
            guard result == 0 else { return result }
            if mode == "uncertain" { errno = EIO; return -1 }
            if mode == "late" { environment.nowNanos = 120 }
            if mode == "lateOld" { environment.nowNanos = 105 }
            return 0
        }
    }

    @Test(arguments: ["uncertain", "late"])
    func uncertainOrLatePublicationCannotAcknowledgeOrResumeAdmission(_ mode: String) throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            let calls = PublicationFault(environment: environment, mode: mode)
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()], environment: environment, systemCalls: calls)
            let request = BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 100, sessionDurationNanos: 200)
            if mode == "uncertain" {
                #expect(throws: JournalFailure.publicationUncertain(operation: "publish", code: EIO)) {
                    try localExchange(broker, request: request)
                }
            } else {
                #expect(throws: BrokerFailure.leaseExpired) { try localExchange(broker, request: request) }
            }
            let visible = try #require(try DurableRecoveryJournal(directory: directory).load())
            #expect(visible.revision == 1 && visible.disposition == .pending)
            let status = try localExchange(broker, request: BrokerRequest())
            #expect(status.lease == nil && status.startup == .reconciliationRequired)
            let retry = try localExchange(broker, request: request)
            #expect(!retry.accepted && retry.reason == "reconciliationRequired")
            #expect(!retry.protectionAvailable && !retry.powerActuation)
        }
    }

    @Test(arguments: ["uncertain", "late", "writeFailure", "lateOld"])
    func failedOrLateRenewalCannotResumeFromVisibleIntent(_ mode: String) throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            let calls = PublicationFault(environment: environment, mode: "healthy")
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()], environment: environment, systemCalls: calls)
            let admitted = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 100, sessionDurationNanos: 200))
            let lease = try #require(admitted.lease)
            environment.nowNanos = 90
            calls.mode = mode
            let renewal = BrokerRequest(operation: .renewInertLease, expectedRevision: 1,
                sessionID: lease.sessionID, generation: lease.generation, sequence: 2, durationNanos: 30)
            if mode == "uncertain" {
                #expect(throws: JournalFailure.publicationUncertain(operation: "publish", code: EIO)) {
                    try localExchange(broker, request: renewal)
                }
            } else if mode == "late" || mode == "lateOld" {
                #expect(throws: BrokerFailure.leaseExpired) { try localExchange(broker, request: renewal) }
            } else {
                #expect(throws: JournalFailure.io(operation: "write", code: ENOSPC)) {
                    try localExchange(broker, request: renewal)
                }
            }
            calls.mode = "healthy"
            let visible = try #require(try DurableRecoveryJournal(directory: directory).load())
            #expect(visible.revision == (mode == "writeFailure" ? 1 : 2))
            #expect(visible.continuousDeadlineNanos == (mode == "writeFailure" ? 100 : 120))
            let retry = try localExchange(broker, request: renewal)
            #expect(!retry.accepted && retry.lease == nil)
            #expect(try DurableRecoveryJournal(directory: directory).load() == visible)
        }
    }

    @Test func busyActiveJournalInvalidatesInsteadOfWaitingOrResuming() throws {
        try withDirectory { directory in
            let environment = TestEnvironment()
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()], environment: environment)
            let admitted = try localExchange(broker, request: BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 100, sessionDurationNanos: 200))
            let lease = try #require(admitted.lease)
            let fd = Darwin.open(directory.appendingPathComponent(".journal.lock").path, O_RDWR | O_CLOEXEC)
            #expect(fd >= 0)
            defer { Darwin.close(fd) }
            #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
            #expect(throws: JournalFailure.busy) { try broker.poll() }
            #expect(flock(fd, LOCK_UN) == 0)
            let resumed = try localExchange(broker, request: BrokerRequest(operation: .renewInertLease,
                expectedRevision: 1, sessionID: lease.sessionID, generation: lease.generation,
                sequence: 2, durationNanos: 100))
            #expect(!resumed.accepted && resumed.lease == nil)
            let saved = try #require(try DurableRecoveryJournal(directory: directory).load())
            #expect(saved.revision == 1 && saved.continuousDeadlineNanos == 100)
        }
    }

    @Test(arguments: ["regression", "bootChanged", "unavailable", "disappeared"])
    func executorFaultCannotBecomeSuccessAfterRepair(_ fault: String) throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            let entry = JournalEntry(revision: 1, sessionID: "old-session", ownerIdentity: "claimed-owner",
                bootID: "previous-boot", generation: 1, operationID: "old-operation",
                intent: .restoreLidPolicy, disposition: .unresolved, continuousDeadlineNanos: 10)
            try journal.commit(entry, replacing: nil)
            let path = directory.appendingPathComponent("recovery.json")
            let bytes = try Data(contentsOf: path)
            let environment = TestEnvironment()
            environment.nowNanos = 5
            let executor = try InertRecoveryExecutor(directory: directory, environment: environment)
            let missingSocket = directory.deletingLastPathComponent().appendingPathComponent("missing.sock").path
            let pin = try CodeIdentityPin.currentProcess()
            _ = try executor.reconcile(brokerPath: missingSocket, serverPin: pin)
            if fault == "regression" { environment.nowNanos = 4 }
            if fault == "bootChanged" { environment.bootID = "another-boot" }
            if fault == "unavailable" { environment.unavailable = true }
            if fault == "disappeared" { try FileManager.default.removeItem(at: path) }
            let expected: BrokerFailure = fault == "regression" ? .clockRegressed :
                fault == "bootChanged" ? .bootChanged : fault == "unavailable" ? .environmentUnavailable : .journalDisappeared
            #expect(throws: expected) { try executor.reconcile(brokerPath: missingSocket, serverPin: pin) }
            environment.nowNanos = 6
            environment.bootID = "previous-boot"
            environment.unavailable = false
            if fault == "disappeared" {
                try bytes.write(to: path)
                #expect(chmod(path.path, 0o600) == 0)
            }
            #expect(throws: expected) { try executor.reconcile(brokerPath: missingSocket, serverPin: pin) }
            #expect(try journal.load() == entry)
        }
    }

    @Test(arguments: ["previousBoot", "expired"])
    func executorClassifiesOldIntentWithoutBrokerOrRearm(_ state: String) throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let environment = TestEnvironment()
            if state == "previousBoot" { environment.bootID = "current-boot" }
            else { environment.nowNanos = 1 }
            let executor = try InertRecoveryExecutor(directory: directory, environment: environment)
            let result = try executor.reconcile(brokerPath: "unused", serverPin: CodeIdentityPin.currentProcess())
            #expect(result.reason == (state == "previousBoot" ? "previousBootUnresolved" : "deadlineExpiredUnresolved"))
            #expect(result.revision == 2 && !result.protectionAvailable && !result.powerActuation)
            let saved = try #require(try journal.load())
            #expect(saved.intent == .restoreLidPolicy && saved.bootID == "previous-boot" && saved.disposition == .unresolved)
        }
    }

    @Test func executorPublicationUncertaintyCannotBecomeSuccessFromVisibleRestore() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let environment = TestEnvironment()
            let calls = PublicationFault(environment: environment, mode: "uncertain")
            let executor = try InertRecoveryExecutor(directory: directory, environment: environment, systemCalls: calls)
            let pin = try CodeIdentityPin.currentProcess()
            let missing = directory.deletingLastPathComponent().appendingPathComponent("missing.sock").path
            let expected = JournalFailure.publicationUncertain(operation: "publish", code: EIO)
            #expect(throws: expected) { try executor.reconcile(brokerPath: missing, serverPin: pin) }
            let visible = try #require(try journal.load())
            #expect(visible.revision == 2 && visible.intent == .restoreLidPolicy && visible.disposition == .unresolved)
            calls.mode = "healthy"
            #expect(throws: expected) { try executor.reconcile(brokerPath: missing, serverPin: pin) }
            #expect(try journal.load() == visible)
        }
    }

    @Test func recoveryRetriesContentionOnlyTowardUnresolvedIntent() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let executor = try InertRecoveryExecutor(directory: directory, environment: TestEnvironment())
            let pin = try CodeIdentityPin.currentProcess()
            let fd = Darwin.open(directory.appendingPathComponent(".journal.lock").path, O_RDWR | O_CLOEXEC)
            #expect(fd >= 0)
            defer { Darwin.close(fd) }
            #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
            let blocked = try executor.reconcile(brokerPath: "unused", serverPin: pin)
            #expect(blocked.reason == "journalBusyUnresolved" && blocked.revision == nil)
            #expect(!blocked.protectionAvailable && !blocked.powerActuation)
            #expect(flock(fd, LOCK_UN) == 0)
            let retried = try executor.reconcile(brokerPath: "unused", serverPin: pin)
            #expect(retried.reason == "journalContentionRecoveryUnresolved" && retried.revision == 2)
            let saved = try #require(try journal.load())
            #expect(saved.intent == .restoreLidPolicy && saved.disposition == .unresolved)
            let again = try executor.reconcile(brokerPath: "unused", serverPin: pin)
            #expect(again.reason == "alreadyUnresolved" && again.revision == 2)
        }
    }

    private final class TestEnvironment: BrokerEnvironment {
        var bootID = "previous-boot"
        var nowNanos: UInt64 = 0
        var unavailable = false
        func sample() throws -> BrokerClockSnapshot {
            if unavailable { throw BrokerFailure.environmentUnavailable }
            return BrokerClockSnapshot(bootID: bootID, nowNanos: nowNanos)
        }
    }

    @Test(arguments: ["regression", "bootChanged"])
    func clockDiscontinuityLatchesAndPreventsMonitorWrites(_ fault: String) throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let environment = TestEnvironment()
            environment.nowNanos = 5
            let broker = try RecoveryBroker(directory: directory,
                trustedMonitors: [CodeIdentityPin(executable: fixtureExecutable())], environment: environment)
            if fault == "regression" { environment.nowNanos = 4 }
            else { environment.bootID = "unexpected-boot" }
            let expected: BrokerFailure = fault == "regression" ? .clockRegressed : .bootChanged
            #expect(throws: expected) {
                try exchange(broker, directory: directory,
                    request: BrokerRequest(operation: .recordRestoreIntent, expectedRevision: 1))
            }
            environment.nowNanos = 6
            environment.bootID = "previous-boot"
            #expect(throws: expected) { try exchange(broker, directory: directory) }
            #expect(try journal.load() == savedIntent())
        }
    }

    @Test(arguments: ["sameBoot", "expired", "previousBoot"])
    func savedIntentIsClassifiedWithoutRearming(_ state: String) throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let environment = TestEnvironment()
            if state == "expired" { environment.nowNanos = 1 }
            if state == "previousBoot" { environment.bootID = "different-boot" }
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin(executable: fixtureExecutable())], environment: environment)
            let reply = try exchange(broker, directory: directory)
            let expected: ReconciliationReason = state == "expired" ? .deadlineExpired :
                state == "previousBoot" ? .previousBoot : .savedIntent
            #expect(reply.reconciliationReason == expected)
            #expect(reply.startup == .reconciliationRequired)
            #expect(!reply.powerActuation && !reply.protectionAvailable)
            #expect(try journal.load() == savedIntent())
        }
    }

    private func withSocketPair(_ body: (Int32, Int32) throws -> Void) throws {
        var sockets: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
            throw BrokerFailure.transport(errno)
        }
        defer { Darwin.close(sockets[0]); Darwin.close(sockets[1]) }
        try body(sockets[0], sockets[1])
    }

    @Test(arguments: [UInt32(0), 32_769, UInt32.max])
    func invalidFrameLengthIsRejectedBeforeBodyAllocation(_ size: UInt32) throws {
        try withDirectory { directory in
            let broker = try RecoveryBroker(directory: directory)
            try withSocketPair { server, client in
                var length = size.bigEndian
                #expect(withUnsafeBytes(of: &length) { send(client, $0.baseAddress, 4, 0) } == 4)
                #expect(throws: BrokerFailure.protocolViolation) { try broker.serveConnection(server) }
                let journal = try DurableRecoveryJournal(directory: directory)
                let loaded = try journal.load()
                #expect(loaded == nil)
            }
        }
    }

    @Test func partialHeaderDoesNotBlockForever() throws {
        try withDirectory { directory in
            let broker = try RecoveryBroker(directory: directory)
            try withSocketPair { server, client in
                var byte: UInt8 = 0
                #expect(send(client, &byte, 1, 0) == 1)
                let start = ContinuousClock.now
                #expect(throws: BrokerFailure.timeout) { try broker.serveConnection(server) }
                #expect(start.duration(to: .now) < .seconds(5))
            }
        }
    }

    @Test(arguments: ["version", "unknownOperation", "brokenJSON"])
    func authenticatedMalformedRequestCannotChangeSavedIntent(_ kind: String) throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin.currentProcess()])
            try withSocketPair { server, client in
                let json = kind == "version" ? #"{"version":2,"operation":"status"}"# :
                    kind == "unknownOperation" ? #"{"version":1,"operation":"enableLidOverride"}"# : "{"
                try FrameIO(fd: client).write(Data(json.utf8))
                if kind == "version" {
                    #expect(throws: BrokerFailure.protocolViolation) { try broker.serveConnection(server) }
                } else {
                    #expect(throws: DecodingError.self) { try broker.serveConnection(server) }
                }
                #expect(try journal.load() == savedIntent())
            }
        }
    }

    @Test func missingPreviouslyObservedIntentCannotClearReconciliation() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin(executable: fixtureExecutable())])
            try FileManager.default.removeItem(at: directory.appendingPathComponent("recovery.json"))
            let reply = try exchange(broker, directory: directory)
            #expect(reply.startup == .reconciliationRequired)
            #expect(!reply.powerActuation && !reply.protectionAvailable)
        }
    }

    @Test func corruptJournalPreventsStartup() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            try Data("{".utf8).write(to: directory.appendingPathComponent("recovery.json"))
            #expect(throws: JournalFailure.corrupt) { try RecoveryBroker(directory: directory) }
        }
    }

    @Test func oneExecutableCannotBeConfiguredForBothRoles() throws {
        try withDirectory { directory in
            let pin = try CodeIdentityPin(executable: fixtureExecutable())
            #expect(throws: BrokerFailure.ambiguousRoles) {
                try RecoveryBroker(directory: directory, trustedClients: [pin], trustedMonitors: [pin])
            }
        }
    }

    @Test func monitorRecordsIntentButNeverClaimsRestoration() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let broker = try RecoveryBroker(directory: directory,
                trustedMonitors: [CodeIdentityPin(executable: fixtureExecutable())])
            let reply = try exchange(broker, directory: directory,
                request: BrokerRequest(operation: .recordRestoreIntent, expectedRevision: 1))
            #expect(reply.accepted && reply.reason == "restoreIntentRecorded")
            #expect(reply.startup == .reconciliationRequired)
            #expect(!reply.powerActuation && !reply.protectionAvailable)
            let saved = try #require(try journal.load())
            #expect(saved.revision == 2 && saved.intent == .restoreLidPolicy)
            #expect(saved.disposition == .unresolved)
            #expect(saved.sessionID == "previous-session" && saved.bootID == "previous-boot")
            #expect(saved.ownerIdentity == "claimed-owner" && saved.generation == 7)
            #expect(saved.continuousDeadlineNanos == 1)
            let replay = try exchange(broker, directory: directory,
                request: BrokerRequest(operation: .recordRestoreIntent, expectedRevision: 1))
            #expect(!replay.accepted && replay.reason == "revisionConflict")
            #expect(try journal.load() == saved)
        }
    }

    @Test func statusClientCannotRecordARestoreIntent() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin(executable: fixtureExecutable())])
            let reply = try exchange(broker, directory: directory,
                request: BrokerRequest(operation: .recordRestoreIntent, expectedRevision: 1))
            #expect(!reply.accepted && reply.reason == "monitorRoleRequired")
            #expect(try journal.load() == savedIntent())
        }
    }

    @Test func explicitlyPinnedFixtureGetsOnlyNonActuatingStatus() throws {
        try withDirectory { directory in
            let pin = try CodeIdentityPin(executable: fixtureExecutable())
            let broker = try RecoveryBroker(directory: directory, trustedClients: [pin])
            let reply = try exchange(broker, directory: directory)
            #expect(reply.accepted && reply.reason == "status")
            #expect(reply.startup == .clean)
            #expect(!reply.powerActuation && !reply.protectionAvailable)
        }
    }

    @Test func clientRejectsIncorrectServerPinBeforeSendingARequest() throws {
        try withDirectory { directory in
            let broker = try RecoveryBroker(directory: directory,
                trustedClients: [CodeIdentityPin(executable: fixtureExecutable())])
            #expect(throws: BrokerFailure.transport(ECONNRESET)) {
                try exchange(broker, directory: directory,
                    serverPin: CodeIdentityPin(cdhash: String(repeating: "0", count: 40)))
            }
            #expect(try DurableRecoveryJournal(directory: directory).load() == nil)
        }
    }

    @Test func unpinnedSameUserClientCannotReadStatus() throws {
        try withDirectory { directory in
            let broker = try RecoveryBroker(directory: directory)
            let reply = try exchange(broker, directory: directory)
            #expect(!reply.accepted)
            #expect(reply.reason == "unauthorized")
            #expect(reply.startup == nil)
            #expect(!reply.powerActuation && !reply.protectionAvailable)
            #expect(try DurableRecoveryJournal(directory: directory).load() == nil)
        }
    }

    @Test func startupNeverRearmsSavedIntent() throws {
        try withDirectory { directory in
            let journal = try DurableRecoveryJournal(directory: directory)
            try journal.commit(savedIntent(), replacing: nil)
            let broker = try RecoveryBroker(directory: directory)
            #expect(broker.startup == .reconciliationRequired)
            #expect(try journal.load() == savedIntent())
        }
    }
}
