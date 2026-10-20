import Foundation
import Testing
import CamLidCLI
import CamLidCore
@testable import CamLidApp

@Suite("M8 outcome alerts") struct OutcomeNotificationsTests {
    @Test @MainActor func returningToSettingsRefreshesPermissionWithoutPrompting() async throws {
        var status = "authorized", reads = 0
        let service = OutcomeNotifications(supported: true, readPermission: {
            reads += 1; return status
        }, requestPermission: { Issue.record("Settings activation must not request permission") }, deliver: { _ in })
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator(outcomeNotifications: service)
        app.receiveUtilityEvent(.visibility(dashboard: false, settings: true))
        for _ in 0..<20 { await Task.yield() }
        #expect(service.permission == "authorized" && reads == 1)
        status = "denied"
        app.receiveUtilityEvent(.visibility(dashboard: true, settings: false))
        for _ in 0..<20 { await Task.yield() }
        #expect(reads == 1)
        app.receiveUtilityEvent(.visibility(dashboard: false, settings: true))
        for _ in 0..<20 { await Task.yield() }
        #expect(service.permission == "denied" && reads == 2)
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let object = try JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as! [String: Any]
        #expect(object["activeSessionMode"] is NSNull && object["powerActuation"] as? Bool == false)
    }
    @Test @MainActor func reorderedTerminalEventAlertsForTheAppliedTask() async throws {
        var titles: [String] = []
        let service = OutcomeNotifications(supported: true, readPermission: { "authorized" },
            requestPermission: { Issue.record("Control events must not request authorization") },
            deliver: { titles.append($0.content.title) })
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator(outcomeNotifications: service)
        var patch = ConfigPatch(); patch.notificationCategories = [.failure]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Could not enable fixture alerts"); return
        }
        let buffered = try app.receiveObservation(event(state: .failed, sequence: 1))
        #expect(buffered == "buffered")
        for _ in 0..<20 { await Task.yield() }
        #expect(titles.isEmpty)
        let applied = try app.receiveObservation(event(state: .working, sequence: 0))
        #expect(applied == "applied")
        for _ in 0..<20 { await Task.yield() }
        #expect(titles == ["CamLid Preview: Work failed"])
        #expect(throws: IPCError.self) { try app.receiveObservation(event(state: .failed, sequence: 1)) }
        for _ in 0..<20 { await Task.yield() }
        #expect(titles.count == 1)
        _ = try await app.handleControlAsync(.logsExport, payload: Data(), deadline: ContinuousTime.now + 2)
    }

    @Test @MainActor func distinctEpochsAndRunTuplesCanAlertWithoutReplayingOldHistory() async throws {
        var deliveries = 0
        let service = OutcomeNotifications(supported: true, readPermission: { "authorized" },
            requestPermission: {}, deliver: { _ in deliveries += 1 })
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator(outcomeNotifications: service)
        var patch = ConfigPatch(); patch.notificationCategories = [.failure]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Could not enable fixture alerts"); return
        }
        let events = [try event(state: .failed, sequence: 0),
            try event(state: .failed, sequence: 0, epoch: 1),
            try event(state: .failed, sequence: 0, sessionID: "left:right", runID: "last"),
            try event(state: .failed, sequence: 0, sessionID: "left", runID: "right:last")]
        for (index, payload) in events.enumerated() {
            _ = try app.receiveObservation(payload)
            for _ in 0..<20 { await Task.yield() }
            #expect(deliveries == index + 1)
        }
        _ = try await app.handleControlAsync(.logsExport, payload: Data(), deadline: ContinuousTime.now + 2)
    }

    @Test @MainActor func processEvidenceCannotClaimTerminalWorkAlerts() async throws {
        var deliveries = 0
        let service = OutcomeNotifications(supported: true, readPermission: { "authorized" },
            requestPermission: {}, deliver: { _ in deliveries += 1 })
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator(outcomeNotifications: service)
        var patch = ConfigPatch(); patch.notificationCategories = [.failure, .completion]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else {
            Issue.record("Could not enable fixture alerts"); return
        }
        for state in [TaskState.failed, .completed] {
            _ = try app.receiveObservation(event(state: state, sequence: 0,
                runID: state.rawValue, evidenceKind: .process))
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(deliveries == 0)
        _ = try await app.handleControlAsync(.logsExport, payload: Data(), deadline: ContinuousTime.now + 2)
    }

    private func event(state: TaskState, sequence: Int, epoch: Int = 0,
                       sessionID: String = "notification-fixture", runID: String = "run",
                       evidenceKind: EvidenceKind = .lifecycle) throws -> NormalizedEvent {
        try NormalizedEvent(provider: "codex", sessionID: sessionID,
            runID: runID, state: state, evidenceKind: evidenceKind,
            confidence: evidenceKind == .process ? .inferred : .exact,
            sequence: sequence, epoch: epoch, receivedMonotonic: 0)
    }

    @Test @MainActor func permissionDenialRevocationAndExplicitConsent() async {
        var status = "notDetermined", requests = 0, deliveries = 0
        let service = OutcomeNotifications(supported: true, readPermission: { status }, requestPermission: {
            requests += 1; status = "denied"
        }, deliver: { _ in deliveries += 1 })
        service.configure(categories: [.safety])
        await service.refresh()
        #expect(requests == 0 && service.permission == "notDetermined")
        await service.authorizeFromUserAction(); await service.authorizeFromUserAction()
        #expect(requests == 1 && service.permission == "denied")
        service.emit(category: .safety, session: "s", event: "denied", reason: "thermal", preview: true, now: 0)
        for _ in 0..<20 { await Task.yield() }
        #expect(deliveries == 0)
        status = "authorized"
        service.emit(category: .safety, session: "s", event: "approved", reason: "thermal", preview: true, now: 1)
        for _ in 0..<20 { await Task.yield() }
        #expect(deliveries == 1)
        status = "denied"
        service.emit(category: .safety, session: "s", event: "revoked", reason: "battery", preview: true, now: 2)
        for _ in 0..<20 { await Task.yield() }
        #expect(deliveries == 1)
        let copy = OutcomeNotifications.content(category: .completion, preview: true)
        #expect(copy.title.hasPrefix("CamLid Preview") && copy.body.contains("No power or sleep change"))
    }
    @Test func criticalAlertSurvivesOrdinaryBudgetAndReplay() {
        var gate = NotificationBudget()
        for index in 0..<5 { let allowed = gate.admit(session: "s", event: "e\(index)", category: .completion, reason: "done", now: 0); #expect(allowed) }
        let duplicate = gate.admit(session: "s", event: "e0", category: .completion, reason: "done", now: 0.5)
        #expect(!duplicate)
        let decision1 = gate.admit(session: "s", event: "six", category: .completion, reason: "done", now: 1)
        #expect(!decision1)
        let decision2 = gate.admit(session: "s", event: "critical", category: .safety, reason: "thermalCritical", now: 1)
        #expect(decision2)
        let decision3 = gate.admit(session: "s", event: "replayed", category: .safety, reason: "thermalCritical", now: 2)
        #expect(!decision3)
        let decision4 = gate.admit(session: "s", event: "later", category: .completion, reason: "done", now: 601)
        #expect(decision4)
    }
    @Test func missingCategoriesOffAndInvalidPatchRejected() throws {
        let old = try Configuration()
        #expect(old.notificationCategories == nil)
        #expect(try Configuration.migrate(from: ["notificationCategories": ["safety"], "mode": "auto"]).notificationCategories == [.safety])
        #expect(try Configuration.migrate(from: ["notificationCategories": ["safety"], "mode": "auto"]).mode == .off)
        var patch = ConfigPatch(); patch.notificationCategories = [.safety]
        #expect(try old.applying(patch).notificationCategories == [.safety])
        #expect(throws: ConfigError.self) { try ConfigPatch(jsonDictionary: ["notificationCategories": ["arbitrary"]]) }
        #expect(throws: ConfigError.self) { try ConfigPatch(jsonDictionary: ["notificationCategories": NSNull()]) }
    }
}
