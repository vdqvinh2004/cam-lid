import Foundation
import Testing
@testable import CamLidCore

/// Canned `codesign` answers: whether the signature verifies, and the designated requirement it names.
private struct CodesignFake: HelperCommandRunning {
    let verifies: Bool
    let requirement: String
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        if arguments.contains("--verify") { return (verifies ? 0 : 1, "") }
        return (0, requirement)
    }
}

@Suite("In-app update package checks")
struct UpdatePackageTests {
    private let leaf = String(repeating: "f", count: 40)

    private func requirement(leaf: String? = nil, identifier: String = "com.camlid.CamLid") -> String {
        "designated => identifier \"\(identifier)\" and certificate leaf = H\"\(leaf ?? self.leaf)\""
    }

    /// A bundle with only the Info.plist that the checks read.
    private func fixtureApp(identifier: String = "com.camlid.CamLid", version: String = "0.2.0") throws -> URL {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("CamLid.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
                                   "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    @Test func theChecksumFileMustNameTheZipAndHoldSixtyFourLowercaseHexDigits() {
        let digest = String(repeating: "a", count: 64)
        #expect(UpdatePackage.expectedDigest(checksumFile: "\(digest)  CamLid-0.2.0-macos-arm64.zip\n",
                                             zipName: "CamLid-0.2.0-macos-arm64.zip") == digest)
        #expect(UpdatePackage.expectedDigest(checksumFile: "\(digest)  other.zip\n", zipName: "CamLid-0.2.0-macos-arm64.zip") == nil)
        #expect(UpdatePackage.expectedDigest(checksumFile: "\(String(repeating: "A", count: 64))  z.zip", zipName: "z.zip") == nil)
        #expect(UpdatePackage.expectedDigest(checksumFile: digest, zipName: "z.zip") == nil)
        #expect(UpdatePackage.expectedDigest(checksumFile: "\(digest)  z.zip extra", zipName: "z.zip") == nil)
    }

    @Test func theDigestOfAFileIsItsSHA256() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: file)
        #expect(UpdatePackage.digest(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(UpdatePackage.digest(of: folder.appendingPathComponent("missing")) == nil)
    }

    @Test func theLeafCertificateIsReadOnlyFromACertificateRequirement() {
        let leaf = String(repeating: "f", count: 40)
        #expect(CodeSignature.leaf(inDesignatedRequirement: "designated => identifier \"x\" and certificate leaf = H\"\(leaf)\"") == leaf)
        #expect(CodeSignature.leaf(inDesignatedRequirement: "designated => cdhash H\"\(String(repeating: "a", count: 40))\"") == nil)
        #expect(CodeSignature.leaf(inDesignatedRequirement: "certificate leaf = H\"\(String(repeating: "F", count: 40))\"") == nil)
    }

    @Test func aBundleIsAcceptedOnlyWithThePinnedSignerTheIdentifierAndTheReleasedVersion() throws {
        let app = try fixtureApp()
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let good = CodesignFake(verifies: true, requirement: requirement())
        #expect(UpdatePackage.verifyBundle(app, pinnedLeaf: leaf, version: "0.2.0", runner: good) == nil)
        #expect(UpdatePackage.verifyBundle(app, pinnedLeaf: leaf, version: "0.2.0",
                                           runner: CodesignFake(verifies: false, requirement: requirement())) == .signatureInvalid)
        #expect(UpdatePackage.verifyBundle(app, pinnedLeaf: leaf, version: "0.2.0",
                                           runner: CodesignFake(verifies: true, requirement: requirement(leaf: String(repeating: "a", count: 40)))) == .signerMismatch)
        #expect(UpdatePackage.verifyBundle(app, pinnedLeaf: leaf, version: "0.2.0",
                                           runner: CodesignFake(verifies: true, requirement: "designated => cdhash H\"\(String(repeating: "b", count: 40))\""))
                == .signerMismatch)
        #expect(UpdatePackage.verifyBundle(app, pinnedLeaf: leaf, version: "0.3.0", runner: good) == .versionMismatch)
        #expect(UpdatePackage.verifyBundle(app.appendingPathComponent("missing.app"), pinnedLeaf: leaf, version: "0.2.0",
                                           runner: good) == .bundleMissing)
        let other = try fixtureApp(identifier: "com.example.other")
        defer { try? FileManager.default.removeItem(at: other.deletingLastPathComponent()) }
        #expect(UpdatePackage.verifyBundle(other, pinnedLeaf: leaf, version: "0.2.0", runner: good) == .identifierMismatch)
    }

    @Test func theSwapScriptWaitsForTheAppThenSwapsThenOpensItWithTheSameArguments() throws {
        let script = UpdateSwap.script
        #expect(script.hasPrefix("#!/bin/sh"))
        #expect(script.contains("while kill -0 \"$pid\""))
        #expect(script.contains("mv \"$installed\" \"$backup\""))
        #expect(script.contains("mv \"$staged\" \"$installed\""))
        #expect(script.contains("mv \"$backup\" \"$installed\""))
        #expect(script.contains("open -n \"$installed\" --args \"$@\""))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("swap-\(UUID().uuidString).sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(ProcessCommandRunner().run("/bin/sh", ["-n", file.path]).status == 0)
    }
}
