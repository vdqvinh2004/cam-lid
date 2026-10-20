import Foundation
import CamLidCore

/// Labels from the Orca status component (version-agnostic), never terminal text.
enum OrcaUIState: String, Sendable {
    case working, waiting, idle, unknown
    init(statusLabel: String) {
        switch statusLabel {
        case "Working", "Monitoring background tasks": self = .working
        case "Waiting for input", "Needs attention": self = .waiting
        case "Idle", "Done": self = .idle
        default: self = .unknown
        }
    }
    var taskState: TaskState {
        switch self {
        case .working: .working
        case .waiting: .waiting
        case .idle: .idle
        case .unknown: .unknown
        }
    }
}

struct OrcaUIStatus: Sendable {
    let id: String
    let state: OrcaUIState
}

struct OrcaUISnapshot: Sendable {
    let statuses: [OrcaUIStatus]
    /// Traversal coverage only, not proof that unseen jobs or children ended.
    let complete: Bool
    let observedAt: Double
}

enum OrcaUIReadError: Error, Equatable {
    case permissionRequired, unavailable, incomplete, statusControlsUnavailable, capacity
    var code: String {
        switch self {
        case .permissionRequired: "accessibilityPermissionRequired"
        case .unavailable: "orcaUIUnavailable"
        case .incomplete: "orcaUIIncomplete"
        case .statusControlsUnavailable: "orcaUIStatusControlsUnavailable"
        case .capacity: "orcaUICapacity"
        }
    }
}

/// Fixed roles and finite geometry only; no names, values, descriptions or identities.
struct OrcaUIStructureStep: Sendable, Equatable, Codable {
    let depth: Int
    let role: String
    let frame: [Double]?

    init(depth: Int, role: String, rect: CGRect? = nil) {
        self.depth = depth
        let roles = ["AXWindow", "AXGroup", "AXWebArea", "AXScrollArea", "AXSplitGroup", "AXTabGroup",
                     "AXRadioButton", "AXTab", "AXButton", "AXImage", "AXTextArea", "AXTextField", "AXStaticText"]
        self.role = roles.contains(role) ? role : "other"
        if let rect, [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }) {
            frame = [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)]
        } else { frame = nil }
    }
}

/// Fixed stage/counters only. Never retain labels, text, titles or AX object IDs.
struct OrcaUIReadDiagnostics: Sendable, Equatable {
    var stage = "notRead"
    var nodesVisited = 0
    var axError: Int32?
    var arrayCount: Int?
    var ancestorPath: [OrcaUIStructureStep] = []
}

/// Fakeable read-only OS boundary. No title, value, text, action or screenshot API.
protocol OrcaUIAccess: AnyObject {
    func roots() throws -> [Int]
    func role(_ node: Int) throws -> String
    func children(_ node: Int) throws -> [Int]
    func tabs(_ node: Int) throws -> [Int]
    func frame(_ node: Int) throws -> CGRect
    func statusLabel(_ node: Int) throws -> String?
    func identity(_ tab: Int) throws -> String
}

struct OrcaUICollector {
    let access: any OrcaUIAccess
    let clock: () -> Double
    var nodeLimit = 256
    var timeout = 0.5
    var reportStage: (String, Int) -> Void = { _, _ in }
    var reportPath: ([OrcaUIStructureStep]) -> Void = { _ in }

