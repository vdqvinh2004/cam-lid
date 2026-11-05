import Foundation
import Testing

@testable import CamLidCore

@Suite("Protection readiness projection")
struct ProtectionReadinessProjectionTests {
    @Test("each missing proof gate prevents Protected")
    func everyProofGateIsRequired() {
        var cases: [ProtectionReadinessFacts] = []

        var facts = eligibleFacts(); facts.buildKind = .development; cases.append(facts)
        facts = eligibleFacts(); facts.supportRowID = nil; cases.append(facts)
        facts = eligibleFacts(); facts.supportRowQualified = false; cases.append(facts)
        facts = eligibleFacts(); facts.helperTrusted = false; cases.append(facts)
        facts = eligibleFacts(); facts.helperAvailable = false; cases.append(facts)
        facts = eligibleFacts(); facts.recoveryRequired = true; cases.append(facts)
        facts = eligibleFacts(); facts.recoveryJournalReady = false; cases.append(facts)
        facts = eligibleFacts(); facts.ownershipEvidence = .unknown; cases.append(facts)
        facts = eligibleFacts(); facts.ownershipEvidence = .conflict; cases.append(facts)
        facts = eligibleFacts(); facts.ownershipEvidence = .noExternalOverride; cases.append(facts)
        facts = eligibleFacts(); facts.backendVerified = false; cases.append(facts)
        facts = eligibleFacts(); facts.leaseVerified = false; cases.append(facts)
        facts = eligibleFacts(); facts.safetyQualifying = false; cases.append(facts)
        facts = eligibleFacts(); facts.requestedClosedLidIntent = false; cases.append(facts)

        for candidate in cases {
            #expect(ProtectionReadiness(facts: candidate).state != .protected)
        }
        #expect(ProtectionReadiness(facts: eligibleFacts()).state == .protected)
    }

    @Test("recovery, conflict, trust, qualification, setup, then readiness priority")
    func statePriorityIsStable() {
        var facts = eligibleFacts()
        #expect(ProtectionReadiness(facts: facts).state == .protected)

        facts.recoveryRequired = true
        facts.helperTrusted = false
        facts.ownershipEvidence = .conflict
        #expect(ProtectionReadiness(facts: facts).state == .recoveryRequired)

        facts.recoveryRequired = false
        #expect(ProtectionReadiness(facts: facts).state == .conflict)

        facts.ownershipEvidence = .verifiedCamLidOwnership
        facts.buildKind = .development
        #expect(ProtectionReadiness(facts: facts).state == .needsSetup)

        facts.helperTrusted = true
        facts.helperAvailable = false
        #expect(ProtectionReadiness(facts: facts).state == .untestedConfiguration)

        facts.buildKind = .release
        #expect(ProtectionReadiness(facts: facts).state == .needsSetup)
    }

    @Test("a release build without a verified lease is Ready and names the missing lease")
    func withoutLeaseItIsReadyWithAReason() {
        var facts = eligibleFacts()
        facts.leaseVerified = false
        let result = ProtectionReadiness(facts: facts)
        #expect(result.state == .ready)
        #expect(result.blockerCodes.contains("leaseNotVerified"))
    }

    @Test("unknown ownership without a helper is setup, not a conflict")
    func unknownOwnershipWithoutHelperNeedsSetup() {
        var facts = eligibleFacts()
        facts.ownershipEvidence = .unknown
        facts.helperTrusted = false
        let result = ProtectionReadiness(facts: facts)
        #expect(result.state == .needsSetup)
        #expect(result.blockerCodes.contains("externalOwnershipUnknown"))
    }

    @Test("matching global value without ownership evidence remains a conflict")
    func matchingValueDoesNotProveOwnership() {
        var facts = eligibleFacts()
        facts.matchingGlobalOverrideObserved = true
        facts.ownershipEvidence = .unknown
        var result = ProtectionReadiness(facts: facts)
        #expect(result.state == .conflict)
        #expect(result.blockerCodes.contains("externalOwnershipUnknown"))

        facts.ownershipEvidence = .noExternalOverride
        result = ProtectionReadiness(facts: facts)
        #expect(result.state == .conflict)
        #expect(result.blockerCodes.contains("externalOwnershipUnknown"))

        facts.ownershipEvidence = .verifiedCamLidOwnership
        result = ProtectionReadiness(facts: facts)
        #expect(result.state == .protected)
        #expect(!result.blockerCodes.contains("externalOwnershipUnknown"))
    }

    @Test("unqualified support row encodes an explicit null with useful blocker copy")
    func nullSupportRowIsExplicit() throws {
        var facts = eligibleFacts()
        facts.supportRowID = nil
        facts.supportRowQualified = false
        let result = ProtectionReadiness(facts: facts)

        let data = try JSONEncoder().encode(result)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.keys.contains("supportRowID"))
        #expect(object["supportRowID"] is NSNull)
        #expect(result.blockerCodes.contains("supportRowUnqualified"))
        #expect(result.blockerDetail?.isEmpty == false)
        #expect(result.blockerDetails.count == result.blockerCodes.count)

        let roundTrip = try JSONDecoder().decode(ProtectionReadiness.self, from: data)
        #expect(roundTrip == result)
    }
}

private func eligibleFacts() -> ProtectionReadinessFacts {
    ProtectionReadinessFacts(
        buildKind: .release,
        supportRowID: "macbook-m4-macos-qualified-26A434",
        supportRowQualified: true,
        helperTrusted: true,
        helperAvailable: true,
        recoveryRequired: false,
        recoveryJournalReady: true,
        ownershipEvidence: .verifiedCamLidOwnership,
        matchingGlobalOverrideObserved: true,
        backendVerified: true,
        leaseVerified: true,
        safetyQualifying: true,
        requestedClosedLidIntent: true
    )
}
