import Testing
import Foundation
import CamLidCore
@testable import CamLidApp
struct LidStateReaderTests {
    @Test func onlyRealBooleanAccepted() {
        #expect(LidStateReader.decode(kCFBooleanTrue, at: 10).state == .closed)
        #expect(LidStateReader.decode(kCFBooleanFalse, at: 10).state == .open)
        #expect(LidStateReader.decode(NSNumber(value: 1), at: 10).state == .unknown)
        #expect(LidStateReader.decode("false" as CFString, at: 10).state == .unknown)
        #expect(LidStateReader.decode(nil, at: 10).state == .unknown)
    }
    @Test func staleOrFutureLidCannotBeHealthy() {
        let observation = LidObservation(state: .closed, sampledAtMonotonic: 10)
        #expect(observation.projected(now: 15).state == .closed)
        #expect(observation.projected(now: 15.01).state == .unknown)
        #expect(observation.projected(now: 9).state == .unknown)
    }
}
