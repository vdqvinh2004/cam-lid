import Foundation
import Testing
import CamLidPowerWire
@testable import CamLidApp
@testable import CamLidCore

@Suite struct PowerLeaseClientTests {
    @Test func actionsMapToTheHelpersRequestShapes() {
        let token = UUID()
        let acquire = XPCPowerHoldTransport.request(for: .acquire(sessionSeconds: 300))
        #expect(acquire.operation == .acquire && acquire.sequence == 1 && acquire.sessionSeconds == 300 && acquire.token == nil)
        let renew = XPCPowerHoldTransport.request(for: .renew(token: token, sequence: 4))
        #expect(renew.operation == .renew && renew.token == token && renew.sequence == 4 && renew.sessionSeconds == nil)
        let release = XPCPowerHoldTransport.request(for: .release(token: token))
        #expect(release.operation == .release && release.token == token && release.sequence == nil)
    }

    @Test func repliesMapToTheNeutralShapeAndBadDataIsUnreachable() throws {
        let token = UUID()
        let data = try JSONEncoder().encode(PowerReply(accepted: true, state: "active", reason: "leaseAcquired", token: token))
        #expect(XPCPowerHoldTransport.holdReply(from: data) == HoldReply(accepted: true, state: "active", reason: "leaseAcquired", token: token))
        #expect(XPCPowerHoldTransport.holdReply(from: Data("not json".utf8)) == nil)
        #expect(XPCPowerHoldTransport.holdReply(from: Data(repeating: 0x20, count: 5000)) == nil)
    }

    @Test func anUnverifiableHelperIdentityMeansUnreachable() async {
        struct Failure: Error {}
        let transport = XPCPowerHoldTransport(requirement: { throw Failure() })
        #expect(await transport.send(.acquire(sessionSeconds: 60)) == nil)
    }
}
