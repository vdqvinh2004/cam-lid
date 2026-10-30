import AppKit
import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

private final class FakeHoldTransport: PowerHoldTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HoldAction] = []
    private let token = UUID()
    var refuseAcquireWith: String?
    var actions: [HoldAction] { lock.withLock { recorded } }
    func send(_ action: HoldAction) async -> HoldReply? {
        lock.withLock { recorded.append(action) }
        switch action {
        case .acquire:
            if let reason = refuseAcquireWith { return HoldReply(accepted: false, state: "ready", reason: reason) }
            return HoldReply(accepted: true, state: "active", reason: "leaseAcquired", token: token)
        case .renew: return HoldReply(accepted: true, state: "active", reason: "leaseRenewed", token: token)
        case .release: return HoldReply(accepted: true, state: "restored", reason: "restorationVerified")
        }
    }
    func close() {}
}

@MainActor private func settle(_ done: () -> Bool) async {
    for _ in 0..<100 where !done() { try? await Task.sleep(nanoseconds: 50_000_000) }
}

@Suite("Helper hold integration", .serialized)
struct PowerHoldIntegrationTests {
    @MainActor private func rig(row: String?, conflicts: [String] = [],
                                system: @escaping () -> (model: String?, osBuild: String?) = { ("Mac99,1", "99Z1") })
        async throws -> (AppCoordinator, FakeHoldTransport, QARefinementSupport) {
        let support = QARefinementSupport()
        let transport = FakeHoldTransport()
        let helper = HelperController(status: { .installed(loaded: true) }, runAdmin: { _ in
            HelperOperationResult(accepted: false, reason: "cancelled", detail: nil)
        }, conflicts: { conflicts })
        helper.refresh()
        await settle { helper.state == "installed" }
        let app = AppCoordinator(historyDirectory: support.root.appendingPathComponent("history"),
            controlDirectory: support.root.appendingPathComponent("control"),
            preferences: UserDefaults(suiteName: support.suite)!,
            healthReader: { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open) },
            helperController: helper, holdTransportFactory: { transport }, closedLidSupportRow: { row },
            systemIdentity: system)
        var patch = ConfigPatch(); patch.closedLidOptIn = true
        _ = app.applySettingsPatch(patch, expectedRevision: 1)
        app.changeMode(.timed)
        return (app, transport, support)
    }

    @Test @MainActor func aQualifiedRowAcquiresAfterProtectionAndReleasesOnStop() async throws {
        let (app, transport, support) = try await rig(row: "test-row")
        defer { support.cleanup() }
        await app.startPreviewSession()
        await settle { transport.actions.contains { if case .acquire = $0 { true } else { false } } }
        await settle { app.dashboardData().leaseVerified }
        #expect(app.dashboardData().leaseVerified && app.dashboardData().powerActuationAvailable)
        if case .acquire(let seconds)? = transport.actions.first { #expect(seconds <= PowerHoldReconciler.maximumSessionSeconds) }
        app.menuBarStopProtection()
        await settle { transport.actions.contains { if case .release = $0 { true } else { false } } }
        await settle { !app.dashboardData().leaseVerified }
        #expect(transport.actions.contains { if case .release = $0 { true } else { false } })
        #expect(!app.dashboardData().leaseVerified)
    }

    @Test @MainActor func withoutAQualifiedRowNothingReachesTheHelper() async throws {
        let (app, transport, support) = try await rig(row: nil)
        defer { support.cleanup() }
        await app.startPreviewSession()
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(transport.actions.isEmpty)
        #expect(!app.dashboardData().leaseVerified && !app.dashboardData().powerActuationAvailable)
    }

    @Test @MainActor func aHelperRefusalStaysExplainedAfterTheSessionStops() async throws {
        let (app, transport, support) = try await rig(row: "test-row")
        defer { support.cleanup() }
        transport.refuseAcquireWith = "preexistingOverride"
        await app.startPreviewSession()
        await settle { app.dashboardData().state == .safetyStopped }
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(app.dashboardData().state == .safetyStopped)
        #expect(app.dashboardData().bannerMessage?.contains("Another app already disables sleep") == true)
    }

    @Test @MainActor func anAcceptedUntestedMacHoldsAndSaysItIsUntested() async throws {
        let (app, transport, support) = try await rig(row: nil)
        defer { support.cleanup() }
        #expect(app.closedLidPermit() == .notPermitted)
        app.setUntestedAcknowledgement(true)
        #expect(app.closedLidPermit() == .untestedAcknowledged)
        await app.startPreviewSession()
        await settle { app.dashboardData().leaseVerified }
        #expect(transport.actions.contains { if case .acquire = $0 { true } else { false } })
        #expect(app.dashboardData().bannerMessage?.contains("Untested configuration: Mac99,1, macOS 99Z1") == true)
        app.setUntestedAcknowledgement(false)
        #expect(app.closedLidPermit() == .notPermitted)
        await settle { transport.actions.contains { if case .release = $0 { true } else { false } } }
        #expect(transport.actions.contains { if case .release = $0 { true } else { false } })   // withdrawing releases the hold
    }

    @Test @MainActor func aMacOSUpdateVoidsTheAcceptance() async throws {
        final class Build: @unchecked Sendable { var value = "99Z1" }
        let build = Build()
        let (app, _, support) = try await rig(row: nil, system: { ("Mac99,1", build.value) })
        defer { support.cleanup() }
        app.setUntestedAcknowledgement(true)
        #expect(app.closedLidPermit() == .untestedAcknowledged)
        build.value = "99Z2"
        #expect(app.closedLidPermit() == .notPermitted)
    }

    @Test @MainActor func aConflictingHelperIsNamedBeforeTheSessionIsInterrupted() async throws {
        let (app, _, support) = try await rig(row: "test-row", conflicts: ["LidRun"])
        defer { support.cleanup() }
        await app.startPreviewSession()
        await settle { app.dashboardData().bannerMessage?.contains("LidRun") == true }
        #expect(app.dashboardData().bannerMessage?.contains("LidRun resets the sleep setting") == true)
    }

    @Test @MainActor func aSettingChangedUnderTheSessionIsExplained() {
        #expect(AppCoordinator.helperReasonText("overrideChanged").contains("Another app changed the sleep setting"))
    }
}
