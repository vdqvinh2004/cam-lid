import Testing
@testable import CamLidPowerWire

@Suite struct ThermalGuardTests {
    @Test func fairIsAcceptableAndNominalIsClean() {
        var guardState = ThermalGuard()
        #expect(guardState.stopReason(for: .nominal, now: 0) == nil)
        #expect(guardState.stopReason(for: .fair, now: 1_000) == nil)
    }

    @Test func seriousStopsOnlyAfterItsGraceWithoutABreak() {
        var guardState = ThermalGuard()
        #expect(guardState.stopReason(for: .serious, now: 100) == nil)
        #expect(guardState.stopReason(for: .serious, now: 129.9) == nil)
        #expect(guardState.stopReason(for: .serious, now: 130) == "thermalSerious")
        // A non-serious reading breaks the run, so a later serious reading starts a fresh grace.
        #expect(guardState.stopReason(for: .fair, now: 131) == nil)
        #expect(guardState.stopReason(for: .serious, now: 132) == nil)
    }

    @Test func criticalAndUnknownStopAtOnce() {
        var guardState = ThermalGuard()
        #expect(guardState.stopReason(for: .critical, now: 0) == "thermalCritical")
        #expect(guardState.stopReason(for: .unknown, now: 0) == "thermalUnknown")
    }

    @Test func criticalKeepsTheSeriousClock() {
        var guardState = ThermalGuard()
        #expect(guardState.stopReason(for: .serious, now: 100) == nil)
        #expect(guardState.stopReason(for: .critical, now: 110) == "thermalCritical")
        // Serious again after critical: the original clock still runs, so the grace is already spent.
        #expect(guardState.stopReason(for: .serious, now: 131) == "thermalSerious")
    }
}
