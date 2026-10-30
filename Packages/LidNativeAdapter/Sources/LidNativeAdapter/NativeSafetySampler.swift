import Foundation
import Dispatch
@_spi(TestInputs) import LidRecoveryBroker

@_spi(TestInputs)
public struct NativeSafetyAssessment: Codable, Sendable {
    public let observation: NativeSafetyObservation?
    public let refusal: String?
    public var allowed: Bool { refusal == nil }
}

/// One read-only worker; a hung read never queues another or makes stale cache safe.
@_spi(TestInputs)
public final class NativeSafetySampler: EpisodeSafetySource, @unchecked Sendable {
    private let calls: NativeSafetySystemCalls
    private let clock: @Sendable () throws -> BrokerClockSnapshot
    private let worker = DispatchQueue(label: "dev.camlid.lab-readonly-safety", qos: .utility)
    private let lock = NSLock()
    private var cached: NativeSafetyObservation?
    private var inFlight = false
    private var lastStarted: BrokerClockSnapshot?
    private var readFailure = "samplePending"

    public init(systemCalls: NativeSafetySystemCalls, clock: @escaping @Sendable () throws -> BrokerClockSnapshot) {
        calls = systemCalls; self.clock = clock
    }

    private func refresh(at now: BrokerClockSnapshot) {
        let start = lock.withLock { () -> Bool in
            guard !inFlight else { return false }
            if let previous = lastStarted, previous.bootID == now.bootID,
               now.nowNanos >= previous.nowNanos, now.nowNanos - previous.nowNanos < 100_000_000 { return false }
            inFlight = true; lastStarted = now
            return true
        }
        guard start else { return }
        worker.async { [self] in
            var observation: NativeSafetyObservation?
            var reason = "readUnavailable"
            do {
                let before = try clock()
                let (battery, ac) = calls.batteryAndAC()
                let lid = calls.lidState()
                let (panel, external) = calls.panelAndTopology()
                let thermal = calls.thermal()
                let after = try clock()
                guard before.bootID == after.bootID else { throw BrokerFailure.bootChanged }
                observation = NativeSafetyObservation(bootID: before.bootID, startedAt: before.nowNanos,
                    finishedAt: after.nowNanos, batteryPercent: battery, onAC: ac, thermal: thermal,
                    lid: lid, panel: panel, externalOnlineDisplays: external)
                reason = "samplePending"
            } catch { reason = "readClockUnavailableOrChanged" }
            lock.withLock { cached = observation; readFailure = reason; inFlight = false }
        }
    }

    public func assessment(at now: BrokerClockSnapshot, stage: EpisodeSafetyStage) -> NativeSafetyAssessment {
        // Cheap fresh ProcessInfo observation bypasses a hung hardware worker; never hold its control lock over OS reads.
        let currentThermal = calls.thermal()
        refresh(at: now)
        let (observation, reason) = lock.withLock { (cached, readFailure) }
        guard currentThermal == .nominal else {
            return NativeSafetyAssessment(observation: observation, refusal: "currentThermalUnknownOrNonNominal")
        }
        // Thermal/lock/refresh work may stall: never validate with the caller's pre-read clock.
        let checked: BrokerClockSnapshot
        do { checked = try clock() }
        catch { return NativeSafetyAssessment(observation: observation, refusal: "assessmentClockUnavailable") }
        guard checked.bootID == now.bootID, checked.nowNanos >= now.nowNanos else {
            return NativeSafetyAssessment(observation: observation, refusal: "assessmentClockChangedOrRegressed")
        }
        guard checked.nowNanos - now.nowNanos <= 200_000_000 else {
            return NativeSafetyAssessment(observation: observation, refusal: "staleSlowOrRegressedRead")
        }
        guard let observation else { return NativeSafetyAssessment(observation: nil, refusal: reason) }
        return NativeSafetyAssessment(observation: observation, refusal: observation.refusal(at: checked, stage: stage))
    }

    public func allows(_ clock: BrokerClockSnapshot, stage: EpisodeSafetyStage) -> Bool {
        assessment(at: clock, stage: stage).allowed
    }
}
