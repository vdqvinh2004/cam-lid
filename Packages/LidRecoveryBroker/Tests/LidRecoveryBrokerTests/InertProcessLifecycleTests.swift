import Foundation
import Darwin
import Testing
import LidRecoveryJournal
@_spi(TestInputs) @testable import LidRecoveryBroker

@Suite("Owned-process inert recovery — no host power", .serialized)
struct InertProcessLifecycleTests {
    private final class BundleLocator: NSObject {}

    private final class Harness {
        let root: URL
        let journal: URL
        let path: String
        let serverPin: CodeIdentityPin
        let server = Process()
        var client = Process()
        let monitor = Process()
        var input = Pipe()
        var output = Pipe()
        var owned: [Process] = []
        let clientURL: URL
        let monitorURL: URL
        let serverURL: URL

        init(root: URL) throws {
            self.root = root
            journal = root.appendingPathComponent("journal")
            path = root.appendingPathComponent("socket").path
            let bundle = Bundle(for: BundleLocator.self).bundleURL
            func executable(_ name: String) throws -> URL {
                for base in [bundle.deletingLastPathComponent(), bundle] {
                    let url = base.appendingPathComponent(name)
                    if FileManager.default.isExecutableFile(atPath: url.path) { return url }
                }
                throw BrokerFailure.transport(ENOENT)
            }
            clientURL = try executable("LidBrokerFixture")
            monitorURL = try executable("LidRecoveryMonitorFixture")
            serverURL = try executable("LidBrokerServerFixture")
            serverPin = try CodeIdentityPin(executable: serverURL)
        }

        func wait(_ seconds: Double = 5, until condition: () throws -> Bool) throws {
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(Int64(seconds * 1_000)))
            while ContinuousClock.now < deadline {
                do { if try condition() { return } }
                catch let failure as JournalFailure where failure == .busy { /* Observation is temporarily unavailable. */ }
                Thread.sleep(forTimeInterval: 0.01)
            }
            throw BrokerFailure.timeout
        }

        func start() throws {
            server.executableURL = serverURL
            server.arguments = [journal.path, path, try CodeIdentityPin(executable: clientURL).cdhash,
                try CodeIdentityPin(executable: monitorURL).cdhash, root.appendingPathComponent("server.ready").path]
            let errors = root.appendingPathComponent("server.stderr")
            guard FileManager.default.createFile(atPath: errors.path, contents: Data(),
                attributes: [.posixPermissions: 0o600]) else { throw BrokerFailure.transport(EIO) }
            let errorHandle = try FileHandle(forWritingTo: errors)
            defer { try? errorHandle.close() }
            server.standardError = errorHandle
            try server.run()
            owned.append(server)
            try wait { FileManager.default.fileExists(atPath: self.root.appendingPathComponent("server.ready").path) }
            try startClient()
        }

        func startClient() throws {
            client = Process()
            input = Pipe()
            output = Pipe()
            client.executableURL = clientURL
            client.arguments = [path, serverPin.cdhash, "stream"]
            client.standardInput = input
            client.standardOutput = output
            try client.run()
            owned.append(client)
        }

        func send(_ request: BrokerRequest) throws -> BrokerReply {
            var data = try JSONEncoder().encode(request)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
            let fd = output.fileHandleForReading.fileDescriptor
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            var bytes = Data()
            while ContinuousClock.now < deadline, bytes.count < 32_768 {
                var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let result = poll(&item, 1, 50)
                if result < 0, errno == EINTR { continue }
                guard result >= 0 else { throw BrokerFailure.transport(errno) }
                if result == 0 { continue }
                var byte: UInt8 = 0
                guard Darwin.read(fd, &byte, 1) == 1 else { throw BrokerFailure.transport(ECONNRESET) }
                if byte == 10 { return try JSONDecoder().decode(BrokerReply.self, from: bytes) }
                bytes.append(byte)
            }
            throw BrokerFailure.timeout
        }

        func startMonitor(pausing: String? = nil) throws {
            monitor.executableURL = monitorURL
            monitor.arguments = [journal.path, path, serverPin.cdhash,
                root.appendingPathComponent("monitor.json").path, root.appendingPathComponent("monitor.ready").path]
            if let pausing { monitor.arguments?.append(pausing) }
            try monitor.run()
            owned.append(monitor)
            try wait { FileManager.default.fileExists(atPath: self.root.appendingPathComponent("monitor.ready").path) }
            try wait { try self.observation()?.reason == "waiting" }
            if pausing != nil {
                try wait {
                    var info = siginfo_t()
                    guard waitid(P_PID, id_t(self.monitor.processIdentifier), &info,
                        WSTOPPED | WNOHANG | WNOWAIT) == 0 else { throw BrokerFailure.transport(errno) }
                    return info.si_pid == self.monitor.processIdentifier && info.si_code == CLD_STOPPED
                }
            }
        }

