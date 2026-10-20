import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

final class StatusAXFixture: OrcaUIAccess {
    var roles = [0: "AXWindow", 1: "AXTabGroup", 2: "AXRadioButton", 3: "AXRadioButton",
                 4: "AXGroup", 5: "AXImage", 6: "AXTextArea", 7: "AXGroup"]
    var childRows = [0: [1, 6], 1: [6], 2: [4], 3: [5], 6: [7]]
    var tabRows = [2, 3]
    var rectangles = [0: CGRect(x: 0, y: 0, width: 400, height: 300),
                      2: CGRect(x: 0, y: 0, width: 100, height: 30),
                      3: CGRect(x: 100, y: 0, width: 100, height: 30),
                      4: CGRect(x: 5, y: 5, width: 10, height: 10),
                      5: CGRect(x: 105, y: 5, width: 10, height: 10)]
    var labels = [4: "Working", 5: "Idle", 7: "PRIVATE_TRANSCRIPT"]
    var reads: [Int] = []
    var childReads: [Int] = []
    var frameReads: [Int] = []
    var failure: OrcaUIReadError?
    func roots() throws -> [Int] { if let failure { throw failure }; return [0] }
    func role(_ node: Int) throws -> String { roles[node] ?? "AXGroup" }
    func children(_ node: Int) throws -> [Int] { childReads.append(node); return childRows[node] ?? [] }
    func tabs(_ node: Int) throws -> [Int] { tabRows }
    func frame(_ node: Int) throws -> CGRect { frameReads.append(node); return rectangles[node] ?? .zero }
    func statusLabel(_ node: Int) throws -> String? { reads.append(node); return labels[node] }
    func identity(_ tab: Int) throws -> String { "fixture-\(tab)" }
}

@Suite("Outside Orca UI observation", .serialized)
struct OrcaUIObservationTests {
    @Test(arguments: ["Working", "Monitoring background tasks", "Waiting for input", "Needs attention", "Done", "Idle",
                      "Blocked", "Interrupted", "Failed", "No recent update", "Couldn’t confirm", "PRIVATE", "working"])
    func exactAllowlistNeverTreatsArbitraryTextAsWork(_ label: String) {
        let result = OrcaUIState(statusLabel: label)
        let expected: OrcaUIState = ["Working", "Monitoring background tasks"].contains(label) ? .working
            : ["Waiting for input", "Needs attention"].contains(label) ? .waiting
            : ["Done", "Idle"].contains(label) ? .idle : .unknown
        #expect(result == expected)
        #expect(result.taskState != .completed && result.taskState != .failed)
    }

    @Test func onlyTinyTabStatusDescriptionsAreRead() throws {
        let fixture = StatusAXFixture()
        let snapshot = try OrcaUICollector(access: fixture, clock: { 1 }).collect()
        #expect(snapshot.statuses.map(\.state) == [.working, .idle])
        #expect(snapshot.complete && fixture.reads == [4, 5])
        #expect(!fixture.reads.contains(6) && !fixture.reads.contains(7))
    }

    @Test(arguments: ["missing", "outside", "oversize", "ambiguous", "unsupported", "contentTab", "invalidWindow"])
    func unverifiedStatusGeometryOrLabelsRefuse(_ kind: String) {
        let fixture = StatusAXFixture()
        if kind == "missing" { fixture.labels[4] = nil }
        if kind == "contentTab" { fixture.rectangles[2] = CGRect(x: 0, y: 100, width: 100, height: 30) }
        if kind == "invalidWindow" { fixture.rectangles[0] = .zero }
        if kind == "unsupported" { fixture.labels[4] = "PRIVATE_TRANSCRIPT" }
        if kind == "outside" { fixture.rectangles[4] = CGRect(x: 500, y: 500, width: 10, height: 10) }
        if kind == "oversize" { fixture.rectangles[4] = CGRect(x: 5, y: 5, width: 90, height: 20) }
        if kind == "ambiguous" { fixture.childRows[2] = [4, 8]; fixture.roles[8] = "AXImage"; fixture.rectangles[8] = fixture.rectangles[4]; fixture.labels[8] = "Idle" }
        #expect(throws: OrcaUIReadError.self) { try OrcaUICollector(access: fixture, clock: { 1 }).collect() }
        if ["outside", "oversize", "contentTab", "invalidWindow"].contains(kind) { #expect(!fixture.reads.contains(4)) }
    }

    @Test func limitsCyclesPermissionAndClockCannotBecomeEmptySuccess() {
        let fixture = StatusAXFixture()
        var reader = OrcaUICollector(access: fixture, clock: { 1 }); reader.nodeLimit = 2
        #expect(throws: OrcaUIReadError.incomplete) { try reader.collect() }
        fixture.tabRows = Array(repeating: 2, count: 21)
        #expect(throws: OrcaUIReadError.capacity) { try OrcaUICollector(access: fixture, clock: { 1 }).collect() }
        fixture.tabRows = [2, 3]; fixture.childRows[0] = [0]
        #expect(throws: OrcaUIReadError.incomplete) { try OrcaUICollector(access: fixture, clock: { 1 }).collect() }
        fixture.failure = .permissionRequired
        #expect(throws: OrcaUIReadError.permissionRequired) { try OrcaUICollector(access: fixture, clock: { 1 }).collect() }
        fixture.failure = nil
        var time = 0.0
        #expect(throws: OrcaUIReadError.incomplete) {
            try OrcaUICollector(access: fixture, clock: { defer { time += 1 }; return time }).collect()
        }
    }

