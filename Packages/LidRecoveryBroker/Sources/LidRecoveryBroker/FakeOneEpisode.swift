import Foundation
import Darwin
import LidRecoveryJournal

// Fixed experimental flow. Default recorder is fake; explicit OS boundary never comes from IPC.
@_spi(TestInputs)
public struct FakeEpisode: Codable, Equatable, Sendable {
    public let bootID: String
    public let sessionID: String
    public let generation: UInt64
    public let operationID: String
    public let deadline: UInt64

    public init(budget: UInt64 = 15_000_000_000) throws {
        let clock = try SystemBrokerEnvironment().sample()
        guard budget > 0, budget <= 30_000_000_000 else { throw BrokerFailure.protocolViolation }
        let end = clock.nowNanos.addingReportingOverflow(budget)
        guard !end.overflow else { throw BrokerFailure.protocolViolation }
        bootID = clock.bootID
        sessionID = UUID().uuidString
        generation = UInt64.random(in: 1...UInt64.max)
        operationID = UUID().uuidString
        deadline = end.partialValue
    }

    func check(_ clock: BrokerClockSnapshot) throws {
        guard UUID(uuidString: bootID) != nil, UUID(uuidString: sessionID) != nil,
              UUID(uuidString: operationID) != nil, generation > 0 else { throw BrokerFailure.protocolViolation }
        guard clock.bootID == bootID else { throw BrokerFailure.bootChanged }
        guard clock.nowNanos < deadline, deadline - clock.nowNanos <= 30_000_000_000 else {
            throw BrokerFailure.leaseExpired
        }
    }
}

@_spi(TestInputs)
public struct FakeEpisodeRequest: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case readiness, completion, stop, observe, writerObserve }
    public let kind: Kind
    public let episode: FakeEpisode
    public let challenge: String
    public let executionMode: EpisodeExecutionMode
    public let enableResult: EpisodeLidCallResult?
    public init(_ kind: Kind, episode: FakeEpisode, executionMode: EpisodeExecutionMode = .simulated,
                enableResult: EpisodeLidCallResult? = nil) {
        self.kind = kind; self.episode = episode; challenge = UUID().uuidString
        self.executionMode = executionMode; self.enableResult = enableResult
    }
}

@_spi(TestInputs)
public struct FakeEpisodeReply: Codable, Sendable {
    public let reason: String
    public let episode: FakeEpisode
    public let challenge: String
    public let writerOwner: String?
    public let simulatedClears: Int
    public let executionMode: EpisodeExecutionMode
    public let enableResult: EpisodeLidCallResult?
    public let clearResult: EpisodeLidCallResult?
    public let clearAttempted: Bool
    public let completionRetained: Bool
    public let safetyRefused: Bool
    public let powerActuation: Bool?
    public let protectionAvailable: Bool
}

@_spi(TestInputs)
public enum FakeEpisodeConnection {
    static func authenticated(path: String, monitorPin: CodeIdentityPin,
                              request: FakeEpisodeRequest) throws -> (FakeEpisodeReply, String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BrokerFailure.transport(errno) }
        defer { Darwin.close(fd) }
        var address = try socketAddress(path)
        let result = withUnsafePointer(to: &address) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw BrokerFailure.transport(errno) }
        let peer = try SocketPeer(fd: fd)
        guard peer.pin == monitorPin else { throw BrokerFailure.authentication(EACCES) }
        let io = FrameIO(fd: fd)
        try io.write(JSONEncoder().encode(request))
        let reply = try JSONDecoder().decode(FakeEpisodeReply.self, from: io.read())
        guard reply.episode == request.episode, reply.challenge == request.challenge,
              reply.executionMode == request.executionMode, !reply.protectionAvailable,
              request.executionMode != .simulated || reply.powerActuation == false else {
            throw BrokerFailure.protocolViolation
        }
        return (reply, peer.ownerIdentity)
    }

    public static func exchange(path: String, monitorPin: CodeIdentityPin,
                                request: FakeEpisodeRequest) throws -> FakeEpisodeReply {
        try authenticated(path: path, monitorPin: monitorPin, request: request).0
    }
}

