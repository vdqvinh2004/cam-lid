import Foundation
import Testing
import CamLidCore
import CamLidCLI
@testable import CamLidApp

private final class SurveyAX: OrcaUIAccess {
    var rootRows = [0]
    var roles = [0: "AXWindow"]
    var frames = [0: CGRect(x: 0, y: 0, width: 400, height: 300)]
    var rows: [Int: [Int]] = [:]
    var roleReads: [Int] = [], frameReads: [Int] = [], childReads: [Int] = []
    var forbiddenReads = 0
    func roots() throws -> [Int] { rootRows }
    func role(_ node: Int) throws -> String { roleReads.append(node); return roles[node] ?? "AXGroup" }
    func frame(_ node: Int) throws -> CGRect { frameReads.append(node); return frames[node] ?? CGRect(x: 0, y: 0, width: 20, height: 20) }
    func children(_ node: Int) throws -> [Int] { childReads.append(node); return rows[node] ?? [] }
    func tabs(_ node: Int) throws -> [Int] { forbiddenReads += 1; throw OrcaUIReadError.incomplete }
    func statusLabel(_ node: Int) throws -> String? { forbiddenReads += 1; throw OrcaUIReadError.incomplete }
    func identity(_ tab: Int) throws -> String { forbiddenReads += 1; throw OrcaUIReadError.incomplete }
}

@Suite("QA-only bounded structural survey") struct OrcaUIStructureSurveyTests {
    @Test func deeperSurveyDoesNotWidenProductionDepthOrReadStatus() {
        let fixture = SurveyAX()
        for node in 0...24 { fixture.rows[node] = [node + 1] }
        let result = OrcaUIStructureSurvey(access: fixture, clock: { 1 }).collect()
        #expect(result.stage == "depthLimit" && result.nodesVisited == 24 && result.steps.count == 24)
        #expect(result.steps.map(\.depth) == Array(0...23))
        #expect(!fixture.roleReads.contains(24) && !fixture.childReads.contains(24) && fixture.forbiddenReads == 0)
        var stage = ""
        #expect(throws: OrcaUIReadError.incomplete) {
            try OrcaUICollector(access: fixture, clock: { 1 }, reportStage: { value, _ in stage = value }).collect()
        }
        #expect(stage == "depthLimit")
    }

    @Test func outsideHeaderAndTextNeverExposeChildrenOrNames() throws {
        let fixture = SurveyAX()
        fixture.rows = [0: [1, 2], 1: [3], 2: [4]]
        fixture.frames[1] = CGRect(x: 0, y: 100, width: 400, height: 200)
        fixture.roles[2] = "AXTextArea"
        let result = OrcaUIStructureSurvey(access: fixture, clock: { 1 }).collect()
        #expect(result.stage == "traversalFinishedNotQualified" && result.steps.count == 1)
        #expect(fixture.childReads == [0] && !fixture.frameReads.contains(2) && fixture.forbiddenReads == 0)
        let json = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        #expect(!json.contains("status") && !json.contains("identity") && !json.contains("label"))
    }

    @Test(arguments: ["cycle", "nodeLimit", "readDeadline", "invalidGeometry", "arrayLimit", "rootLimit"])
    func refusalsRetainBoundedPartialMetadata(_ kind: String) {
        let fixture = SurveyAX()
        if kind == "cycle" { fixture.rows[0] = [0] }
        if kind == "nodeLimit" { fixture.rows[0] = Array(1...64) }
        if kind == "invalidGeometry" { fixture.frames[0] = .zero }
        if kind == "arrayLimit" { fixture.rows[0] = Array(1...65) }
        if kind == "rootLimit" { fixture.rootRows = Array(0...4) }
        var calls = 0
        let result = OrcaUIStructureSurvey(access: fixture, clock: {
            calls += 1
            return kind == "readDeadline" && calls > 2 ? 2 : 1
        }).collect()
        #expect(result.stage == kind && result.nodesVisited <= 64 && result.steps.count <= 64)
        #expect(fixture.forbiddenReads == 0 && !fixture.roleReads.contains(64))
    }

    @Test func testHostCannotEnableNativeSurveyOrInspectOrca() {
        #expect(!NativeOrcaUIAccess.structureSurveyAuthorized)
        let result = NativeOrcaUIAccess().readStructureSurvey()
        #expect(result.stage == "surveyNotAuthorized" && result.nodesVisited == 0 && result.steps.isEmpty)
    }

    @Test @MainActor func ordinaryStatusHasNoSurveyOrActivityQualification() throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let app = fixture.makeCoordinator()
        let reply = try JSONDecoder().decode(CLIResult.self, from: app.handleControl(.status, payload: Data()))
        let object = try #require(JSONSerialization.jsonObject(with: Data(reply.json.utf8)) as? [String: Any])
        #expect(object["orcaUIStructureSurvey"] is NSNull)
        #expect((object["orcaUIObservation"] as? [String: Any])?["completionCoverageQualified"] as? Bool == false)
        #expect(object["powerActuation"] as? Bool == false)
    }
}