        func observation() throws -> InertRecoveryResult? {
            let url = root.appendingPathComponent("monitor.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode(InertRecoveryResult.self, from: Data(contentsOf: url))
        }

        func signal(_ process: Process, _ signal: Int32) throws {
            guard owned.contains(where: { $0 === process }), process.isRunning else {
                throw BrokerFailure.transport(ESRCH)
            }
            guard kill(process.processIdentifier, signal) == 0 else { throw BrokerFailure.transport(errno) }
        }

        func stop() {
            for process in owned.reversed() where process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
    }

    private func withHarness(_ body: (Harness) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cllife-\(UUID().uuidString.prefix(12))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = try Harness(root: root)
        defer { harness.stop() }
        try harness.start()
        try body(harness)
    }

    @Test func sameExecutableNewProcessCannotTakeOverOwnerLease() throws {
        try withHarness { harness in
            let admitted = try harness.send(BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 5_000_000_000, sessionDurationNanos: 10_000_000_000))
            let lease = try #require(admitted.lease)
            let firstPID = harness.client.processIdentifier
            try harness.signal(harness.client, SIGKILL)
            harness.client.waitUntilExit()
            try harness.startClient()
            #expect(harness.client.processIdentifier != firstPID)
            let takeover = try harness.send(BrokerRequest(operation: .renewInertLease,
                expectedRevision: 1, sessionID: lease.sessionID, generation: lease.generation,
                sequence: 2, durationNanos: 5_000_000_000))
            #expect(!takeover.accepted && takeover.reason == "invalidLeaseRequest")
            let stored = try #require(try DurableRecoveryJournal(directory: harness.journal).load())
            #expect(stored.revision == 1 && stored.ownerIdentity.contains("pid:\(firstPID):"))
        }
    }