/// Caller schedules this journal-only monitor independently; receipt memory never reloads from disk.
@_spi(TestInputs)
public final class FakeEpisodeMonitor {
    private let episode: FakeEpisode
    private let writerPin: CodeIdentityPin
    private let governorPin: CodeIdentityPin
    private let journal: DurableRecoveryJournal
    private let environment: any BrokerEnvironment
    private var lastClock: BrokerClockSnapshot
    private var owner: String?
    private var retainedCompletion = false
    private var terminal = false
    private var storageFault = false
    private var simulatedClears = 0
    private let calls: any OneEpisodePowerCalls
    private let safetySource: (any EpisodeSafetySource)?
    private var enableResult: EpisodeLidCallResult?
    private var clearResult: EpisodeLidCallResult?
    private var clearAttempted = false
    private var safetyRefused = false

    public init(episode: FakeEpisode, directory: URL, writerPin: CodeIdentityPin,
                governorPin: CodeIdentityPin, environment: (any BrokerEnvironment)? = nil,
                calls: any OneEpisodePowerCalls = FakeEpisodeCalls(),
                safetySource: (any EpisodeSafetySource)? = nil) throws {
        guard writerPin != governorPin, writerPin != (try CodeIdentityPin.currentProcess()),
              governorPin != (try CodeIdentityPin.currentProcess()) else { throw BrokerFailure.ambiguousRoles }
        self.episode = episode; self.writerPin = writerPin; self.governorPin = governorPin
        guard calls.executionMode == .simulated || safetySource != nil else {
            throw BrokerFailure.environmentUnavailable
        }
        self.calls = calls; self.safetySource = safetySource
        let environment = environment ?? SystemBrokerEnvironment()
        self.environment = environment
        lastClock = try environment.sample()
        try episode.check(lastClock)
        journal = try DurableRecoveryJournal(directory: directory)
        guard try journal.load() == nil else { throw BrokerFailure.protocolViolation }
    }

    private func sample() throws -> BrokerClockSnapshot {
        let clock = try environment.sample()
        guard clock.bootID == lastClock.bootID else { throw BrokerFailure.bootChanged }
        guard clock.nowNanos >= lastClock.nowNanos else { throw BrokerFailure.clockRegressed }
        lastClock = clock
        return clock
    }

    private func bound(_ record: JournalEntry) -> Bool {
        record.sessionID == episode.sessionID && record.bootID == episode.bootID &&
            record.generation == episode.generation && record.continuousDeadlineNanos == episode.deadline &&
            record.ownerIdentity == owner
    }

    private func restoreIfEligible() throws {
        guard terminal, retainedCompletion, !storageFault, !clearAttempted else { return }
        guard let record = try journal.load(), bound(record), record.operationID == episode.operationID,
              record.revision == 2, record.intent == .enableLidOverride,
              record.disposition == .acknowledged else { throw BrokerFailure.protocolViolation }
        try journal.commit(restoreIntent(after: record), replacing: record.revision)
        clearAttempted = true
        clearResult = try calls.setLid(enabled: false)
        if calls.executionMode == .simulated, clearResult?.successfulSelectorReturn == true {
            simulatedClears += 1
        }
    }

    private func safetyAllows(_ clock: BrokerClockSnapshot, stage: EpisodeSafetyStage) -> Bool {
        let allowed = safetySource?.allows(clock, stage: stage) ?? (calls.executionMode == .simulated)
        safetyRefused = safetyRefused || !allowed
        return allowed
    }

    public func poll() {
        do {
            let clock = try sample()
            if clock.nowNanos >= episode.deadline || (!terminal && !safetyAllows(clock, stage: .monitoring)) {
                terminal = true
            }
            try restoreIfEligible()
        } catch { terminal = true; storageFault = true }
    }

