import AppKit
import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

private final class FakeHoldTransport: PowerHoldTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HoldAction] = []
    private let token = UUID()
    var actions: [HoldAction] { lock.withLock { recorded } }
    func send(_ action: HoldAction) async -> HoldReply? {
        lock.withLock { recorded.append(action) }
        switch action {
        case .acquire: return HoldReply(accepted: true, state: "active", reason: "leaseAcquired", token: token)
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
    @MainActor private func rig(row: String?) async throws -> (AppCoordinator, FakeHoldTransport, QARefinementSupport) {
        let support = QARefinementSupport()
        let transport = FakeHoldTransport()
        let helper = HelperController(status: { .installed(loaded: true) }, runAdmin: { _ in
            HelperOperationResult(accepted: false, reason: "cancelled", detail: nil)
        })
        helper.refresh()
        await settle { helper.state == "installed" }
        let app = AppCoordinator(historyDirectory: support.root.appendingPathComponent("history"),
            controlDirectory: support.root.appendingPathComponent("control"),
            preferences: UserDefaults(suiteName: support.suite)!,
            healthReader: { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open) },
            helperController: helper, holdTransportFactory: { transport }, closedLidSupportRow: { row })
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
}
