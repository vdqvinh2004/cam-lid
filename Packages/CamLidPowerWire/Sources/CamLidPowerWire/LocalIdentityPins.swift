import Foundation
import Darwin
import Security

/// Bumped whenever the helper's behavior changes. The pins record the version installed; an app that ships a higher
/// one asks for a reinstall, an app that ships the same one never does.
public enum PowerHelperVersion {
    public static let current = 1
}

/// Explicit local trust, installed by root out-of-band, not a UID-only fallback.
/// Version 1 (ad-hoc builds): both executables are kernel-validated against distinct exact CDHashes, so any rebuild
/// needs a new install. Version 2 (releases signed with a stable certificate): both are validated against their
/// identifier plus the signing certificate's hash, so an app update keeps working until the helper itself changes.
public struct LocalIdentityPins: Codable, Sendable {
    public let version: Int
    public let appCDHash: String?
    public let helperCDHash: String?
    /// SHA-1 of the leaf certificate that signed both the app and the helper (version 2).
    public let signerLeaf: String?
    /// `PowerHelperVersion.current` at install time (version 2).
    public let helperVersion: Int?

    public init(appCDHash: String, helperCDHash: String) throws {
        version = 1
        self.appCDHash = appCDHash
        self.helperCDHash = helperCDHash
        signerLeaf = nil; helperVersion = nil
        try validate()
    }

    public init(signerLeaf: String, helperVersion: Int = PowerHelperVersion.current) throws {
        version = 2
        self.signerLeaf = signerLeaf
        self.helperVersion = helperVersion
        appCDHash = nil; helperCDHash = nil
        try validate()
    }

    private static func isSHA1(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.count == 40 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    public func validate() throws {
        switch version {
        case 1:
            guard let app = appCDHash, let helper = helperCDHash, app != helper,
                  Self.isSHA1(app), Self.isSHA1(helper), signerLeaf == nil, helperVersion == nil else {
                throw HelperIdentityFailure.invalidIdentity
            }
        case 2:
            guard Self.isSHA1(signerLeaf), let helperVersion, helperVersion >= 1,
                  appCDHash == nil, helperCDHash == nil else { throw HelperIdentityFailure.invalidIdentity }
        default: throw HelperIdentityFailure.invalidIdentity
        }
    }

    public func requirement(forHelper: Bool) throws -> String {
        try validate()
        let noDebug = "!(entitlement[\"com.apple.security.get-task-allow\"] exists)"
        let text: String
        if version == 2, let signerLeaf {
            let identifier = forHelper ? PowerHelperIdentity.serviceName : PowerHelperIdentity.appIdentifier
            text = "identifier \"\(identifier)\" and certificate leaf = H\"\(signerLeaf)\" and \(noDebug)"
        } else {
            let hash = (forHelper ? helperCDHash : appCDHash) ?? ""
            text = "cdhash H\"\(hash)\" and \(noDebug)"
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            throw HelperIdentityFailure.invalidRequirement
        }
        return text
    }

    public static func loadInstalled() throws -> LocalIdentityPins {
        var directory = open("/Library", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw HelperIdentityFailure.invalidIdentity }
        defer { close(directory) }
        try validateDirectory(directory)
        for component in ["Application Support", "CamLidPowerHelper"] {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw HelperIdentityFailure.invalidIdentity }
            do { try validateDirectory(next) }
            catch { close(next); throw error }
            close(directory)
            directory = next
        }
        let fd = openat(directory, "identity.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw HelperIdentityFailure.invalidIdentity }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o777 == 0o644,
              (1...2048).contains(info.st_size) else { throw HelperIdentityFailure.invalidIdentity }
        try requireNoExtendedACL(fd: fd)
        var bytes = [UInt8](repeating: 0, count: 2049)
        let count = Darwin.read(fd, &bytes, bytes.count)
        guard count == Int(info.st_size) else { throw HelperIdentityFailure.invalidIdentity }
        let pins = try JSONDecoder().decode(LocalIdentityPins.self, from: Data(bytes.prefix(count)))
        try pins.validate()
        return pins
    }

    private static func validateDirectory(_ fd: Int32) throws {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o022 == 0 else { throw HelperIdentityFailure.invalidIdentity }
        try requireNoExtendedACL(fd: fd)
    }
}