    public func serveConnection(_ fd: Int32) throws {
        let peer = try SocketPeer(fd: fd)
        guard peer.pin == writerPin || peer.pin == governorPin else { throw BrokerFailure.authentication(EACCES) }
        let io = FrameIO(fd: fd)
        let request = try JSONDecoder().decode(FakeEpisodeRequest.self, from: io.read())
        guard request.episode == episode, UUID(uuidString: request.challenge) != nil,
              request.executionMode == calls.executionMode else {
            throw BrokerFailure.protocolViolation
        }
        let writerOperation = request.kind == .readiness || request.kind == .completion || request.kind == .writerObserve
        guard peer.pin == (writerOperation ? writerPin : governorPin) else {
            throw BrokerFailure.authentication(EACCES)
        }
        var reason = "unresolved"
        do {
            let clock = try sample()
            guard !storageFault else { throw BrokerFailure.protocolViolation }
            if clock.nowNanos >= episode.deadline { terminal = true }
            switch request.kind {
            case .readiness:
                try episode.check(clock)
                guard !terminal, !retainedCompletion, !storageFault,
                      safetyAllows(clock, stage: .beforeEnable) else { throw BrokerFailure.protocolViolation }
                guard owner == nil || owner == peer.ownerIdentity else { throw BrokerFailure.authentication(EACCES) }
                owner = peer.ownerIdentity
                reason = "ready"
            case .completion:
                guard !storageFault, !retainedCompletion, owner == peer.ownerIdentity,
                      let result = request.enableResult else { throw BrokerFailure.protocolViolation }
                enableResult = result
                guard result.successfulSelectorReturn, let record = try journal.load(), bound(record),
                      record.operationID == episode.operationID, record.intent == .enableLidOverride,
                      record.disposition == .pending, record.revision == 1 else { throw BrokerFailure.protocolViolation }
                let completed = JournalEntry(revision: 2, sessionID: record.sessionID,
                    ownerIdentity: record.ownerIdentity, bootID: record.bootID, generation: record.generation,
                    operationID: record.operationID, intent: .enableLidOverride, disposition: .acknowledged,
                    continuousDeadlineNanos: record.continuousDeadlineNanos)
                try journal.commit(completed, replacing: record.revision)
                retainedCompletion = true
                reason = "completionRetained"
            case .stop: terminal = true
            case .observe: break
            case .writerObserve:
                guard owner == peer.ownerIdentity else { throw BrokerFailure.authentication(EACCES) }
                reason = terminal ? "terminal" : "active"
            }
            try restoreIfEligible()
            if clearAttempted {
                reason = clearResult?.successfulSelectorReturn == true ?
                    (calls.executionMode == .simulated ? "simulatedClearReturned" : "nativeClearCallReturned") : "clearUnresolved"
            }
        } catch { terminal = true; storageFault = true; reason = "unresolved" }
        let observedNativeDispatch: Bool? = calls.executionMode == .simulated ? false :
            ((enableResult?.selectorWasDispatched == true || clearResult?.selectorWasDispatched == true) ? true : nil)
        let reply = FakeEpisodeReply(reason: reason, episode: episode, challenge: request.challenge,
            writerOwner: owner, simulatedClears: simulatedClears, executionMode: calls.executionMode,
            enableResult: enableResult, clearResult: clearResult, clearAttempted: clearAttempted,
            completionRetained: retainedCompletion, safetyRefused: safetyRefused,
            powerActuation: observedNativeDispatch, protectionAvailable: false)
        try io.write(JSONEncoder().encode(reply))
    }
}

/// Concrete recorder: hooks are fake OS-boundary faults/delays, never IPC authentication overrides.
@_spi(TestInputs)
public final class FakeEpisodeCalls: OneEpisodePowerCalls, @unchecked Sendable {
    public enum Event: String, Codable, Sendable { case acquire, enable, release, clear }
    public let executionMode: EpisodeExecutionMode = .simulated
    private let lock = NSLock()
    private var recorded: [Event] = []
    private var timeout: UInt64?
    private let acquired: @Sendable () throws -> Void
    private let enteringEnable: @Sendable () throws -> Void
    private let returnedEnable: @Sendable () throws -> Void

