import Foundation
import Testing
@testable import CamLidApp

@MainActor private final class ProbeStub: UpdateProbeDriver {
    var checks = 0
    var failToStart = false
    var completion: (@MainActor (UpdateProbeOutcome) -> Void)?
    func checkInformation(completion: @escaping @MainActor (UpdateProbeOutcome) -> Void) throws {
        checks += 1
        if failToStart { throw NSError(domain: "fixture", code: 1) }
        self.completion = completion
    }
    func finish(_ outcome: UpdateProbeOutcome) { let callback = completion; completion = nil; callback?(outcome) }
}
@MainActor private final class UpdateContextBox { var value = UpdateSafetyContext() }

@Suite("M5 information-only updates") @MainActor
struct UpdateControllerTests {
    private var eligible: UpdateEligibility {
        UpdateEligibility(feedURL: "https://updates.example.invalid/appcast.xml",
                          publicKey: Data(repeating: 1, count: 32).base64EncodedString(), developerIDSigned: true)
    }
    @Test func missingTrustNeverConstructsDriver() {
        var constructions = 0
        let controller = UpdateController(eligibility: .init(feedURL: nil, publicKey: nil, developerIDSigned: false),
            safety: { UpdateSafetyContext() }, makeDriver: { constructions += 1; return ProbeStub() })
        controller.check(); controller.refreshSafety()
        #expect(constructions == 0)
        #expect(controller.snapshot.phase == .unavailable)
        #expect(!controller.snapshot.installationAvailable)
        #expect(!UpdateEligibility.bundle(.main).permitsCheck)
    }
    @Test func invalidDistributionConfigurationRejects() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        for feed in [nil, "http://example.invalid/feed", "https://user:secret@example.invalid/feed", "https://example.invalid/feed#fragment"] {
            #expect(!UpdateEligibility(feedURL: feed, publicKey: key, developerIDSigned: true).permitsCheck)
        }
        for value in [nil, "bad", Data(repeating: 1, count: 31).base64EncodedString()] {
            #expect(!UpdateEligibility(feedURL: "https://example.invalid/feed", publicKey: value, developerIDSigned: true).permitsCheck)
        }
    }
    @Test func blockersDeferOneExplicitRequest() {
        for key in [\UpdateSafetyContext.sessionActive, \.agentWorkActive, \.recoveryRequired, \.unsavedSettings] {
            let box = UpdateContextBox(); box.value[keyPath: key] = true
            let driver = ProbeStub()
            let controller = UpdateController(eligibility: eligible, safety: { box.value }, makeDriver: { driver })
            controller.check(); controller.refreshSafety()
            #expect(controller.snapshot.phase == .deferred)
            #expect(driver.checks == 0)
            box.value[keyPath: key] = false; controller.refreshSafety()
            #expect(driver.checks == 1)
            driver.finish(.current); controller.refreshSafety()
            #expect(controller.snapshot.phase == .current)
            #expect(driver.checks == 1)
        }
    }
    @Test func activityAppearingDuringCheckDefersResult() {
        let box = UpdateContextBox(); let driver = ProbeStub()
        let controller = UpdateController(eligibility: eligible, safety: { box.value }, makeDriver: { driver })
        controller.check(); box.value.agentWorkActive = true; controller.refreshSafety()
        driver.finish(.available("2.0"))
        #expect(controller.snapshot.phase == .deferred)
        box.value.agentWorkActive = false; controller.refreshSafety()
        #expect(controller.snapshot.phase == .available)
        #expect(controller.snapshot.version == "2.0")
        #expect(driver.checks == 1)
        #expect(!controller.snapshot.installationAvailable)
    }
    @Test func repeatedClicksDoNotQueueChecks() {
        let driver = ProbeStub()
        let controller = UpdateController(eligibility: eligible, safety: { UpdateSafetyContext() }, makeDriver: { driver })
        controller.check(); controller.check(); controller.check(); driver.finish(.current); controller.refreshSafety()
        #expect(driver.checks == 1)
    }
    @Test func outcomesAndRetryNeverInventCurrent() {
        for (outcome, phase) in [(UpdateProbeOutcome.current, UpdatePhase.current), (.available("2"), .available),
                                  (.noCompatibleUpdate, .unavailable), (.offline, .offline), (.failed, .error)] {
            let driver = ProbeStub()
            let controller = UpdateController(eligibility: eligible, safety: { UpdateSafetyContext() }, makeDriver: { driver })
            controller.check(); driver.finish(outcome)
            #expect(controller.snapshot.phase == phase)
            #expect(!controller.snapshot.installationAvailable)
            #expect(controller.canCheck)
            controller.check(); #expect(driver.checks == 2)
        }
    }
    @Test func failedStartCanBeRetried() {
        let driver = ProbeStub(); driver.failToStart = true
        let controller = UpdateController(eligibility: eligible, safety: { UpdateSafetyContext() }, makeDriver: { driver })
        controller.check(); #expect(controller.snapshot.phase == .error)
        driver.failToStart = false; controller.check(); driver.finish(.current)
        #expect(controller.snapshot.phase == .current)
    }
}
