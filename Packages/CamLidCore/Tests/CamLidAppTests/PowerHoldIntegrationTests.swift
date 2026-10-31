import AppKit
import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

private final class FakeHoldTransport: PowerHoldTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HoldAction] = []
    private let token = UUID()
    var refuseAcquireWith: String?
    private var closes = 0
    var closed: Bool { lock.withLock { closes > 0 } }
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
    func close() { lock.withLock { closes += 1 } }
}

@MainActor private func settle(_ done: () -> Bool) async {
    for _ in 0..<100 where !done() { try? await Task.sleep(nanoseconds: 50_000_000) }
}

@Suite("Helper hold integration", .serialized)
struct PowerHoldIntegrationTests {
    @MainActor private func rig(row: String?, keepAwake: [KeepAwakeApp] = [],
                                system: @escaping () -> (model: String?, osBuild: String?) = { ("Mac99,1", "99Z1") },
                                lid: @escaping () -> LidState = { .open }, sleep: @escaping () -> Void = {})
        async throws -> (AppCoordinator, FakeHoldTransport, QARefinementSupport) {
        let support = QARefinementSupport()
        let transport = FakeHoldTransport()
        let helper = HelperController(status: { .installed(loaded: true) }, runAdmin: { _ in
            HelperOperationResult(accepted: false, reason: "cancelled", detail: nil)
        }, keepAwakeApps: { keepAwake })
        helper.refresh()
        await settle { helper.state == "installed" }
        let app = AppCoordinator(historyDirectory: support.root.appendingPathComponent("history"),
            controlDirectory: support.root.appendingPathComponent("control"),
            preferences: UserDefaults(suiteName: support.suite)!,
            healthReader: { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: lid()) },
            helperController: helper, holdTransportFactory: { transport }, closedLidSupportRow: { row },
            systemIdentity: system, sleepSystem: sleep)
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

    /// Trial 8: restoring the setting with the lid already closed left the Mac awake; a release then sleeps it.
    @Test(arguments: [LidState.open, .closed])
    @MainActor func releasingWithTheLidClosedSleepsTheMac(_ state: LidState) async throws {
        var lid = LidState.open
        var sleeps = 0
        let (app, transport, support) = try await rig(row: "test-row", lid: { lid }, sleep: { sleeps += 1 })
        defer { support.cleanup() }
        await app.startPreviewSession()
        await settle { app.dashboardData().leaseVerified }
        lid = state
        app.menuBarStopProtection()
        await settle { transport.actions.contains { if case .release = $0 { true } else { false } } }
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(sleeps == (state == .closed ? 1 : 0))
    }

    @Test @MainActor func aHelperRefusalOutranksTheLidRunNotice() async throws {
        let (app, transport, support) = try await rig(row: "test-row", keepAwake: [KeepAwakeApp(name: "LidRun", resetsSleepSetting: true)])
        defer { support.cleanup() }
        transport.refuseAcquireWith = "safetyRefused"
        await app.startPreviewSession()
        await settle { app.dashboardData().state == .safetyStopped }
        await settle { app.dashboardData().bannerMessage?.contains("lid open") == true }
        #expect(app.dashboardData().bannerMessage?.contains("only start with the lid open") == true)
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
        let (app, _, support) = try await rig(row: "test-row", keepAwake: [KeepAwakeApp(name: "LidRun", resetsSleepSetting: true)])
        defer { support.cleanup() }
        await app.startPreviewSession()
        await settle { app.dashboardData().bannerMessage?.contains("LidRun") == true }
        #expect(app.dashboardData().bannerMessage?.contains("LidRun resets the sleep setting") == true)
    }

    @Test @MainActor func aSettingChangedUnderTheSessionIsExplained() {
        #expect(AppCoordinator.helperReasonText("overrideChanged").contains("Another app changed the sleep setting"))
    }

    @Test @MainActor func otherKeepAwakeAppsGetAGeneralNotice() async throws {
        let (app, _, support) = try await rig(row: "test-row", keepAwake: [KeepAwakeApp(name: "Amphetamine", resetsSleepSetting: false)])
        defer { support.cleanup() }
        await app.startPreviewSession()
        await settle { app.dashboardData().bannerMessage?.contains("Amphetamine") == true }
        #expect(app.dashboardData().bannerMessage?.contains("Another keep-awake app is running (Amphetamine)") == true)
    }

    @Test @MainActor func theNoticeLineTellsWhetherThisMacCanKeepAwake() async throws {
        let (untested, _, a) = try await rig(row: nil)
        defer { a.cleanup() }
        #expect(untested.closedLidCapabilityText == "Can’t keep your Mac awake · this Mac isn’t tested")
        untested.setUntestedAcknowledgement(true)
        #expect(untested.closedLidCapabilityText == "Closed lid ready · untested Mac")
        #expect(untested.dashboardData().capabilityText == "Closed lid ready · untested Mac")
        let (tested, _, b) = try await rig(row: "test-row")
        defer { b.cleanup() }
        #expect(tested.closedLidCapabilityText == "Closed lid ready · tested Mac")
    }