    @Test func busyPollKeepsServerAliveWithoutRevivingLease() throws {
        try withHarness { harness in
            let admitted = try harness.send(BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 5_000_000_000, sessionDurationNanos: 10_000_000_000))
            let lease = try #require(admitted.lease)
            let journal = try DurableRecoveryJournal(directory: harness.journal)
            let original = try journal.load()
            let fd = Darwin.open(harness.journal.appendingPathComponent(".journal.lock").path, O_RDWR | O_CLOEXEC)
            try #require(fd >= 0)
            defer { flock(fd, LOCK_UN); Darwin.close(fd) }
            try harness.wait { flock(fd, LOCK_EX | LOCK_NB) == 0 }
            try harness.wait {
                let errors = try String(contentsOf: harness.root.appendingPathComponent("server.stderr"), encoding: .utf8)
                return !harness.server.isRunning || errors.contains("owned broker poll deferred: busy")
            }
            try #require(harness.server.isRunning)
            try #require(flock(fd, LOCK_UN) == 0)
            let renewed = try harness.send(BrokerRequest(operation: .renewInertLease,
                expectedRevision: 1, sessionID: lease.sessionID, generation: lease.generation,
                sequence: 2, durationNanos: 1_000_000_000))
            let clock = try SystemBrokerEnvironment().sample()
            try #require(clock.nowNanos < lease.deadlineNanos)
            #expect(!renewed.accepted && renewed.lease == nil)
            #expect(!renewed.powerActuation && !renewed.protectionAvailable)
            let readmitted = try harness.send(BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: 1_000_000_000, sessionDurationNanos: 10_000_000_000))
            #expect(!readmitted.accepted && readmitted.lease == nil)
            #expect(readmitted.startup == .reconciliationRequired)
            #expect(!readmitted.powerActuation && !readmitted.protectionAvailable)
            #expect(try journal.load() == original)
        }
    }

    @Test(arguments: ["brokerKill", "brokerStop", "lockedBrokerStop", "clientKill", "clientStop", "missedRenewal", "monitorStop", "monitorStopLocked", "jointStop"])
    func processFailuresLeaveUnresolvedIntentNotRestoration(_ fault: String) throws {
        try withHarness { harness in
            let longLease = fault == "brokerKill" || fault == "brokerStop" || fault == "lockedBrokerStop"
            let admitted = try harness.send(BrokerRequest(operation: .admitInertLease,
                sequence: 1, durationNanos: longLease ? 5_000_000_000 : 2_000_000_000,
                sessionDurationNanos: 10_000_000_000))
            let lease = try #require(admitted.lease)
            #expect(admitted.accepted && !admitted.protectionAvailable && !admitted.powerActuation)
            let publishedBeforePause = try Data(contentsOf: harness.journal.appendingPathComponent("recovery.json"))
            let pause = fault == "monitorStopLocked" ? "withJournal" :
                (fault == "monitorStop" || fault == "jointStop" ? "outsideJournal" : nil)
            try harness.startMonitor(pausing: pause)
            if fault == "brokerKill" { try harness.signal(harness.server, SIGKILL) }
            if fault == "brokerStop" { try harness.signal(harness.server, SIGSTOP) }
            if fault == "clientKill" { try harness.signal(harness.client, SIGKILL) }
            if fault == "clientStop" { try harness.signal(harness.client, SIGSTOP) }
            if fault == "jointStop" {
                try harness.signal(harness.server, SIGSTOP)
                Thread.sleep(forTimeInterval: 2.2)
                // A paused actor may own the lock; observe the atomic envelope without acquiring it.
                #expect(try Data(contentsOf: harness.journal.appendingPathComponent("recovery.json")) == publishedBeforePause)
                #expect(try harness.observation()?.reason == "waiting")
                try harness.signal(harness.monitor, SIGCONT)
            }
            let journal = try DurableRecoveryJournal(directory: harness.journal)
            var brokerResumed = false
            if fault == "monitorStopLocked" {
                try harness.wait {
                    let clock = try SystemBrokerEnvironment().sample()
                    return clock.nowNanos >= lease.deadlineNanos
                }
                #expect(throws: JournalFailure.busy) { try journal.load() }
                #expect(try Data(contentsOf: harness.journal.appendingPathComponent("recovery.json")) == publishedBeforePause)
                try harness.wait {
                    let errors = try String(contentsOf: harness.root.appendingPathComponent("server.stderr"), encoding: .utf8)
                    return errors.contains("owned broker poll deferred: busy")
                }
                #expect(harness.server.isRunning && harness.monitor.isRunning)
                #expect(try harness.observation()?.reason == "waiting")
                try harness.signal(harness.monitor, SIGCONT)
            }
            if fault == "lockedBrokerStop" {
                try Data("pause".utf8).write(to: harness.root.appendingPathComponent("lock.trigger"), options: .atomic)
                try harness.wait { FileManager.default.fileExists(atPath: harness.root.appendingPathComponent("lock.ready").path) }
                try harness.wait { try harness.observation()?.reason == "journalBusyUnresolved" }
                #expect(throws: JournalFailure.busy) { try journal.load() }
                let blocked = try #require(try harness.observation())
                #expect(blocked.revision == nil && !blocked.protectionAvailable && !blocked.powerActuation)
                try harness.signal(harness.server, SIGCONT)
                brokerResumed = true
            }
            if fault == "brokerStop" || fault == "jointStop" {
                try harness.wait(6) {
                    guard let observation = try harness.observation() else { return false }
                    return observation.reason != "waiting" && observation.reason != "noRecord"
                }
                if let observation = try harness.observation(),
                   ["journalBusyUnresolved", "journalConflictUnresolved"].contains(observation.reason) {
                    try harness.signal(harness.server, SIGCONT)
                    brokerResumed = true
                }
            }
            try harness.wait(6) { try journal.load()?.intent == .restoreLidPolicy }
            let record = try #require(try journal.load())
            #expect(record.revision == 2 && record.disposition == .unresolved)
            #expect(record.sessionID == lease.sessionID && record.generation == lease.generation)
            #expect(record.continuousDeadlineNanos == lease.deadlineNanos)
            if fault != "monitorStop" {
                try harness.wait(6) {
                    guard let observation = try harness.observation() else { return false }
                    return observation.revision == 2 && observation.reason != "waiting"
                }
                let observation = try #require(try harness.observation())
                #expect(!observation.powerActuation && !observation.protectionAvailable)
            } else {
                #expect(try harness.observation()?.reason == "waiting")
            }
            if fault == "brokerStop" || fault == "lockedBrokerStop" || fault == "jointStop" || fault == "monitorStopLocked" {
                if fault != "monitorStopLocked", !brokerResumed { try harness.signal(harness.server, SIGCONT) }
                let late = try harness.send(BrokerRequest(operation: .renewInertLease,
                    expectedRevision: 1, sessionID: lease.sessionID, generation: lease.generation,
                    sequence: 2, durationNanos: 5_000_000_000))
                #expect(!late.accepted && late.lease == nil)
                #expect(try journal.load() == record)
            }
        }
    }
}
