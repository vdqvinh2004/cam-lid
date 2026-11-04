import Foundation
import Testing
@testable import CamLidPowerService

/// Records every OS call; never touches power state.
final class FakeClamshellCalls: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var log: [String] = []
    var bit = false
    var failSetBit = false
    var rootDomainGone = false
    var failCreate = false
    var nextID: UInt32 = 41

    func note(_ entry: String) { lock.withLock { log.append(entry) } }
    var calls: ClamshellBitCalls {
        ClamshellBitCalls(
            setBit: { [self] on in note("bit \(on)"); if rootDomainGone { return ClamshellBitCalls.rootDomainMissing }; if failSetBit { return 1 }; bit = on; return 0 },
            createIdleAssertion: { [self] seconds in
                note("create \(Int(seconds.rounded()))")
                if failCreate { return (1, 0) }
                nextID += 1; return (0, nextID)
            },
            setTimeout: { [self] id, seconds in note("timeout \(id) \(Int(seconds.rounded()))"); return 0 },
            release: { [self] id in note("release \(id)"); return 0 })
    }
}

@Suite struct ClamshellBitMechanismTests {
    private func make(_ fake: FakeClamshellCalls, foreign: ForeignPolicyObservation = .clear) -> ClamshellBitMechanism {
        ClamshellBitMechanism(calls: fake.calls, foreignPolicy: { foreign })
    }

    @Test func applyCreatesTheExpiringAssertionBeforeSettingTheBit() throws {
        let fake = FakeClamshellCalls(); let m = make(fake)
        try m.apply(remainingNanos: 30_000_000_000, episodeID: UUID())
        #expect(fake.log == ["create 36", "bit true"])
        #expect(m.applyAcknowledged && fake.bit)
        #expect(try m.readApplied() == nil)   // no getter exists
    }

    @Test func renewalExtendsTheAssertionAndSetsTheBitAgain() throws {
        let fake = FakeClamshellCalls(); let m = make(fake)
        try m.apply(remainingNanos: 30_000_000_000, episodeID: UUID())
        fake.bit = false                       // powerd cleared the shared bit
        try m.prepareRenewal(remainingNanos: 20_000_000_000, episodeID: UUID())
        #expect(fake.log.suffix(2) == ["timeout 42 26", "bit true"])
        #expect(fake.bit)
    }

    @Test func clearIsUnconditionalAndIdempotent() throws {
        let fake = FakeClamshellCalls(); let m = make(fake)
        try m.apply(remainingNanos: 30_000_000_000, episodeID: UUID())
        #expect(try m.clear() == .callsAcknowledgedOnly)
        #expect(fake.log.suffix(2) == ["bit false", "release 42"])
        #expect(try m.clear() == .callsAcknowledgedOnly)   // the recovery job owns no assertion
        #expect(fake.log.last == "bit false" && !fake.bit)
    }

    @Test func clearingWhileTheRootDomainIsGoneCountsAsClearedButApplyDoesNot() throws {
        let fake = FakeClamshellCalls(); let m = make(fake)
        try m.apply(remainingNanos: 30_000_000_000, episodeID: UUID())
        fake.rootDomainGone = true             // shutdown teardown: nothing left to clear, a restart clears the bit
        #expect(try m.clear() == .callsAcknowledgedOnly)
        #expect(fake.log.last == "release 42")
        #expect(throws: PowerServiceFailure.self) { try make(fake).apply(remainingNanos: 30_000_000_000, episodeID: UUID()) }
    }

    @Test func aFailedBitLeavesNothingBehind() throws {
        let fake = FakeClamshellCalls(); let m = make(fake)
        fake.failSetBit = true
        #expect(throws: PowerServiceFailure.self) { try m.apply(remainingNanos: 30_000_000_000, episodeID: UUID()) }
        #expect(!m.applyAcknowledged)
        try m.discardOwnedResourcesAfterFailedApply()
        #expect(fake.log.contains("release 42"))
        let fresh = FakeClamshellCalls(); fresh.failCreate = true
        #expect(throws: PowerServiceFailure.self) { try make(fresh).apply(remainingNanos: 30_000_000_000, episodeID: UUID()) }
        #expect(!fresh.log.contains("bit true"))
    }

    @Test func anotherAppsSleepDisabledRefusesAdmission() throws {
        #expect(try make(FakeClamshellCalls(), foreign: .clear).admissionAllowed())
        #expect(try !make(FakeClamshellCalls(), foreign: .conflicted).admissionAllowed())
    }
}
