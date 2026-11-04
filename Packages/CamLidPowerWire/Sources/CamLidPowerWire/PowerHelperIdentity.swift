import Foundation
import Security
import CryptoKit

@objc public protocol PowerHelperXPC {
    func perform(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}

public enum HelperIdentityFailure: Error { case unsigned, invalidIdentity, invalidRequirement, teamUnavailable }

public enum PowerHelperIdentity {
    public static let serviceName = "com.camlid.power-helper"
    public static let appIdentifier = "com.camlid.CamLid"
    public static let qaIdentifier = "com.camlid.PowerCandidate"

    private static func signingInformation(expectedIdentifier: String) throws -> [String: Any] {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else {
            throw HelperIdentityFailure.unsigned
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            throw HelperIdentityFailure.invalidIdentity
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              values[kSecCodeInfoIdentifier as String] as? String == expectedIdentifier,
              let flags = values[kSecCodeInfoFlags as String] as? NSNumber,
              flags.uint32Value & SecCodeSignatureFlags.runtime.rawValue != 0 else {
            throw HelperIdentityFailure.invalidIdentity
        }
        let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        guard entitlements?["com.apple.security.get-task-allow"] as? Bool != true else {
            throw HelperIdentityFailure.invalidIdentity
        }
        return values
    }

    /// Production identity comes from our validated executable, never from IPC input.
    public static func ownTeam(expectedIdentifier: String) throws -> String {
        let values = try signingInformation(expectedIdentifier: expectedIdentifier)
        guard let team = values[kSecCodeInfoTeamIdentifier as String] as? String else {
            throw HelperIdentityFailure.teamUnavailable
        }
        guard team.count == 10, team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else {
            throw HelperIdentityFailure.invalidIdentity
        }
        return team
    }

    public static func peerRequirement(forHelper: Bool) throws -> String {
        if forHelper, Bundle.main.bundleIdentifier == qaIdentifier {
            return try localPeerRequirement(forHelper: true, ownIdentifier: qaIdentifier)
        }
        let ownIdentifier = forHelper ? appIdentifier : serviceName
        do {
            let team = try ownTeam(expectedIdentifier: ownIdentifier)
            return try requirement(identifier: forHelper ? serviceName : appIdentifier, team: team)
        } catch HelperIdentityFailure.teamUnavailable {
            return try localPeerRequirement(forHelper: forHelper, ownIdentifier: ownIdentifier)
        }
    }

    private static func localPeerRequirement(forHelper: Bool, ownIdentifier: String) throws -> String {
        // Root-installed exact pins, never caller-configured trust or a UID-only bypass.
        let pins = try LocalIdentityPins.loadInstalled()
        let values = try signingInformation(expectedIdentifier: ownIdentifier)
        if pins.version == 2 {
            // Own check: this process is signed by the pinned certificate. The peer is held to the same by the requirement.
            guard let certificates = values[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certificates.first,
                  Self.sha1Hex(SecCertificateCopyData(leaf) as Data) == pins.signerLeaf else {
                throw HelperIdentityFailure.invalidIdentity
            }
            return try pins.requirement(forHelper: forHelper)
        }
        guard let hash = values[kSecCodeInfoUnique as String] as? Data, hash.count == 20 else {
            throw HelperIdentityFailure.invalidIdentity
        }
        let actual = hash.map { String(format: "%02x", $0) }.joined()
        guard actual == (forHelper ? pins.appCDHash : pins.helperCDHash) else {
            throw HelperIdentityFailure.invalidIdentity
        }
        return try pins.requirement(forHelper: forHelper)
    }

    /// The hash `certificate leaf = H"…"` compares: SHA-1 of the certificate's DER bytes.
    static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func requirement(identifier: String, team: String) throws -> String {
        guard [appIdentifier, serviceName].contains(identifier), team.count == 10,
              team.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else {
            throw HelperIdentityFailure.invalidRequirement
        }
        let text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and !(entitlement[\"com.apple.security.get-task-allow\"] exists)"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else {
            throw HelperIdentityFailure.invalidRequirement
        }
        return text
    }
}
