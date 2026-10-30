import Foundation
import Darwin
import CPeerIdentity

public enum BrokerFailure: Error, Equatable {
    case authentication(Int32), invalidPin, protocolViolation, timeout, transport(Int32)
    case environmentUnavailable, clockRegressed, bootChanged, ambiguousRoles, leaseExpired, journalDisappeared
}

/// Owner-configured main-executable pin, including local ad-hoc builds. No UID-only fallback.
public struct CodeIdentityPin: Hashable, Sendable {
    public let cdhash: String
    public init(cdhash: String) throws {
        guard cdhash.count == 40, cdhash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw BrokerFailure.invalidPin
        }
        self.cdhash = cdhash
    }
    public init(executable: URL) throws {
        guard executable.isFileURL else { throw BrokerFailure.invalidPin }
        var hash = [CChar](repeating: 0, count: 41)
        let result = CLRBExecutableHash(executable.path, &hash)
        guard result == 0 else { throw BrokerFailure.authentication(result) }
        try self.init(cdhash: String(decoding: hash.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }
    public static func currentProcess() throws -> CodeIdentityPin {
        var hash = [CChar](repeating: 0, count: 41)
        let result = CLRBCurrentHash(&hash)
        guard result == 0 else { throw BrokerFailure.authentication(result) }
        return try CodeIdentityPin(cdhash: String(decoding: hash.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }
}

struct SocketPeer {
    let pin: CodeIdentityPin
    let ownerIdentity: String
    init(fd: Int32) throws {
        var identity = CLRBPeerIdentity()
        let result = CLRBReadPeerIdentity(fd, &identity)
        guard result == 0 else { throw BrokerFailure.authentication(result) }
        guard identity.uid == geteuid() else { throw BrokerFailure.authentication(EACCES) }
        let hash = withUnsafeBytes(of: identity.cdhash) { raw in
            String(decoding: raw.prefix(40), as: UTF8.self)
        }
        pin = try CodeIdentityPin(cdhash: hash)
        ownerIdentity = "uid:\(identity.uid):pid:\(identity.pid):version:\(identity.pid_version):cdhash:\(hash)"
    }
}
