import Foundation
import Security
import Testing
@testable import CamLidPowerWire

/// Exercises the pinned requirement against real signed, re-signed and tampered executables, so a peer with an
/// invalid signature or the wrong CDHash is shown to fail the same check the XPC connection applies.
@Suite struct PeerSignatureTests {
    private func run(_ path: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func signedCopy(of source: String, in directory: URL, named name: String) throws -> (URL, String) {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(atPath: source, toPath: url.path)
        #expect(run("/usr/bin/codesign", ["--force", "--sign", "-", "--options", "runtime", url.path]).0 == 0)
        let info = run("/usr/bin/codesign", ["-dvvv", url.path]).1
        let hash = info.split(separator: "\n").first { $0.hasPrefix("CDHash=") }.map { String($0.dropFirst(7)) }
        return (url, try #require(hash))
    }

    private func valid(_ url: URL, against requirementText: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    @Test func pinnedRequirementAcceptsOnlyTheExactSignedPeer() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-peer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (helper, helperHash) = try signedCopy(of: "/bin/echo", in: directory, named: "helper")
        let (other, otherHash) = try signedCopy(of: "/usr/bin/true", in: directory, named: "other")
        #expect(helperHash != otherHash)
        let pins = try LocalIdentityPins(appCDHash: otherHash, helperCDHash: helperHash)
        let helperRequirement = try pins.requirement(forHelper: true)

        #expect(valid(helper, against: helperRequirement))                 // the pinned peer
        #expect(!valid(other, against: helperRequirement))                 // validly signed, wrong CDHash
        #expect(valid(other, against: try pins.requirement(forHelper: false)))
    }

    @Test func aTamperedPeerFailsEvenWithItsOwnPinnedHash() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-peer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (helper, helperHash) = try signedCopy(of: "/bin/echo", in: directory, named: "helper")
        let pins = try LocalIdentityPins(appCDHash: String(repeating: "a", count: 40), helperCDHash: helperHash)
        let requirement = try pins.requirement(forHelper: true)
        #expect(valid(helper, against: requirement))

        var bytes = try Data(contentsOf: helper)
        // Flip one byte per page across the file so the running architecture's code pages are hit.
        for index in stride(from: 16_384, to: bytes.count, by: 4_096) { bytes[index] ^= 0xFF }
        try bytes.write(to: helper)
        #expect(!valid(helper, against: requirement))
    }

    @Test func anUnsignedPeerFailsThePinnedRequirement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-peer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (signed, hash) = try signedCopy(of: "/bin/echo", in: directory, named: "signed")
        let unsigned = directory.appendingPathComponent("unsigned")
        try FileManager.default.copyItem(at: signed, to: unsigned)
        #expect(run("/usr/bin/codesign", ["--remove-signature", unsigned.path]).0 == 0)
        let pins = try LocalIdentityPins(appCDHash: String(repeating: "b", count: 40), helperCDHash: hash)
        #expect(!valid(unsigned, against: try pins.requirement(forHelper: true)))
    }
}
