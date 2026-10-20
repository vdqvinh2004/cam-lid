import Foundation
import Darwin

public enum PMSetCommand: Sendable, Equatable {
    case inspect, enable, disable
    public var arguments: [String] {
        switch self {
        case .inspect: ["-g"]
        case .enable: ["-a", "disablesleep", "1"]
        case .disable: ["-a", "disablesleep", "0"]
        }
    }
}

public enum PMSetFailure: Error, Equatable {
    case invalidOutput, exit(Int32), timeout, outputTooLarge, io, commandStillUncertain
}

public struct PMSetResult: Sendable {
    public let status: Int32
    public let output: Data
    public init(status: Int32, output: Data) { self.status = status; self.output = output }
}

public final class PMSetBackend: SleepOverrideBackend {
    private let execute: (PMSetCommand) throws -> PMSetResult
    public init(execute: @escaping (PMSetCommand) throws -> PMSetResult) { self.execute = execute }

    public func readDisabled() throws -> Bool {
        let result = try execute(.inspect)
        guard result.status == 0 else { throw PMSetFailure.exit(result.status) }
        return try Self.decodeDisabled(result.output)
    }

    public func setDisabled(_ disabled: Bool) throws {
        let result = try execute(disabled ? .enable : .disable)
        guard result.status == 0 else { throw PMSetFailure.exit(result.status) }
    }

    public static func decodeDisabled(_ data: Data) throws -> Bool {
        guard data.count <= 65_536, let text = String(data: data, encoding: .utf8),
              !text.contains("\0") else { throw PMSetFailure.invalidOutput }
        let rows = text.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace) }
            .filter { $0.first == "SleepDisabled" }
        guard rows.count == 1, rows[0].count == 2 else { throw PMSetFailure.invalidOutput }
        switch rows[0][1] {
        case "0": return false
        case "1": return true
        default: throw PMSetFailure.invalidOutput
        }
    }
}

/// Only the root daemon chooses this runner. No shell, sudo, client paths or client arguments.
/// A timeout poisons this instance: SIGTERM/process exit is not OS-operation cancellation.
public final class NativePMSetRunner {
    private var uncertainProcess: Process?
    public init() {}

    public func execute(_ command: PMSetCommand) throws -> PMSetResult {
        guard uncertainProcess == nil else { throw PMSetFailure.commandStillUncertain }
        var template = Array("/private/var/tmp/camlid-pmset.XXXXXX".utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw PMSetFailure.io }
        template.withUnsafeBufferPointer { _ = unlink($0.baseAddress!) }
        defer { close(fd) }
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw PMSetFailure.io }
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = command.arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 2) == .success else {
            // Retain owned process; do not issue a racing reset after a timed-out enable.
            uncertainProcess = process
            if process.isRunning { process.terminate() }
            throw PMSetFailure.timeout
        }
        var information = stat()
        guard fstat(fd, &information) == 0, information.st_size <= 65_536 else {
            throw PMSetFailure.outputTooLarge
        }
        guard lseek(fd, 0, SEEK_SET) >= 0 else { throw PMSetFailure.io }
        let data = try output.read(upToCount: 65_537) ?? Data()
        guard data.count <= 65_536 else { throw PMSetFailure.outputTooLarge }
        return PMSetResult(status: process.terminationStatus, output: data)
    }
}