    public init(acquired: @escaping @Sendable () throws -> Void = {},
                enteringEnable: @escaping @Sendable () throws -> Void = {},
                returnedEnable: @escaping @Sendable () throws -> Void = {}) {
        self.acquired = acquired; self.enteringEnable = enteringEnable; self.returnedEnable = returnedEnable
    }
    public var events: [Event] { lock.withLock { recorded } }
    public var requestedTimeout: UInt64? { lock.withLock { timeout } }
    private final class Assertion: EpisodeIdleAssertion, @unchecked Sendable {
        let calls: FakeEpisodeCalls
        init(_ calls: FakeEpisodeCalls) { self.calls = calls }
        func release() -> Int32 {
            calls.lock.withLock { calls.recorded.append(.release) }
            return 0 // Simulated creator-local resource, no OS identifier.
        }
    }
    public func acquire(remaining: UInt64) throws -> any EpisodeIdleAssertion {
        guard remaining > 0, remaining <= 30_000_000_000 else { throw BrokerFailure.leaseExpired }
        lock.withLock { recorded.append(.acquire); timeout = remaining }
        try acquired()
        return Assertion(self)
    }
    public func setLid(enabled: Bool) throws -> EpisodeLidCallResult {
        if enabled {
            try enteringEnable()
            lock.withLock { recorded.append(.enable) }
            try returnedEnable()
        } else { lock.withLock { recorded.append(.clear) } }
        return .returned(selectorCode: 0, serviceReleaseCode: 0, connectionCloseCode: 0)
    }
}

/// One caller executes run; another may latch Stop. Control lock is never held across I/O/hooks.
@_spi(TestInputs)
public final class FakeEpisodeWriter: @unchecked Sendable {
    private let episode: FakeEpisode
    private let directory: URL
    private let path: String
    private let monitorPin: CodeIdentityPin
    private let calls: any OneEpisodePowerCalls
    private let environment: any BrokerEnvironment
    private let lock = NSLock()
    private var terminal = false
    private var consumed = false
    private var assertion: (any EpisodeIdleAssertion)?
    private var releaseReturn: Int32?
    private var releaseError = false
    private var phase = "new"
    private var lastClock: BrokerClockSnapshot?
    private let safety: @Sendable (BrokerClockSnapshot) throws -> Bool

    public init(episode: FakeEpisode, directory: URL, path: String, monitorPin: CodeIdentityPin,
                calls: any OneEpisodePowerCalls, environment: (any BrokerEnvironment)? = nil,
                safety: (@Sendable (BrokerClockSnapshot) throws -> Bool)? = nil,
                safetySource: (any EpisodeSafetySource)? = nil) {
        self.episode = episode; self.directory = directory; self.path = path; self.monitorPin = monitorPin
        self.calls = calls; self.environment = environment ?? SystemBrokerEnvironment()
        self.safety = { clock in
            if let safetySource { return safetySource.allows(clock, stage: .beforeEnable) }
            // Legacy Boolean hook belongs only to recorder tests; cannot admit native SDK execution.
            guard calls.executionMode == .simulated else { return false }
            return try safety?(clock) ?? true
        }
    }
    public var observation: String { lock.withLock { phase } }
    public var stopped: Bool { lock.withLock { terminal } }
    public var assertionReleaseReturn: Int32? { lock.withLock { releaseReturn } }
    public var assertionReleaseFailed: Bool { lock.withLock { releaseError } }

    private func release(_ owned: any EpisodeIdleAssertion) {
        do {
            let code = try owned.release()
            lock.withLock { releaseReturn = code; releaseError = code != 0 }
        } catch { lock.withLock { releaseError = true } }
    }

    public func stop() {
        let id = lock.withLock { () -> (any EpisodeIdleAssertion)? in
            terminal = true
            let id = assertion; assertion = nil
            return id
        }
        if let id { release(id) }
    }