    @Test func missingTabsInvalidateIdleAndRetainUnknownWithoutClaimingCompletion() throws {
        var tracker = OrcaUITracker(); var store = RuntimeAgentStore()
        func ingest(_ snapshot: OrcaUISnapshot, now: Double) throws {
            for event in try tracker.consume(snapshot, now: now) { _ = try store.ingest(JSONEncoder().encode(event), now: now) }
        }
        try ingest(OrcaUISnapshot(statuses: [OrcaUIStatus(id: "a", state: .working), OrcaUIStatus(id: "b", state: .idle)], complete: true, observedAt: 1), now: 1)
        try ingest(OrcaUISnapshot(statuses: [], complete: false, observedAt: 2), now: 2)
        let unknown = store.tasks(now: 2)
        #expect(unknown.count == 2 && unknown.allSatisfy { $0.state == .unknown })
        let deadline = try #require(unknown.first { $0.runID == "a" }?.unknownUntilMonotonic)
        try ingest(OrcaUISnapshot(statuses: [], complete: false, observedAt: 3), now: 3)
        #expect(store.tasks(now: 3).first { $0.runID == "a" }?.unknownUntilMonotonic == deadline)
        #expect(store.tasks(now: 3).allSatisfy { $0.state != .completed })
    }

    @Test func invalidSnapshotsAreTransactionalAndCapacityCannotDropKnownTabs() throws {
        var tracker = OrcaUITracker()
        let first = OrcaUISnapshot(statuses: [OrcaUIStatus(id: "a", state: .working)], complete: true, observedAt: 1)
        #expect(try tracker.consume(first, now: 1).first?.sequence == 0)
        #expect(throws: OrcaUIReadError.incomplete) { try tracker.consume(first, now: 3) }
        let duplicate = OrcaUISnapshot(statuses: [OrcaUIStatus(id: "a", state: .idle), OrcaUIStatus(id: "a", state: .idle)], complete: true, observedAt: 2)
        #expect(throws: OrcaUIReadError.incomplete) { try tracker.consume(duplicate, now: 2) }
        #expect(try tracker.consume(OrcaUISnapshot(statuses: [OrcaUIStatus(id: "a", state: .idle)], complete: true, observedAt: 2), now: 2).first?.sequence == 1)
        for batch in 0..<4 {
            let count = batch == 3 ? 15 : 16
            let rows = (0..<count).map { OrcaUIStatus(id: "b-\(batch)-\($0)", state: .idle) }
            _ = try tracker.consume(OrcaUISnapshot(statuses: rows, complete: true, observedAt: 3), now: 3)
        }
        #expect(throws: OrcaUIReadError.capacity) {
            try tracker.consume(OrcaUISnapshot(statuses: [OrcaUIStatus(id: "overflow", state: .working)], complete: true, observedAt: 4), now: 4)
        }
        #expect(try tracker.consume(OrcaUISnapshot(statuses: [OrcaUIStatus(id: "a", state: .working)], complete: true, observedAt: 4), now: 4).first { $0.runID == "a" }?.state == .working)
    }

    @Test func testHostCannotInspectNativeAgentUIOrPromptForPermission() {
        #expect(throws: OrcaUIReadError.permissionRequired) { try NativeOrcaUIAccess().read() }
    }

    @Test @MainActor func delayedSnapshotCannotReplaceWorkingWithIdle() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.adapterEnrollment = ["orca"]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else { Issue.record("Fixture enrollment failed"); return }
        app.receiveOrcaUISnapshot(OrcaUISnapshot(statuses: [OrcaUIStatus(id: "a", state: .working)], complete: true, observedAt: ContinuousTime.now))
        // A delayed snapshot is rejected before its receipt can revive evidence.
        app.receiveOrcaUISnapshot(OrcaUISnapshot(statuses: [OrcaUIStatus(id: "a", state: .idle)], complete: true, observedAt: ContinuousTime.now - 200))
        let bytes = try app.handleControl(.status, payload: Data())
        let reply = try JSONDecoder().decode(CamLidCLI.CLIResult.self, from: bytes)
        let object = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        let observation = try #require(object["orcaUIObservation"] as? [String: Any])
        #expect(observation["lastIssue"] as? String == "orcaUIIncomplete")
        #expect(observation["completionCoverageQualified"] as? Bool == false)
        #expect(object["powerActuation"] as? Bool == false)
        #expect(app.sleepRelevantTasks(now: ContinuousTime.now).allSatisfy { $0.state != .idle })
    }

    @Test @MainActor func appReceivesOnlyMetadataAndRefusesProducerIngress() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        var patch = ConfigPatch(); patch.adapterEnrollment = ["orca"]
        guard case .saved = app.applySettingsPatch(patch, expectedRevision: 1) else { Issue.record("Fixture enrollment failed"); return }
        app.receiveOrcaUISnapshot(OrcaUISnapshot(statuses: [OrcaUIStatus(id: "a", state: .working), OrcaUIStatus(id: "b", state: .idle)], complete: true, observedAt: ContinuousTime.now))
        #expect(app.sleepRelevantTasks(now: ContinuousTime.now).filter { $0.state == .working }.count == 1)
        app.receiveOrcaUISnapshot(OrcaUISnapshot(statuses: [], complete: false, observedAt: ContinuousTime.now))
        #expect(app.sleepRelevantTasks(now: ContinuousTime.now).allSatisfy { $0.state == .unknown })
        #expect(throws: IPCError.policyDenied("externalObservationOnly")) { try app.handleControl(.event, payload: Data("PRIVATE".utf8)) }
    }

    @Test func parallelWorkAndFreshWorkCancelGraceWithoutResettingCap() throws {
        var tracker = OrcaUITracker(); var store = RuntimeAgentStore()
        var session = try ProtectionSession(id: "policy", requestedMode: .auto, armedClosedLid: true, startedAtMonotonic: 0, capDeadlineMonotonic: 7200)
        let health = try HealthSnapshot(batteryPercent: 80, powerSource: .ac, thermalPressure: .nominal, cpuPercent: 0,
            lidState: .closed, internalDisplayState: .asleep, capabilityVerified: true)
        let config = try Configuration()
        func update(_ rows: [OrcaUIStatus], now: Double, complete: Bool = true) throws -> PolicyDecision {
            for event in try tracker.consume(OrcaUISnapshot(statuses: rows, complete: complete, observedAt: now), now: now) {
                _ = try store.ingest(JSONEncoder().encode(event), now: now)
            }
            let result = PolicyEngine.evaluate(session: session, tasks: store.tasks(now: now), health: health,
                config: config, armed: true, safety: .clear, recoveryConflict: false, completionUncertain: !complete, nowMonotonic: now)
            session = result.session; return result
        }
        #expect(try update([OrcaUIStatus(id: "a", state: .working), OrcaUIStatus(id: "b", state: .working)], now: 1).state == .protected)
        #expect(try update([OrcaUIStatus(id: "a", state: .idle), OrcaUIStatus(id: "b", state: .working)], now: 2).state == .protected)
        #expect(try update([OrcaUIStatus(id: "a", state: .idle), OrcaUIStatus(id: "b", state: .idle)], now: 3).state == .completionGrace)
        #expect(try update([OrcaUIStatus(id: "a", state: .working), OrcaUIStatus(id: "b", state: .idle)], now: 4).state == .protected)
        #expect(session.graceDeadlineMonotonic == nil && session.capDeadlineMonotonic == 7200)
        let lost = try update([], now: 5, complete: false)
        #expect(!lost.reasons.contains("sleepRequested"))
        let expired = PolicyEngine.evaluate(session: session, tasks: store.tasks(now: 200), health: health,
            config: config, armed: true, safety: .clear, recoveryConflict: false,
            completionUncertain: true, nowMonotonic: 200)
        #expect(expired.state == .ready && !expired.reasons.contains("sleepRequested"))
        #expect(expired.session.graceDeadlineMonotonic == nil)
    }
}
