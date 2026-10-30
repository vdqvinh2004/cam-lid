import Foundation
import Darwin

public struct BrokerRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case status, recordRestoreIntent, admitInertLease, renewInertLease, finishInertLease
    }
    public let version: Int
    public let operation: Operation
    public let expectedRevision: UInt64?
    public let sessionID: String?
    public let generation: UInt64?
    public let sequence: UInt64?
    public let durationNanos: UInt64?
    public let sessionDurationNanos: UInt64?
    public init(version: Int = 1, operation: Operation = .status, expectedRevision: UInt64? = nil,
                sessionID: String? = nil, generation: UInt64? = nil, sequence: UInt64? = nil,
                durationNanos: UInt64? = nil, sessionDurationNanos: UInt64? = nil) {
        self.version = version
        self.operation = operation
        self.expectedRevision = expectedRevision
        self.sessionID = sessionID
        self.generation = generation
        self.sequence = sequence
        self.durationNanos = durationNanos
        self.sessionDurationNanos = sessionDurationNanos
    }
}

public enum ReconciliationReason: String, Codable, Sendable {
    case savedIntent, previousBoot, deadlineExpired, restoreUnresolved
}

/// Experimental bookkeeping only; never an OS assertion or protection capability.
public struct InertLease: Codable, Equatable, Sendable {
    public let sessionID: String
    public let generation: UInt64
    public var sequence: UInt64
    public var revision: UInt64
    public var deadlineNanos: UInt64
    public let capNanos: UInt64
}

public struct BrokerReply: Codable, Sendable {
    public let accepted: Bool
    public let reason: String
    public let startup: StartupState?
    public var reconciliationReason: ReconciliationReason? = nil
    public var lease: InertLease? = nil
    public let powerActuation: Bool
    public let protectionAvailable: Bool
}

// Fixed total I/O deadline, independent of injected lease-clock test values.
struct FrameIO {
    static let maximumBytes = 32_768
    let fd: Int32
    let deadline = DispatchTime.now().uptimeNanoseconds + 3_000_000_000

    func wait(_ events: Int16) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw BrokerFailure.timeout }
            var item = pollfd(fd: fd, events: events, revents: 0)
            let milliseconds = Int32(min(3_000, (deadline - now + 999_999) / 1_000_000))
            let result = poll(&item, 1, milliseconds)
            if result < 0, errno == EINTR { continue }
            guard result >= 0 else { throw BrokerFailure.transport(errno) }
            if result == 0 { throw BrokerFailure.timeout }
            guard item.revents & events != 0 else { throw BrokerFailure.transport(ECONNRESET) }
            return
        }
    }

    func readBytes(_ count: Int) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: min(count, 4096))
        while result.count < count {
            try wait(Int16(POLLIN))
            let remaining = min(buffer.count, count - result.count)
            let received = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, remaining, MSG_DONTWAIT) }
            if received < 0, errno == EINTR || errno == EAGAIN { continue }
            guard received > 0 else { throw BrokerFailure.transport(received == 0 ? ECONNRESET : errno) }
            result.append(contentsOf: buffer.prefix(received))
        }
        return result
    }

    func read() throws -> Data {
        let header = try readBytes(4)
        let count = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count > 0, count <= Self.maximumBytes else { throw BrokerFailure.protocolViolation }
        return try readBytes(Int(count))
    }

    func write(_ body: Data) throws {
        guard !body.isEmpty, body.count <= Self.maximumBytes else { throw BrokerFailure.protocolViolation }
        var size = UInt32(body.count).bigEndian
        var data = withUnsafeBytes(of: &size) { Data($0) }
        data.append(body)
        var noSignal: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw BrokerFailure.transport(errno)
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try wait(Int16(POLLOUT))
                let sent = send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, MSG_DONTWAIT)
                if sent < 0, errno == EINTR || errno == EAGAIN { continue }
                guard sent > 0 else { throw BrokerFailure.transport(sent == 0 ? EIO : errno) }
                offset += sent
            }
        }
    }
}

/// Connect only to an owner-configured endpoint/pin. One request per connection.
public enum BrokerConnection {
    public static func exchange(path: String, serverPin: CodeIdentityPin, request: BrokerRequest) throws -> BrokerReply {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BrokerFailure.transport(errno) }
        defer { Darwin.close(fd) }
        var address = try socketAddress(path)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw BrokerFailure.transport(errno) }
        guard try SocketPeer(fd: fd).pin == serverPin else { throw BrokerFailure.authentication(EACCES) }
        let io = FrameIO(fd: fd)
        try io.write(JSONEncoder().encode(request))
        return try JSONDecoder().decode(BrokerReply.self, from: io.read())
    }
}

@_spi(TestInputs)
public func socketAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let bytes = Array(path.utf8)
    guard !bytes.contains(0), !bytes.isEmpty, bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
        throw BrokerFailure.protocolViolation
    }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: bytes + [0])
    }
    return address
}