    func collect() throws -> OrcaUISnapshot {
        let start = clock()
        guard start.isFinite else { throw OrcaUIReadError.incomplete }
        var visited: Set<Int> = []
        var output: [OrcaUIStatus] = []
        var path: [OrcaUIStructureStep] = []
        func recordPath(depth: Int, role: String, rect: CGRect? = nil) {
            path.removeAll { $0.depth >= depth }
            path.append(OrcaUIStructureStep(depth: depth, role: role, rect: rect))
            reportPath(path)
        }
        func admit(_ node: Int, depth: Int) throws {
            let age = clock() - start
            if !age.isFinite || age < 0 { reportStage("invalidClock", visited.count); throw OrcaUIReadError.incomplete }
            if age > timeout { reportStage("readDeadline", visited.count); throw OrcaUIReadError.incomplete }
            if depth > 12 { reportStage("depthLimit", visited.count); throw OrcaUIReadError.incomplete }
            if visited.count >= nodeLimit { reportStage("nodeLimit", visited.count); throw OrcaUIReadError.incomplete }
            if !visited.insert(node).inserted { reportStage("cycle", visited.count); throw OrcaUIReadError.incomplete }
            reportStage("structure", visited.count)
        }
        func statusIcons(_ node: Int, tabFrame: CGRect, depth: Int) throws -> [OrcaUIState] {
            try admit(node, depth: depth)
            let role = try access.role(node)
            recordPath(depth: depth, role: role)
            // Text controls are pruned without reading any of their text attributes.
            if ["AXTextArea", "AXTextField", "AXStaticText", "AXWebArea"].contains(role) { return [] }
            var states: [OrcaUIState] = []
            if ["AXGroup", "AXImage"].contains(role) {
                let rect = try access.frame(node)
                recordPath(depth: depth, role: role, rect: rect)
                if rect.width > 0, rect.height > 0, rect.width <= 16, rect.height <= 16,
                   tabFrame.contains(rect), let label = try access.statusLabel(node) {
                    let state = OrcaUIState(statusLabel: label)
                    // An unrecognized tiny icon is not activity evidence.
                    if state != .unknown { states.append(state) }
                }
            }
            for child in try access.children(node) { states += try statusIcons(child, tabFrame: tabFrame, depth: depth + 1) }
            return states
        }
        func discover(_ node: Int, depth: Int, header: CGRect?) throws {
            try admit(node, depth: depth)
            let role = try access.role(node)
            recordPath(depth: depth, role: role)
            if ["AXTextArea", "AXTextField", "AXStaticText"].contains(role) { return }
            var region = header
            if role == "AXWindow" {
                let rect = try access.frame(node)
                recordPath(depth: depth, role: role, rect: rect)
                reportStage("windowGeometry", visited.count)
                guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
                      rect.width > 0, rect.height > 0 else { throw OrcaUIReadError.incomplete }
                region = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(64, rect.height))
            }
            if role != "AXWindow", let region {
                let rect = try access.frame(node)
                recordPath(depth: depth, role: role, rect: rect)
                reportStage("discoveryGeometry", visited.count)
                guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
                      rect.width >= 0, rect.height >= 0 else { throw OrcaUIReadError.incomplete }
                // Empty structural wrappers may contain header controls; definite outside regions never need a child walk.
                if rect.width > 0, rect.height > 0, !rect.intersects(region) { return }
            }
            if role == "AXTabGroup" {
                guard let region else { throw OrcaUIReadError.incomplete }
                let tabs = try access.tabs(node)
                reportStage("tabCapacity", visited.count)
                guard !tabs.isEmpty, tabs.count <= 20, output.count + tabs.count <= 20 else { throw OrcaUIReadError.capacity }
                for tab in tabs {
                    try admit(tab, depth: depth + 1)
                    let tabRole = try access.role(tab)
                    recordPath(depth: depth + 1, role: tabRole)
                    guard ["AXRadioButton", "AXTab", "AXButton"].contains(tabRole) else { throw OrcaUIReadError.incomplete }
                    let rect = try access.frame(tab)
                    recordPath(depth: depth + 1, role: tabRole, rect: rect)
                    reportStage("tabGeometry", visited.count)
                    guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
                          rect.width > 0, rect.height > 0, rect.height <= 64,
                          region.contains(rect) else { throw OrcaUIReadError.incomplete }
                    var states: [OrcaUIState] = []
                    for child in try access.children(tab) { states += try statusIcons(child, tabFrame: rect, depth: depth + 2) }
                    reportStage("statusControlCount", visited.count)
                    guard states.count == 1 else { throw OrcaUIReadError.statusControlsUnavailable }
                    output.append(OrcaUIStatus(id: try access.identity(tab), state: states[0]))
                }
                return // Never visit the tab group's content panels.
            }
            for child in try access.children(node) { try discover(child, depth: depth + 1, header: region) }
        }
        for root in try access.roots() { try discover(root, depth: 0, header: nil) }
        reportStage("statusControlsUnavailable", visited.count)
        guard !output.isEmpty else { throw OrcaUIReadError.statusControlsUnavailable }
        let end = clock()
        reportStage("finalReadDeadline", visited.count)
        guard end.isFinite, end >= start, end - start <= timeout else { throw OrcaUIReadError.incomplete }
        reportStage("complete", visited.count)
        return OrcaUISnapshot(statuses: output, complete: true, observedAt: start)
    }
}

/// Bounded stable tab observations. Missing or failed reads invalidate idle too.
struct OrcaUITracker {
    private var sequences: [String: Int] = [:]
    private var lastStates: [String: OrcaUIState] = [:]
    mutating func consume(_ snapshot: OrcaUISnapshot, now: Double) throws -> [NormalizedEvent] {
        let age = now - snapshot.observedAt
        guard now.isFinite, age.isFinite, age >= 0, age <= 1,
              snapshot.statuses.count <= 20 else { throw OrcaUIReadError.incomplete }
        var current: [String: OrcaUIState] = [:]
        for row in snapshot.statuses {
            try validateID(row.id)
            guard current.updateValue(row.state, forKey: row.id) == nil else { throw OrcaUIReadError.incomplete }
        }
        let ids = Set(sequences.keys).union(current.keys)
        guard ids.count <= 64 else { throw OrcaUIReadError.capacity }
        var next = sequences
        var states = lastStates
        var events: [NormalizedEvent] = []
        for id in ids.sorted() {
            let state = snapshot.complete ? current[id] ?? .unknown : .unknown
            // Repeated loss is not fresh evidence and must not resurrect retired runs.
            if state == .unknown && states[id] == .unknown { continue }
            let sequence = next[id, default: 0]
            guard sequence < Int.max - 1 else { throw OrcaUIReadError.capacity }
            events.append(try NormalizedEvent(provider: "orca", sessionID: "outside-ui", runID: id,
                state: state.taskState, evidenceKind: .lifecycle, confidence: .inferred,
                sequence: sequence, receivedMonotonic: now))
            next[id] = sequence + 1
            states[id] = state
        }
        sequences = next
        lastStates = states
        return events
    }
}
