import Foundation

/// Operator-approved QA diagnostic only; never a task observation or coverage proof.
struct OrcaUIStructureSurveyResult: Sendable, Codable {
    let stage: String
    let nodesVisited: Int
    let steps: [OrcaUIStructureStep]
    var axError: Int32?
    var arrayCount: Int?
}

struct OrcaUIStructureSurvey {
    let access: any OrcaUIAccess
    let clock: () -> Double

    func collect() -> OrcaUIStructureSurveyResult {
        let start = clock()
        var visited: Set<Int> = [], steps: [OrcaUIStructureStep] = []
        var stage = "roots"
        func refuse(_ reason: String) throws {
            stage = reason
            throw OrcaUIReadError.incomplete
        }
        func checkClock() throws {
            let age = clock() - start
            if !start.isFinite || !age.isFinite || age < 0 { try refuse("invalidClock") }
            if age > 0.5 { try refuse("readDeadline") }
        }
        func walk(_ node: Int, depth: Int, header: CGRect?) throws {
            try checkClock()
            if depth >= 24 { try refuse("depthLimit") }
            if visited.count >= 64 { try refuse("nodeLimit") }
            if !visited.insert(node).inserted { try refuse("cycle") }
            stage = "role"
            let role = try access.role(node)
            try checkClock()
            if ["AXTextArea", "AXTextField", "AXStaticText"].contains(role) { return }
            stage = "geometry"
            let rect = try access.frame(node)
            try checkClock()
            guard [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }),
                  rect.width > 0, rect.height > 0 else { try refuse("invalidGeometry"); return }
            let region: CGRect
            if role == "AXWindow", header == nil {
                region = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(64, rect.height))
            } else if let header { region = header }
            else { try refuse("windowRequired"); return }
            if !rect.intersects(region) { return }
            steps.append(OrcaUIStructureStep(depth: depth, role: role, rect: rect))
            stage = "children"
            // No tabs, status descriptions, names, values, identities or actions in this diagnostic.
            let children = try access.children(node)
            try checkClock()
            if children.count > 64 { try refuse("arrayLimit") }
            for child in children { try walk(child, depth: depth + 1, header: region) }
        }
        do {
            try checkClock()
            let roots = try access.roots()
            if roots.isEmpty || roots.count > 4 { try refuse("rootLimit") }
            for root in roots { try walk(root, depth: 0, header: nil) }
            try checkClock()
            stage = "traversalFinishedNotQualified"
        } catch { /* Retain partial metadata and the precise refusal, never manufacture completion. */ }
        return OrcaUIStructureSurveyResult(stage: stage, nodesVisited: visited.count, steps: steps)
    }
}