    @Test @MainActor func helperReasonsNeverShowARawCode() {
        for code in ["notReady", "invalidLease", "renewalRefused", "heartbeatExpired", "safetyStop", "sessionExpired",
                     "startupInspectionFailed", "restorationFailed", "clientDisconnected", "monitorFailed", "somethingNew"] {
            let text = AppCoordinator.helperReasonText(code)
            #expect(!text.contains(code), "raw code shown for \(code): \(text)")
        }
        #expect(AppCoordinator.helperReasonText("somethingNew") == "Closed lid stopped.")
    }

    @Test @MainActor func settingsAndTheUntestedAcceptanceSurviveAnAppRestart() async throws {
        let support = QARefinementSupport()
        defer { support.cleanup() }
        let helper = HelperController(status: { .installed(loaded: true) }, runAdmin: { _ in
            HelperOperationResult(accepted: false, reason: "cancelled", detail: nil) }, keepAwakeApps: { [] })
        helper.refresh()
        await settle { helper.state == "installed" }
        func launch() -> AppCoordinator {
            AppCoordinator(historyDirectory: support.root.appendingPathComponent("history"),
                controlDirectory: support.root.appendingPathComponent("control"),
                preferences: UserDefaults(suiteName: support.suite)!,
                healthReader: { try! HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, lidState: .open) },
                helperController: helper, holdTransportFactory: { FakeHoldTransport() }, closedLidSupportRow: { nil },
                systemIdentity: { ("Mac99,1", "99Z1") })
        }
        let first = launch()
        var patch = ConfigPatch(); patch.closedLidOptIn = true; patch.completionDelayMinutes = 7
        guard case .saved = first.applySettingsPatch(patch, expectedRevision: 1) else { Issue.record("settings not saved"); return }
        first.changeMode(.timed)
        first.setUntestedAcknowledgement(true)

        let second = launch()                                   // same storage, as after quitting and reopening
        #expect(second.closedLidCapabilityText == "Closed lid ready · untested Mac")
        #expect(second.dashboardData().mode == .timed)
        #expect(second.dashboardData().state != .protected)     // a session is never resumed by a restart
    }

    @Test @MainActor func cliStartUsesTheDashboardPathAndReportsHonestly() async throws {
        let (app, transport, support) = try await rig(row: "test-row")
        defer { support.cleanup() }
        func object(_ r: CLIResult) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(r.json.utf8))) as? [String: Any] ?? [:] }
        func options(_ flags: [String: String]) -> Data { try! JSONEncoder().encode(CLIOptions(flags: flags)) }
        #expect(await app.startFromControl(options(["mode": "off"])).exitCode == 2)
        #expect(await app.startFromControl(options(["mode": "timed", "duration": "0m"])).exitCode == 2)
        let started = await app.startFromControl(options(["mode": "timed", "duration": "30m"]))
        #expect(started.exitCode == 0)
        #expect(object(started)["mode"] as? String == "timed" && object(started)["closedLidPermit"] as? String == "qualified:test-row")
        #expect(app.dashboardData().timerMinutes == 30)
        await settle { transport.actions.contains { if case .acquire = $0 { true } else { false } } }
        let again = await app.startFromControl(Data())
        #expect(again.exitCode == 3 && object(again)["reason"] as? String == "sessionAlreadyActive")
    }

    @Test @MainActor func cliStartRefusesAnUntestedMacWithAReason() async throws {
        let (app, transport, support) = try await rig(row: nil)
        defer { support.cleanup() }
        let refused = await app.startFromControl(Data())
        let object = (try? JSONSerialization.jsonObject(with: Data(refused.json.utf8))) as? [String: Any] ?? [:]
        #expect(refused.exitCode == 3 && object["reason"] as? String == "closedLidNotPermitted")
        #expect(transport.actions.isEmpty)
    }

    /// 003 T022: quitting while the helper holds the Mac awake closes the connection, which makes the helper restore.
    @Test @MainActor func quittingWithAHeldLeaseClosesTheHelperConnection() async throws {
        let (app, transport, support) = try await rig(row: "test-row")
        defer { support.cleanup() }
        #expect(app.releaseHoldForQuit() == "noPowerResourcesOwned")
        await app.startPreviewSession()
        await settle { app.dashboardData().leaseVerified }
        #expect(app.releaseHoldForQuit() == "helperRestoresOnDisconnect")
        #expect(transport.closed)
    }
}
