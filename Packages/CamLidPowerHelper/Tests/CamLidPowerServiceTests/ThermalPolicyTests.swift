import Testing
@testable import CamLidPowerService

/// The helper's thermal rule matches the app's safety policy: fair holds, serious holds through its grace and then
/// stops with its own reason, critical and unknown refuse or stop at once, and a late renewal learns why the lease ended.
@Suite struct ThermalPolicyTests {
    private func reading(_ thermal: ThermalLevel) -> HelperSafety {
        HelperSafety(onAC: true, batteryPercent: 80, thermal: thermal, consoleUID: 501, lidClosed: false, externalDisplays: 0)
    }

    @Test func fairHoldsAndRenewsLikeNominal() {
        let f = Fixture()
        f.safety = reading(.fair)
        let held = f.acquire()
        #expect(held.accepted)
        f.time += 10
        #expect(f.service.handle(PowerRequest(operation: .renew, token: held.token, sequence: 2), owner: f.owner, uid: 501).accepted)
    }

    @Test func seriousHoldsThroughItsGraceThenStopsWithItsOwnReason() {
        let f = Fixture()
        let held = f.acquire()                            // the lease runs to t = 130 unless renewed
        #expect(held.accepted)
        f.safety = reading(.serious)
        f.service.poll()                                  // the serious run starts at t = 100
        f.time += 10
        #expect(f.service.handle(PowerRequest(operation: .renew, token: held.token, sequence: 2), owner: f.owner, uid: 501).accepted)
        f.time += 10
        #expect(f.service.handle(PowerRequest(operation: .renew, token: held.token, sequence: 3), owner: f.owner, uid: 501).accepted)
        f.time += 9                                       // 29 s of serious: still inside the grace
        f.service.poll()
        #expect(f.service.state == "active")
        f.time += 1                                       // 30 s of serious: the grace is spent
        f.service.poll()
        #expect(f.service.state != "active" && f.service.reason == "thermalSerious")
        let late = f.service.handle(PowerRequest(operation: .renew, token: held.token, sequence: 4), owner: f.owner, uid: 501)
        #expect(!late.accepted && late.reason == "thermalSerious")
    }

    @Test func criticalRefusesToStartAndStopsAHeldSessionAtOnce() {
        let refused = Fixture()
        refused.safety = reading(.critical)
        let none = refused.acquire()
        #expect(!none.accepted && none.reason == "thermalCritical" && refused.backend.writes.isEmpty)

        let f = Fixture()
        let held = f.acquire()
        #expect(held.accepted)
        f.safety = reading(.critical)
        f.service.poll()
        #expect(f.service.state != "active" && f.service.reason == "thermalCritical")
        let late = f.service.handle(PowerRequest(operation: .renew, token: held.token, sequence: 2), owner: f.owner, uid: 501)
        #expect(!late.accepted && late.reason == "thermalCritical")
    }

    @Test func unknownThermalRefusesToStart() {
        let f = Fixture()
        f.safety = reading(.unknown)
        let refused = f.acquire()
        #expect(!refused.accepted && refused.reason == "thermalUnknown" && f.backend.writes.isEmpty)
    }

    @Test func aNewHoldClearsTheStopOfTheLastOne() {
        let f = Fixture()
        #expect(f.acquire().accepted)
        f.safety = reading(.critical)
        f.service.poll()
        f.safety = reading(.fair)
        let second = f.acquire()
        #expect(second.accepted)
        #expect(f.service.handle(PowerRequest(operation: .renew, token: second.token, sequence: 2), owner: f.owner, uid: 501).accepted)
    }
}
