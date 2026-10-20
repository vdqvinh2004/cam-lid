import Foundation
import Darwin
import Security
import Testing
@testable import CamLidPowerService

@Suite struct IdentityTests {
    @Test func signingRequirementsAreSpecificAndParseable() throws {
        let app = try PowerHelperIdentity.requirement(identifier: PowerHelperIdentity.appIdentifier, team: "ABCDE12345")
        let helper = try PowerHelperIdentity.requirement(identifier: PowerHelperIdentity.serviceName, team: "ABCDE12345")
        #expect(app.contains("anchor apple generic"))
        #expect(app.contains("get-task-allow"))
        #expect(app != helper)
        #expect(throws: HelperIdentityFailure.self) {
            try PowerHelperIdentity.requirement(identifier: "com.example.other", team: "ABCDE12345")
        }
        #expect(throws: HelperIdentityFailure.self) {
            try PowerHelperIdentity.requirement(identifier: PowerHelperIdentity.appIdentifier, team: "\" or true")
        }
    }

    @Test func testHostCannotPretendToBeProductionAppOrHelper() {
        #expect(throws: HelperIdentityFailure.self) {
            try PowerHelperIdentity.ownTeam(expectedIdentifier: PowerHelperIdentity.appIdentifier)
        }
        #expect(throws: HelperIdentityFailure.self) {
            try PowerHelperIdentity.ownTeam(expectedIdentifier: PowerHelperIdentity.serviceName)
        }
    }

    @Test func localPinsRemainExactAndRoleSeparated() throws {
        let pins = try LocalIdentityPins(appCDHash: String(repeating: "a", count: 40), helperCDHash: String(repeating: "b", count: 40))
        #expect(try pins.requirement(forHelper: false).contains(String(repeating: "a", count: 40)))
        #expect(try pins.requirement(forHelper: true).contains(String(repeating: "b", count: 40)))
        #expect(throws: HelperIdentityFailure.self) {
            try LocalIdentityPins(appCDHash: String(repeating: "a", count: 40), helperCDHash: String(repeating: "a", count: 40))
        }
        #expect(throws: HelperIdentityFailure.self) {
            try LocalIdentityPins(appCDHash: "unsigned", helperCDHash: String(repeating: "b", count: 40))
        }
        let invalid = Data("{\"version\":2,\"appCDHash\":\"\(String(repeating: "a", count: 40))\",\"helperCDHash\":\"\(String(repeating: "b", count: 40))\"}".utf8)
        #expect(throws: HelperIdentityFailure.self) {
            try JSONDecoder().decode(LocalIdentityPins.self, from: invalid).validate()
        }
    }

    @Test func extendedACLIsNotMistakenForProtectedModeBits() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fd = open(url.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        #expect(fd >= 0)
        guard fd >= 0 else { return }
        defer { close(fd); unlink(url.path) }
        try requireNoExtendedACL(fd: fd)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+a", "\(NSUserName()) allow write", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(throws: HelperIdentityFailure.self) { try requireNoExtendedACL(fd: fd) }
    }

    @Test func protocolRepliesNeverClaimQualification() throws {
        let reply = PowerReply(accepted: true, state: "active", reason: "fixture")
        let data = try JSONEncoder().encode(reply)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["qualifiedClosedLidProtection"] as? Bool == false)
    }
}
