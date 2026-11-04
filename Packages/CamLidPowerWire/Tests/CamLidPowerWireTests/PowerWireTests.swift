import Foundation
import Testing
@testable import CamLidPowerWire

@Suite struct PowerWireTests {
    @Test func requestRoundTripsWithoutLosingFields() throws {
        let token = UUID()
        let request = PowerRequest(operation: .renew, token: token, sequence: 7, sessionSeconds: 300)
        let decoded = try JSONDecoder().decode(PowerRequest.self, from: JSONEncoder().encode(request))
        #expect(decoded.operation == .renew && decoded.token == token)
        #expect(decoded.sequence == 7 && decoded.sessionSeconds == 300 && decoded.version == 1)
    }

    @Test func theMechanismRoundTripsAndAnOldClientMeansStandard() throws {
        let strict = PowerRequest(operation: .acquire, sequence: 1, sessionSeconds: 60, mechanism: .strict)
        #expect(try JSONDecoder().decode(PowerRequest.self, from: JSONEncoder().encode(strict)).mechanism == .strict)
        let old = Data(#"{"version":1,"operation":"acquire","sequence":1,"sessionSeconds":60}"#.utf8)
        #expect(try JSONDecoder().decode(PowerRequest.self, from: old).mechanism == nil)
        let unknown = Data(#"{"version":1,"operation":"acquire","mechanism":"everything"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PowerRequest.self, from: unknown) }
    }

    @Test func unknownOperationsAreRejectedWhenDecoding() {
        let json = Data(#"{"version":1,"operation":"format-disk"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PowerRequest.self, from: json) }
    }

    @Test func replyNeverClaimsQualificationByDefault() throws {
        let reply = PowerReply(accepted: true, state: "active", reason: "ok", leaseRemainingSeconds: 20)
        #expect(!reply.qualifiedClosedLidProtection)
        let decoded = try JSONDecoder().decode(PowerReply.self, from: JSONEncoder().encode(reply))
        #expect(decoded.accepted && decoded.leaseRemainingSeconds == 20 && !decoded.qualifiedClosedLidProtection)
    }

    @Test func identityRequirementsAcceptOnlyKnownIdentifiersAndTeams() throws {
        let text = try PowerHelperIdentity.requirement(identifier: PowerHelperIdentity.serviceName, team: "ABCDE12345")
        #expect(text.contains("anchor apple generic"))
        #expect(throws: HelperIdentityFailure.self) {
            try PowerHelperIdentity.requirement(identifier: "com.example.other", team: "ABCDE12345")
        }
        #expect(throws: HelperIdentityFailure.self) {
            try PowerHelperIdentity.requirement(identifier: PowerHelperIdentity.appIdentifier, team: "short")
        }
    }

    @Test func localPinsRejectEqualOrMalformedHashes() throws {
        let hash = String(repeating: "a", count: 40)
        #expect(throws: (any Error).self) { try LocalIdentityPins(appCDHash: hash, helperCDHash: hash) }
        #expect(throws: (any Error).self) { try LocalIdentityPins(appCDHash: "bad", helperCDHash: hash) }
        let pins = try LocalIdentityPins(appCDHash: hash, helperCDHash: String(repeating: "b", count: 40))
        #expect(try pins.requirement(forHelper: true) != pins.requirement(forHelper: false))
    }

    @Test func signerPinsNameTheCertificateAndTheIdentifierNotAnExactBuild() throws {
        let leaf = String(repeating: "c", count: 40)
        let pins = try LocalIdentityPins(signerLeaf: leaf)
        let helper = try pins.requirement(forHelper: true)
        let app = try pins.requirement(forHelper: false)
        #expect(helper.contains("identifier \"com.camlid.power-helper\"") && helper.contains("certificate leaf = H\"\(leaf)\""))
        #expect(app.contains("identifier \"com.camlid.CamLid\"") && !app.contains("cdhash"))
        #expect(PowerHelperVersion.current >= 1 && pins.helperVersion == PowerHelperVersion.current)
    }

    @Test func signerPinsRejectMalformedOrMixedContent() throws {
        #expect(throws: (any Error).self) { try LocalIdentityPins(signerLeaf: "short") }
        #expect(throws: (any Error).self) { try LocalIdentityPins(signerLeaf: String(repeating: "C", count: 40)) }
        #expect(throws: (any Error).self) { try LocalIdentityPins(signerLeaf: String(repeating: "c", count: 40), helperVersion: 0) }
        let mixed = Data(#"{"version":2,"signerLeaf":"\#(String(repeating: "c", count: 40))","helperVersion":1,"appCDHash":"\#(String(repeating: "a", count: 40))"}"#.utf8)
        let decoded = try JSONDecoder().decode(LocalIdentityPins.self, from: mixed)
        #expect(throws: (any Error).self) { try decoded.validate() }
        let old = Data(#"{"version":1,"appCDHash":"\#(String(repeating: "a", count: 40))","helperCDHash":"\#(String(repeating: "b", count: 40))"}"#.utf8)
        try JSONDecoder().decode(LocalIdentityPins.self, from: old).validate()   // existing installs keep working
    }
}
