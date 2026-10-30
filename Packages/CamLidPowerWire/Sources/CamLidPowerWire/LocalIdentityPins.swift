import Foundation
import Darwin
import Security

/// Explicit local-development trust, installed by root out-of-band, not a UID-only fallback.
/// Both executables remain kernel-validated against distinct exact CDHashes.
public struct LocalIdentityPins: Codable, Sendable {
    public let version: Int
    public let appCDHash: String
    public let helperCDHash: String

    public init(appCDHash: String, helperCDHash: String) throws {
        version = 1
        self.appCDHash = appCDHash
        self.helperCDHash = helperCDHash
        try validate()
    }

    public func validate() throws {
        let hashes = [appCDHash, helperCDHash]
        guard version == 1, appCDHash != helperCDHash,
              hashes.allSatisfy({ $0.count == 40 && $0.utf8.allSatisfy({
                  (48...57).contains($0) || (97...102).contains($0)
              }) }) else { throw HelperIdentityFailure.invalidIdentity }
    }

    public func requirement(forHelper: Bool) throws -> String {
        try validate()
        let hash = forHelper ? helperCDHash : appCDHash
        let text = "cdhash H\"\(hash)\" and !(entitlement[\"com.apple.security.get-task-allow\"] exists)"
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
