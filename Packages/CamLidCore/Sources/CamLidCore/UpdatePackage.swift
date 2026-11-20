import CryptoKit
import Foundation

/// The zip and its checksum of one release, both from GitHub (spec 026 FR-002).
public struct UpdateAssets: Equatable, Sendable {
    public let zipURL: URL
    public let checksumURL: URL

    public init(zipURL: URL, checksumURL: URL) {
        self.zipURL = zipURL
        self.checksumURL = checksumURL
    }
}

/// Spec 026 FR-004: the checks a downloaded release must pass before anything is replaced. Each failure's raw value
/// is the reason the app shows.
public enum UpdatePackage {
    public static let bundleName = "CamLid.app"
    public static let identifier = "com.camlid.CamLid"

    public enum Failure: String, Equatable, Sendable {
        case checksumUnreadable = "updateChecksumUnreadable"
        case checksumMismatch = "updateChecksumMismatch"
        case unpackFailed = "updateUnpackFailed"
        case bundleMissing = "updateBundleMissing"
        case signatureInvalid = "updateSignatureInvalid"
        case signerMismatch = "updateSignerMismatch"
        case identifierMismatch = "updateIdentifierMismatch"
        case versionMismatch = "updateVersionMismatch"
    }

    /// The `.sha256` asset is `shasum` output, `<64 lowercase hex>  <file name>`. Anything else is refused.
    public static func expectedDigest(checksumFile text: String, zipName: String) -> String? {
        let fields = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 2, fields[1] == zipName, fields[0].count == 64,
              fields[0].allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return fields[0]
    }

    /// SHA-256 of a file as 64 lowercase hex characters, or nil if it cannot be read.
    public static func digest(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
    }

    /// FR-004 for an unpacked bundle: a valid signature (deep and strict), the pinned release certificate as its signer,
    /// the project identifier, and the version the release names. Returns the first failed check, or nil.
    public static func verifyBundle(_ app: URL, pinnedLeaf: String, version: String,
                                    runner: any HelperCommandRunning) -> Failure? {
        guard FileManager.default.fileExists(atPath: app.path) else { return .bundleMissing }
        guard runner.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0 else {
            return .signatureInvalid
        }
        let designated = runner.run("/usr/bin/codesign", ["-d", "-r-", app.path])
        guard designated.status == 0, CodeSignature.leaf(inDesignatedRequirement: designated.output) == pinnedLeaf else {
            return .signerMismatch
        }
        let bundle = Bundle(url: app)
        guard designated.output.contains("identifier \"\(identifier)\""), bundle?.bundleIdentifier == identifier else {
            return .identifierMismatch
        }
        guard bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
            return .versionMismatch
        }
        return nil
    }
}