    private func sample() throws -> BrokerClockSnapshot {
        let clock = try environment.sample()
        if let previous = lastClock {
            guard clock.bootID == previous.bootID else { throw BrokerFailure.bootChanged }
            guard clock.nowNanos >= previous.nowNanos else { throw BrokerFailure.clockRegressed }
        }
        lastClock = clock
        try episode.check(clock)
        return clock
    }

    private func ready() throws -> (FakeEpisodeReply, String, UInt64) {
        let before = try sample()
        let (reply, owner) = try FakeEpisodeConnection.authenticated(path: path, monitorPin: monitorPin,
            request: FakeEpisodeRequest(.readiness, episode: episode, executionMode: calls.executionMode))
        let after = try sample()
        guard reply.reason == "ready", reply.writerOwner != nil,
              after.nowNanos - before.nowNanos <= 1_000_000_000 else { throw BrokerFailure.timeout }
        return (reply, owner, after.nowNanos)
    }

    /// Prepared study caller must stop explicitly at terminal status/safety/deadline.
    @discardableResult public func runRetainingAssertion() -> String { run(retainOnCompletion: true) }

    @discardableResult public func run() -> String { run(retainOnCompletion: false) }

    private func run(retainOnCompletion: Bool) -> String {
        let first = lock.withLock { () -> Bool in
            guard !consumed, !terminal else { return false }
            consumed = true; phase = "preparing"
            return true
        }
        guard first else { return "refused" }
        var completed = false
        defer { if !retainOnCompletion || !completed { stop() } }
        do {
            guard try safety(sample()) else { throw BrokerFailure.protocolViolation }
            let (initial, monitorOwner, _) = try ready()
            let journal = try DurableRecoveryJournal(directory: directory)
            guard try journal.load() == nil else { throw BrokerFailure.protocolViolation }
            guard let writerOwner = initial.writerOwner else { throw BrokerFailure.protocolViolation }
            let intent = JournalEntry(revision: 1, sessionID: episode.sessionID,
                ownerIdentity: writerOwner, bootID: episode.bootID, generation: episode.generation,
                operationID: episode.operationID, intent: .enableLidOverride, disposition: .pending,
                continuousDeadlineNanos: episode.deadline)
            try journal.commit(intent, replacing: nil)
            let clock = try sample()
            guard !stopped else { throw BrokerFailure.leaseExpired }
            let id = try calls.acquire(remaining: episode.deadline - clock.nowNanos)
            let keep = lock.withLock { () -> Bool in
                guard !terminal else { return false }
                assertion = id
                return true
            }
            guard keep else {
                release(id)
                throw BrokerFailure.leaseExpired
            }
            let (fresh, currentMonitor, received) = try ready()
            let dispatchClock = try sample()
            guard fresh.writerOwner == initial.writerOwner, currentMonitor == monitorOwner,
                  try safety(dispatchClock) else { throw BrokerFailure.protocolViolation }
            // Safety reads can stall; resample before the control-only dispatch transition.
            let afterSafety = try sample()
            guard afterSafety.nowNanos - received <= 1_000_000_000 else { throw BrokerFailure.timeout }
            let authorized = lock.withLock { () -> Bool in
                guard !terminal else { return false }
                phase = "enableInFlight"
                return true
            }
            guard authorized else { throw BrokerFailure.leaseExpired }
            let enabled = try calls.setLid(enabled: true)
            let (receipt, completingMonitor) = try FakeEpisodeConnection.authenticated(path: path, monitorPin: monitorPin,
                request: FakeEpisodeRequest(.completion, episode: episode, executionMode: calls.executionMode,
                    enableResult: enabled))
            guard enabled.successfulSelectorReturn, completingMonitor == monitorOwner,
                receipt.reason == "completionRetained" || receipt.reason == "simulatedClearReturned" ||
                receipt.reason == "nativeClearCallReturned" else { throw BrokerFailure.protocolViolation }
            lock.withLock { phase = "completionRetained" }
            completed = true
            return "completionRetained"
        } catch {
            lock.withLock { phase = "unresolved" }
            return "unresolved"
        }
    }
}
