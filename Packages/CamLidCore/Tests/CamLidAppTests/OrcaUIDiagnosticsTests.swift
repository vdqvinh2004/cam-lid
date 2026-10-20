import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

@Suite("Bounded Orca UI read diagnostics") struct OrcaUIDiagnosticsTests {
    @Test func diagnosticsIdentifyBoundsWithoutReadingMoreContent() throws {
        let fixture = StatusAXFixture()
        var stage = "", visited = -1
        var reader = OrcaUICollector(access: fixture, clock: { 1 }, reportStage: { stage = $0; visited = $1 })
        reader.nodeLimit = 2
        #expect(throws: OrcaUIReadError.incomplete) { try reader.collect() }
        #expect(stage == "nodeLimit" && visited == 2 && fixture.reads.isEmpty)
        reader.nodeLimit = 256
        let snapshot = try reader.collect()
        #expect(stage == "complete" && visited == 7 && snapshot.statuses.count == 2)
        #expect(fixture.reads == [4, 5] && !stage.contains("PRIVATE_TRANSCRIPT"))
    }

    @Test(arguments: ["clock", "windowGeometry", "cycle", "statusControlCount"]) func failureStagesRetainUnknownPolicy(_ kind: String) {
        let fixture = StatusAXFixture()
        var stage = "", calls = 0
        if kind == "windowGeometry" { fixture.rectangles[0] = .zero }
        if kind == "cycle" { fixture.childRows[0] = [0] }
        if kind == "statusControlCount" { fixture.labels[4] = nil }
        let reader = OrcaUICollector(access: fixture, clock: {
            calls += 1
            return kind == "clock" && calls > 1 ? 2 : 1
        }, reportStage: { value, _ in stage = value })
        #expect(throws: OrcaUIReadError.self) { try reader.collect() }
        #expect(stage == (kind == "clock" ? "readDeadline" : kind))
        #expect(!fixture.reads.contains(6) && !fixture.reads.contains(7))
    }

    @Test(arguments: ["AXGroup", "AXWebArea", "AXScrollArea", "AXSplitGroup"])
    func outsideHeaderBranchesArePrunedBeforeChildren(_ role: String) throws {
        let fixture = StatusAXFixture()
        fixture.childRows[0] = [8, 1, 6]
        fixture.roles[8] = role
        fixture.rectangles[8] = CGRect(x: 0, y: 100, width: 400, height: 200)
        fixture.childRows[8] = [9]
        fixture.roles[9] = "AXGroup"
        fixture.labels[9] = "PRIVATE_TRANSCRIPT"
        let snapshot = try OrcaUICollector(access: fixture, clock: { 1 }).collect()
        #expect(snapshot.statuses.map(\.state) == [.working, .idle])
        #expect(!fixture.childReads.contains(8) && !fixture.childReads.contains(9))
        #expect(!fixture.frameReads.contains(6) && !fixture.reads.contains(9))
        #expect(fixture.reads == [4, 5])
    }

    @Test func malformedDiscoveryGeometryRefusesInsteadOfClaimingAbsence() {
        let fixture = StatusAXFixture()
        fixture.roles[8] = "AXGroup"; fixture.childRows[0] = [8, 1, 6]
        fixture.rectangles[8] = CGRect(x: CGFloat.infinity, y: 0, width: 20, height: 20)
        var stage = ""
        let reader = OrcaUICollector(access: fixture, clock: { 1 }, reportStage: { value, _ in stage = value })
        #expect(throws: OrcaUIReadError.incomplete) { try reader.collect() }
        #expect(stage == "discoveryGeometry" && !fixture.childReads.contains(8) && fixture.reads.isEmpty)
    }

    @Test func ancestorPathStopsAtDepthBoundaryWithoutExtraReadsOrNames() {
        let fixture = StatusAXFixture()
        fixture.childRows = [0: [8]]
        for node in 8...20 {
            fixture.roles[node] = "AXGroup"
            fixture.rectangles[node] = CGRect(x: 0, y: 0, width: 400, height: 30)
            fixture.childRows[node] = [node + 1]
        }
        var path: [OrcaUIStructureStep] = [], stage = ""
        let reader = OrcaUICollector(access: fixture, clock: { 1 }, reportStage: { value, _ in stage = value }, reportPath: { path = $0 })
        #expect(throws: OrcaUIReadError.incomplete) { try reader.collect() }
        #expect(stage == "depthLimit" && path.count == 13)
        #expect(path.map(\.depth) == Array(0...12))
        #expect(path.first?.role == "AXWindow" && path.dropFirst().allSatisfy { $0.role == "AXGroup" })
        #expect(fixture.reads.isEmpty && !fixture.frameReads.contains(20) && !fixture.childReads.contains(20))
    }

    @Test func metadataSanitizesUnexpectedRolesAndNonFiniteFrames() {
        let step = OrcaUIStructureStep(depth: 1, role: "PRIVATE_TRANSCRIPT", rect: CGRect(x: CGFloat.infinity, y: 0, width: 20, height: 20))
        #expect(step.role == "other" && step.frame == nil)
        let valid = OrcaUIStructureStep(depth: 2, role: "AXGroup", rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(valid.frame == [1, 2, 3, 4])
    }

    @Test func nativeDeniedReadHasNoTextOrPromptDiagnostics() {
        let reader = NativeOrcaUIAccess()
        #expect(throws: OrcaUIReadError.permissionRequired) { try reader.read() }
        #expect(reader.diagnostics == OrcaUIReadDiagnostics(stage: "permission"))
    }

    @Test @MainActor func statusPublishesFixedMetadataWithoutGrantingCoverage() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let object = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        let observation = try #require(object["orcaUIObservation"] as? [String: Any])
        let diagnostic = try #require(observation["readDiagnostics"] as? [String: Any])
        #expect(Set(diagnostic.keys) == ["stage", "nodesVisited", "axError", "arrayCount", "ancestorPath"])
        #expect((diagnostic["ancestorPath"] as? [Any])?.isEmpty == true)
        #expect(diagnostic["stage"] as? String == "notRead")
        #expect(diagnostic["nodesVisited"] as? Int == 0)
        #expect(observation["completionCoverageQualified"] as? Bool == false)
        #expect(object["powerActuation"] as? Bool == false)
    }
}
