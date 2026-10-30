import Foundation
import Testing
@_spi(TestInputs) import LidRecoveryBroker
@_spi(TestInputs) import LidNativeAdapter

@Suite("Typed read-only lab safety", .serialized)
struct NativeSafetyTests {
    let boot = "00000000-0000-0000-0000-000000000001"
    func observation(battery: Double? = 75, ac: Bool? = true, thermal: NativeThermalState = .nominal,
                     lid: NativeLidState = .open, panel: NativePanelState = .awake,
                     external: Int? = 0, start: UInt64 = 1_000_000_000, end: UInt64 = 1_010_000_000) -> NativeSafetyObservation {
        NativeSafetyObservation(bootID: boot, startedAt: start, finishedAt: end, batteryPercent: battery,
            onAC: ac, thermal: thermal, lid: lid, panel: panel, externalOnlineDisplays: external)
    }
    var now: BrokerClockSnapshot { BrokerClockSnapshot(bootID: boot, nowNanos: 1_020_000_000) }

    @Test func freshNominalACOpenAwakePermitsPreflightOnlyAsObservation() {
        #expect(observation().refusal(at: now, stage: .beforeEnable) == nil)
        #expect(observation(lid: .closed, panel: .asleep).refusal(at: now, stage: .beforeEnable) != nil)
        #expect(observation(lid: .closed, panel: .asleep).refusal(at: now, stage: .monitoring) == nil)
    }

    @Test(arguments: [NativeLidState.open, .closed], [NativePanelState.awake, .asleep, .unknown])
    func continuityMonitoringDoesNotClaimOrRequirePanelSleep(_ lid: NativeLidState, _ panel: NativePanelState) {
        let value = observation(lid: lid, panel: panel)
        #expect(value.refusal(at: now, stage: .monitoring) == nil)
        #expect((value.refusal(at: now, stage: .beforeEnable) == nil) == (lid == .open && panel == .awake))
        #expect(value.panel == panel)
    }

    @Test(arguments: ["batteryMissing", "batteryLow", "batteryNaN", "acMissing", "acLost", "thermalFair", "thermalCritical", "thermalUnknown", "lidUnknown", "external", "topologyMissing"])
    func unknownOrUnsafeNeverPermits(_ fault: String) {
        let value = observation(battery: fault == "batteryMissing" ? nil : (fault == "batteryLow" ? 19 : (fault == "batteryNaN" ? .nan : 75)),
            ac: fault == "acMissing" ? nil : fault != "acLost",
            thermal: fault == "thermalFair" ? .fair : (fault == "thermalCritical" ? .critical : (fault == "thermalUnknown" ? .unknown : .nominal)),
            lid: fault == "lidUnknown" ? .unknown : .open,
            panel: .awake,
            external: fault == "topologyMissing" ? nil : (fault == "external" ? 1 : 0))
        #expect(value.refusal(at: now, stage: .beforeEnable) != nil)
        #expect(value.refusal(at: now, stage: .monitoring) != nil)
    }

    @Test(arguments: ["stale", "slow", "regressedEnd", "futureEnd", "bootChanged"])
    func freshnessNeverRestampedAtCompletion(_ fault: String) {
        let value = observation(start: 1_000_000_000,
            end: fault == "slow" ? 1_200_000_001 : (fault == "regressedEnd" ? 999_999_999 : 1_010_000_000))
        let clock = BrokerClockSnapshot(bootID: fault == "bootChanged" ? UUID().uuidString : boot,
            nowNanos: fault == "stale" ? 2_000_000_001 : (fault == "futureEnd" ? 1_009_999_999 : 1_300_000_000))
        #expect(value.refusal(at: clock, stage: .beforeEnable) != nil)
    }

    func calls(battery: [[String: Any]]? = nil, lid: CFTypeRef? = kCFBooleanFalse,
               ids: [UInt32]? = [1], flags: NativeDisplayFlags = .init(builtin: 1, online: 1, asleep: 0)) -> NativeSafetySystemCalls {
        NativeSafetySystemCalls(batteries: { battery }, lidProperty: { lid }, displays: { ids },
            displayFlags: { _ in flags }, thermal: { .nominal })
    }

