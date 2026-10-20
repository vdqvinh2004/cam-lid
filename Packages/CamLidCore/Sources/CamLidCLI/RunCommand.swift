import Foundation
import CamLidCore

/// Enrolled command wrapper (T021). Holds one enrollment per live child in an
/// `EnrollmentSet` (max 20, never evicts existing work) and releases it when
/// the direct child exits.
///
/// Detached-process rule: a spawned-and-detached child (double-fork daemon)
/// exiting promptly is NOT completion evidence. The wrapper observes only the
/// direct child, so `ChildResult.enrolled` reports whether the run was
/// protection-enrolled and `completionEvidence` is always `directChildOnly`.
/// Callers must treat a 0 exit from a spawner as enrollment-held-unknown for
/// the detached work, never as task completion.
///
/// Child I/O: the child inherits stdio by design (interactive agents need a
/// live terminal). The wrapper never captures or interleaves child stdout;
/// the machine-readable result JSON is printed by `camlid` itself at
/// completion, after the child has exited, so interactive output and the
/// result envelope never share a byte stream concurrently.
///
/// Exit mapping: normal exit returns the status verbatim. Signaled termination
/// maps to shell convention 128+signo (SIGTERM -> 143) via
/// `shellExitStatus`. Launch failure is never success: it throws
/// `RunError.launchFailed` with exitMapping 127 (not found) or 126 (found but
/// not launchable), matching shell convention for the thin `camlid`
/// executable to re-emit. Bare commands (no slash) resolve via PATH through
/// `/usr/bin/env`.
public struct RunCommand: Sendable {
    public var enrollment = RunEnrollment()
    /// Caller-provided power-policy gate, consulted before enrolling. A
    /// `false` gate still launches the child but unenrolled (`enrolled:false`,
    /// completion unknown); the gate never fabricates protection.
    public let isArmed: @Sendable () -> Bool

    public init(isArmed: @escaping @Sendable () -> Bool) {
        self.isArmed = isArmed
    }

    /// Maps `Process` termination to shell-style status: exit passes through,
    /// uncaught signal N becomes 128+N (F14).
    public static func shellExitStatus(
        terminationStatus: Int32, reason: Process.TerminationReason
    ) -> Int32 {
        switch reason {
        case .exit:
            return terminationStatus
        case .uncaughtSignal:
            return 128 + terminationStatus
        @unknown default:
            return terminationStatus
        }
    }

    /// Resolves the launch pair. Bare commands (no `/`) go through
    /// `/usr/bin/env` for PATH lookup; anything containing a slash is used
    /// directly as a file path.
    public static func resolvedLaunch(
        executable: String, args: [String]
    ) -> (url: URL, arguments: [String]) {
        if executable.contains("/") {
            return (URL(fileURLWithPath: executable), args)
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), [executable] + args)
    }

    public mutating func runChild(executable: String, args: [String]) throws(RunError) -> ChildResult {
        let id = UUID().uuidString
        let enrolled = isArmed()
        if enrolled {
            try enrollment.enroll(id)
        }
        defer { if enrolled { enrollment.release(id) } }
        let launch = Self.resolvedLaunch(executable: executable, args: args)
        let process = Process()
        process.executableURL = launch.url
        process.arguments = launch.arguments
        // Intentionally unset standardInput/Output/Error: the child inherits
        // stdio by design (see type docs). Result JSON is emitted after exit.
        do {
            try process.run()
        } catch {
            if executable.contains("/") {
                let exists = FileManager.default.fileExists(atPath: executable)
                throw RunError.launchFailed(exitMapping: exists ? 126 : 127, detail: String(describing: error))
            }
            // Bare command that could not launch env itself: treat as not found.
            throw RunError.launchFailed(exitMapping: 127, detail: String(describing: error))
        }
        process.waitUntilExit()
        let mapped = Self.shellExitStatus(
            terminationStatus: process.terminationStatus,
            reason: process.terminationReason)
        return ChildResult(exitStatus: mapped, enrolled: enrolled)
    }
}

public struct ChildResult: Sendable, Equatable {
    /// Direct child's shell-style status (exit verbatim, signal as 128+signo).
    public var exitStatus: Int32
    /// Whether this run held a protection enrollment for its lifetime.
    public var enrolled: Bool
    /// Always `directChildOnly`: detached grandchildren are never evidence.
    public var completionEvidence: String = "directChildOnly"
}

public struct RunEnrollment: Sendable {
    private var members = EnrollmentSet()

    public init() {}

    public var count: Int { members.count }

    public mutating func enroll(_ id: String) throws(RunError) {
        do {
            try members.enroll(id)
        } catch EnrollmentError.overLimit(let limit, _) {
            throw RunError.enrollmentFull(limit: limit)
        } catch {
            throw RunError.invalidID(id: id)
        }
    }

    public mutating func release(_ id: String) {
        members.release(id)
    }
}

public enum RunError: Error, Equatable, Sendable {
    case enrollmentFull(limit: Int)
    case invalidID(id: String)
    case launchFailed(exitMapping: Int, detail: String)
}

/// Only direct-child lifetime evidence. Periodic receipts do not claim that
/// arbitrary detached descendants are complete or that any power lease exists.
final class WrapperEventStream: @unchecked Sendable {
    private let channel: any IPCChannel
    private let sessionID = UUID().uuidString
    private let queue = DispatchQueue(label: "camlid.wrapper-events")
    private var sequence = 0
    private var timer: DispatchSourceTimer?
    init(channel: any IPCChannel) { self.channel = channel }
    func start() -> Bool {
        guard queue.sync(execute: { emit(.working) }) else { return false }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in _ = self?.emit(.working) }
        self.timer = timer
        timer.resume()
        return true
    }
    func finish(_ state: TaskState) {
        timer?.cancel()
        queue.sync { _ = emit(state) }
        timer = nil
    }
    private func emit(_ state: TaskState) -> Bool {
        guard let event = try? NormalizedEvent(provider: "wrapper", sessionID: sessionID, runID: "main",
            state: state, evidenceKind: .wrapper, confidence: .exact, sequence: sequence, receivedMonotonic: ContinuousTime.now),
            let data = try? JSONEncoder().encode(event),
            (try? channel.send(command: .event, payload: data)) != nil else { return false }
        sequence += 1
        return true
    }
}
