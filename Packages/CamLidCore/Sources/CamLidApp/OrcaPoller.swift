import Foundation
import CamLidCore
import Darwin
import CryptoKit

struct OrcaMetadataSnapshot: Sendable {
    let statuses: [OrcaUIStatus]
    let queryStartedAt: Double
    let receivedAt: Double
}

public enum OrcaPollError: Error, Sendable {
    case unavailable, timeout, tooLarge, remote, invalid

    /// Capability, not version: any Orca whose replies still match the decoded
    /// contract below is accepted. A reshaped reply fails decode as `.invalid`;
    /// the version string gates nothing.

    /// User-facing text. The raw case name must never reach the UI.
    public var userMessage: String {
        switch self {
        case .unavailable: "Orca unavailable"
        case .timeout: "Orca timed out"
        case .tooLarge: "Orca output too large"
        case .remote: "Orca remote target ignored"
        case .invalid: "Orca reply invalid"
        }
    }
}

/// Owner-approved read-only runtime source. Mixed JSON is transient, never logged or exported.
public struct OrcaPoller: Sendable {
    public static let bundledExecutable = URL(fileURLWithPath: "/Applications/Orca.app/Contents/Resources/bin/orca")
    public let executable: URL
    public init(executable: URL = Self.bundledExecutable) { self.executable = executable }
    public func poll(consent: Bool = false) throws -> [OrcaWorktreeRow] {
        let bytes = try readBytes(consent: consent)
        return try Self.decode(status: bytes.status, worktrees: bytes.worktrees)
    }
    private func readBytes(consent: Bool) throws -> (status: Data, worktrees: Data) {
        guard consent else { throw IPCError.policyDenied("orcaMetadataConsentRequired") }
        // No version pin: a missing or reshaped CLI fails below as unavailable/invalid.
        let status = try Self.run(executable: executable, arguments: ["status", "--json"])
        let worktrees = try Self.run(executable: executable, arguments: ["worktree", "ps", "--limit", "20", "--json"])
        return (status, worktrees)
    }
    func snapshot(consent: Bool, clock: () -> Double = { ContinuousTime.now }) throws -> OrcaMetadataSnapshot {
        let started = clock()
        guard started.isFinite else { throw OrcaPollError.invalid }
        let bytes = try readBytes(consent: consent)
        let rows = try Self.decode(status: bytes.status, worktrees: bytes.worktrees)
        let runtime = try JSONDecoder().decode(StatusEnvelope.self, from: bytes.status).result.runtime.runtimeId
        let statuses = rows.map { row in
            // Opaque runtime/pane identity only; never persist a provider title or raw pane key.
            let identity = Data((runtime + "\u{0}" + row.sessionID).utf8)
            let hash = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
            let state: OrcaUIState
            if row.restoredUnconfirmed { state = .unknown }
            else {
                state = switch row.agentState {
                case "working": .working
                case "waiting": .waiting
                case "idle": .idle
                default: .unknown
                }
            }
            return OrcaUIStatus(id: "meta-" + hash, state: state)
        }
        let received = clock()
        guard received.isFinite, received >= started, received - started <= 4.5 else { throw OrcaPollError.timeout }
        return OrcaMetadataSnapshot(statuses: statuses, queryStartedAt: started, receivedAt: received)
    }
    public static func decode(status: Data, worktrees: Data) throws -> [OrcaWorktreeRow] {
        guard status.count <= 65_536, worktrees.count <= 65_536 else { throw OrcaPollError.tooLarge }
        let state = try JSONDecoder().decode(StatusEnvelope.self, from: status)
        guard state.ok, state.result.target.kind == "local" else { throw OrcaPollError.remote }
        // Version-agnostic: the reply shape is the contract. Any version whose
        // reply still decodes is accepted; a reshaped reply throws below as invalid.
        guard state.result.runtime.reachable else { throw OrcaPollError.unavailable }
        guard !state.result.runtime.runtimeId.isEmpty, state.result.runtime.runtimeId.utf8.count <= 256 else {
            throw OrcaPollError.invalid
        }
        let response = try JSONDecoder().decode(WorktreeEnvelope.self, from: worktrees)
        guard response.ok, !response.result.truncated,
            response._meta.runtimeId == state.result.runtime.runtimeId else { throw OrcaPollError.invalid }
        var output: [OrcaWorktreeRow] = []
        var panes: Set<String> = []
        for workspace in response.result.worktrees where workspace.hostId == "local" {
            for row in workspace.agents {
                guard output.count < 20 else { throw OrcaPollError.tooLarge }
                guard !row.paneKey.isEmpty, row.paneKey.utf8.count <= 256, panes.insert(row.paneKey).inserted else {
                    throw OrcaPollError.invalid
                }
                // Orca done is a settled pane/turn, not success or pane death.
                // Keep its identity reusable for the next prompt.
                let state = row.restoredUnconfirmed == true || row.interrupted == true ? "unknown"
                    : row.state == "done" ? "idle" : ["working", "waiting", "idle", "unknown"].contains(row.state) ? row.state : "unknown"
                output.append(OrcaWorktreeRow(sessionID: row.paneKey, runID: "main", host: "local",
                    restoredUnconfirmed: row.restoredUnconfirmed ?? false, agentState: state))
            }
        }
        return output
    }
    static func run(executable: URL, arguments: [String], timeout: Double = 2, maximumBytes: Int = 65_536) throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw OrcaPollError.unavailable }
        let process = Process()
        let pipe = Pipe()
        let output = BoundedProcessOutput(maximum: max(0, min(maximumBytes, 65_536)))
        let ended = DispatchSemaphore(value: 0)
        let eof = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = arguments
        // Do not inherit agent caller identity, remote routing, Node injection or provider secrets.
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { _ in ended.signal() }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            output.append(data)
            if data.isEmpty { handle.readabilityHandler = nil; eof.signal() }
        }
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        try process.run()
        guard ended.wait(timeout: .now() + timeout) == .success else {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = ended.wait(timeout: .now() + 0.2)
            throw OrcaPollError.timeout
        }
        // A descendant retaining stdout must not strand the collector.
        guard eof.wait(timeout: .now() + 0.2) == .success else { throw OrcaPollError.timeout }
        guard process.terminationStatus == 0 else { throw OrcaPollError.unavailable }
        return try output.value()
    }
}

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var oversized = false
    private let maximum: Int
    init(maximum: Int) { self.maximum = maximum }
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        if bytes.count + data.count > maximum { oversized = true; return }
        if !oversized { bytes.append(data) }
    }
    func value() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard !oversized else { throw OrcaPollError.tooLarge }
        return bytes
    }
}

private struct StatusEnvelope: Decodable {
    let ok: Bool; let result: StatusResult
    struct StatusResult: Decodable {
        let target: Target; let runtime: Runtime
        struct Target: Decodable { let kind: String }
        struct Runtime: Decodable { let appVersion: String; let reachable: Bool; let runtimeId: String }
    }
}
private struct WorktreeEnvelope: Decodable {
    let ok: Bool; let result: ResultRows; let _meta: Meta
    struct Meta: Decodable { let runtimeId: String }
    struct ResultRows: Decodable { let worktrees: [Workspace]; let truncated: Bool }
    struct Workspace: Decodable { let hostId: String; let agents: [Row] }
    struct Row: Decodable {
        let paneKey: String; let state: String
        let interrupted: Bool?; let restoredUnconfirmed: Bool?
    }
}
