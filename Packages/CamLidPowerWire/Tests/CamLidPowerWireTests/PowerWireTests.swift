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
}