    @Test func strictBatteryRequiresUniquePresentInternalSourceAndValidNumbers() {
        let good: [String: Any] = ["Type": "InternalBattery", "Is Present": true,
            "Current Capacity": 75, "Max Capacity": 100, "Power Source State": "AC Power"]
        #expect(calls(battery: [good]).batteryAndAC().0 == 75)
        #expect(calls(battery: [good]).batteryAndAC().1 == true)
        #expect(calls(battery: [good, good]).batteryAndAC().0 == nil)
        let badValues: [Any] = [true, -1, 101, Double.nan]
        for bad in badValues {
            var malformed = good; malformed["Current Capacity"] = bad
            #expect(calls(battery: [malformed]).batteryAndAC().0 == nil)
        }
        var absent = good; absent["Is Present"] = false
        #expect(calls(battery: [absent]).batteryAndAC().0 == nil)
        #expect(calls().batteryAndAC().0 == nil)
    }

    @Test(arguments: ["missing", "number", "unknown", "empty"])
    func unclassifiedSecondSourceCannotDisappearFromUniqueness(_ fault: String) {
        let good: [String: Any] = ["Type": "InternalBattery", "Is Present": true,
            "Current Capacity": 75, "Max Capacity": 100, "Power Source State": "AC Power"]
        var other: [String: Any] = [:]
        if fault == "number" { other["Type"] = 3 }
        if fault == "unknown" { other["Type"] = "UnclassifiedDevice" }
        if fault == "empty" { other["Type"] = "" }
        #expect(calls(battery: [good, other]).batteryAndAC().0 == nil)
        #expect(calls(battery: [good, other]).batteryAndAC().1 == nil)
        #expect(calls(battery: [good, ["Type": "UPS"]]).batteryAndAC().0 == 75)
    }

    @Test func panelUnknownDoesNotEraseKnownExternalTopology() {
        #expect(calls(ids: []).panelAndTopology().0 == .unknown)
        #expect(calls(ids: []).panelAndTopology().1 == 0)
        #expect(calls(flags: .init(builtin: 1, online: 1, asleep: 2)).panelAndTopology().0 == .unknown)
        #expect(calls(flags: .init(builtin: 1, online: 1, asleep: 2)).panelAndTopology().1 == 0)
        #expect(calls(ids: [1, 2]).panelAndTopology().0 == .unknown)
        #expect(calls(ids: [1, 2]).panelAndTopology().1 == 0)
        #expect(calls(flags: .init(builtin: 0, online: 1, asleep: 0)).panelAndTopology().0 == .unknown)
        #expect(calls(flags: .init(builtin: 0, online: 1, asleep: 0)).panelAndTopology().1 == 1)
        #expect(calls(flags: .init(builtin: 2, online: 1, asleep: 0)).panelAndTopology().1 == nil)
        #expect(calls(ids: nil).panelAndTopology().1 == nil)
        var reads = 0
        let changing = NativeSafetySystemCalls(batteries: { nil }, lidProperty: { kCFBooleanFalse }, displays: {
            reads += 1; return reads == 1 ? [1] : []
        }, displayFlags: { _ in .init(builtin: 1, online: 1, asleep: 0) }, thermal: { .nominal })
        #expect(changing.panelAndTopology().1 == nil)
    }

    @Test func strictBooleanLidAndPanelReportingRetainUnknown() {
        #expect(calls(lid: kCFBooleanFalse).lidState() == .open)
        #expect(calls(lid: kCFBooleanTrue).lidState() == .closed)
        #expect(calls(lid: NSNumber(value: 1)).lidState() == .unknown)
        #expect(calls(lid: nil).lidState() == .unknown)
        #expect(calls().panelAndTopology().0 == .awake)
        #expect(calls(ids: [1, 1]).panelAndTopology().0 == .unknown)
        #expect(calls(ids: []).panelAndTopology().0 == .unknown)
        #expect(calls(flags: .init(builtin: 1, online: 0, asleep: 1)).panelAndTopology().0 == .unknown)
        #expect(calls(flags: .init(builtin: 1, online: 1, asleep: 2)).panelAndTopology().0 == .unknown)
        #expect(calls(ids: [1, 2]).panelAndTopology().0 == .unknown)
    }
}
