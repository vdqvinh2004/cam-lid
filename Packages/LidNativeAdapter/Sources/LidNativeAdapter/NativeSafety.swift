import Foundation
@_spi(TestInputs) import LidRecoveryBroker

@_spi(TestInputs)
public enum NativeThermalState: String, Codable, Sendable { case nominal, fair, serious, critical, unknown }
@_spi(TestInputs)
public enum NativeLidState: String, Codable, Sendable { case open, closed, unknown }
@_spi(TestInputs)
public enum NativePanelState: String, Codable, Sendable { case awake, asleep, unknown }

@_spi(TestInputs)
public struct NativeSafetyObservation: Codable, Sendable {
    public let bootID: String
    public let startedAt: UInt64
    public let finishedAt: UInt64
    public let batteryPercent: Double?
    public let onAC: Bool?
    public let thermal: NativeThermalState
    public let lid: NativeLidState
    public let panel: NativePanelState
    public let externalOnlineDisplays: Int?

    public init(bootID: String, startedAt: UInt64, finishedAt: UInt64, batteryPercent: Double?,
                onAC: Bool?, thermal: NativeThermalState, lid: NativeLidState,
                panel: NativePanelState, externalOnlineDisplays: Int?) {
        self.bootID = bootID; self.startedAt = startedAt; self.finishedAt = finishedAt
        self.batteryPercent = batteryPercent; self.onAC = onAC; self.thermal = thermal
        self.lid = lid; self.panel = panel; self.externalOnlineDisplays = externalOnlineDisplays
    }

    public func refusal(at now: BrokerClockSnapshot, stage: EpisodeSafetyStage) -> String? {
        guard UUID(uuidString: bootID) != nil, bootID == now.bootID else { return "bootUnknownOrChanged" }
        guard finishedAt >= startedAt, now.nowNanos >= finishedAt,
              finishedAt - startedAt <= 200_000_000, now.nowNanos - startedAt <= 1_000_000_000 else {
            return "staleSlowOrRegressedRead"
        }
        guard let batteryPercent, batteryPercent.isFinite, batteryPercent >= 20,
              batteryPercent <= 100 else { return "batteryUnknownOrBelowFloor" }
        guard onAC == true else { return "acUnknownOrDisconnected" }
        // Attended lab row is deliberately stricter than the production serious/critical exits.
        guard thermal == .nominal else { return "thermalUnknownOrNonNominal" }
        guard externalOnlineDisplays == 0 else { return "externalTopologyUnknownOrPresent" }
        if stage == .beforeEnable {
            guard lid == .open, panel == .awake else { return "preflightRequiresOpenAwake" }
        } else {
            // Continuity-only scope records panel state without claiming display sleep.
            guard lid != .unknown else { return "lidUnknown" }
        }
        return nil
    }
}
