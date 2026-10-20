import AppKit
import ApplicationServices
import Darwin
import CamLidCore

/// One serialized caller owns this AX pool. No actions, text values or screenshots.
final class NativeOrcaUIAccess: OrcaUIAccess, @unchecked Sendable {
    private var nodes: [AXUIElement] = []
    private var retainedTabs: [(element: AXUIElement, id: String)] = []
    private var process: ProcessIdentity?
    private(set) var diagnostics = OrcaUIReadDiagnostics()

    private func note(_ stage: String, error: Int32? = nil, count: Int? = nil) {
        diagnostics.stage = stage; diagnostics.axError = error; diagnostics.arrayCount = count
    }

    func read() throws -> OrcaUISnapshot {
        diagnostics = OrcaUIReadDiagnostics(stage: "permission")
        // Test executables never inspect real agent UI, even if their host is trusted.
        guard Bundle.main.bundleURL.pathExtension == "app", AXIsProcessTrusted() else {
            throw OrcaUIReadError.permissionRequired
        }
        nodes.removeAll(keepingCapacity: true)
        return try OrcaUICollector(access: self, clock: { ContinuousTime.now }, reportStage: { stage, count in
            self.note(stage); self.diagnostics.nodesVisited = count
        }, reportPath: { self.diagnostics.ancestorPath = $0 }).collect()
    }

    static var structureSurveyAuthorized: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.bundleIdentifier == "com.camlid.PermissionsQA"
            && Bundle.main.object(forInfoDictionaryKey: "CamLidQAStateDirectory") is String
            && Bundle.main.object(forInfoDictionaryKey: "CamLidQAOrcaStructureSurvey") as? Bool == true
            && AXIsProcessTrusted()
    }

    func readStructureSurvey() -> OrcaUIStructureSurveyResult {
        guard Self.structureSurveyAuthorized else {
            return OrcaUIStructureSurveyResult(stage: "surveyNotAuthorized", nodesVisited: 0, steps: [])
        }
        diagnostics = OrcaUIReadDiagnostics()
        nodes.removeAll(keepingCapacity: true)
        var result = OrcaUIStructureSurvey(access: self, clock: { ContinuousTime.now }).collect()
        result.axError = diagnostics.axError
        result.arrayCount = diagnostics.arrayCount
        return result
    }

    func roots() throws -> [Int] {
        note("applicationIdentity")
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.stablyai.orca")
        guard apps.count == 1, let app = apps.first else { throw OrcaUIReadError.unavailable }
        // No version pin: capability is proven by the AX reads below. A reshaped
        // Orca UI fails there as incomplete, never as invented data.
        note("processIdentity")
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let read = withUnsafeMutablePointer(to: &info) { proc_pidinfo(app.processIdentifier, PROC_PIDTBSDINFO, 0, $0, Int32(size)) }
        guard read == size, info.pbi_uid == getuid(), info.pbi_ruid == getuid() else { throw OrcaUIReadError.unavailable }
        let identity = try ProcessIdentity(pid: app.processIdentifier,
            startTime: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
        if identity != process { retainedTabs.removeAll(); process = identity }
        let application = try intern(AXUIElementCreateApplication(app.processIdentifier))
        let windows = try array(application, attribute: kAXWindowsAttribute as CFString, limit: 4)
        guard !windows.isEmpty else { throw OrcaUIReadError.unavailable }
        return windows
    }

    func role(_ node: Int) throws -> String {
        guard let value = try string(node, attribute: kAXRoleAttribute as CFString, maximum: 40) else { throw OrcaUIReadError.incomplete }
        return value
    }
    func children(_ node: Int) throws -> [Int] { try array(node, attribute: kAXChildrenAttribute as CFString, limit: 64, optional: true) }
    func tabs(_ node: Int) throws -> [Int] { try array(node, attribute: kAXTabsAttribute as CFString, limit: 20) }

    func frame(_ node: Int) throws -> CGRect {
        let position = try attribute(node, name: kAXPositionAttribute as CFString)
        let size = try attribute(node, name: kAXSizeAttribute as CFString)
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw OrcaUIReadError.incomplete
        }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { throw OrcaUIReadError.incomplete }
        return CGRect(origin: point, size: dimensions)
    }

    func statusLabel(_ node: Int) throws -> String? {
        // Called only for a tiny Group/Image entirely inside a verified tab header.
        try string(node, attribute: kAXDescriptionAttribute as CFString, maximum: 32)
    }

    func identity(_ tab: Int) throws -> String {
        let element = try handle(tab)
        if let old = retainedTabs.first(where: { CFEqual($0.element, element) }) { return old.id }
        guard retainedTabs.count < 64 else { throw OrcaUIReadError.capacity }
        let id = "ui-" + UUID().uuidString.lowercased()
        retainedTabs.append((element, id))
        return id
    }

    private func handle(_ node: Int) throws -> AXUIElement {
        guard nodes.indices.contains(node) else { throw OrcaUIReadError.incomplete }
        return nodes[node]
    }
    private func intern(_ element: AXUIElement) throws -> Int {
        if let index = nodes.firstIndex(where: { CFEqual($0, element) }) { return index }
        note("elementPool")
        guard nodes.count < 512 else { throw OrcaUIReadError.incomplete }
        let result = AXUIElementSetMessagingTimeout(element, 0.05)
        note("elementTimeout", error: result.rawValue)
        guard result == .success else { throw OrcaUIReadError.incomplete }
        nodes.append(element)
        return nodes.count - 1
    }
    private func attribute(_ node: Int, name: CFString) throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(try handle(node), name, &value)
        note("attribute." + (name as String), error: result.rawValue)
        guard result == .success, let value else {
            throw OrcaUIReadError.incomplete
        }
        return value
    }
    private func string(_ node: Int, attribute: CFString, maximum: Int) throws -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(try handle(node), attribute, &value)
        note("attribute." + (attribute as String), error: result.rawValue)
        if result == .attributeUnsupported || result == .noValue { return nil }
        guard result == .success, let value, CFGetTypeID(value) == CFStringGetTypeID() else { throw OrcaUIReadError.incomplete }
        let text = unsafeBitCast(value, to: CFString.self)
        guard CFStringGetLength(text) <= maximum else { return nil }
        return text as String
    }
    private func array(_ node: Int, attribute: CFString, limit: Int, optional: Bool = false) throws -> [Int] {
        let element = try handle(node)
        var count: CFIndex = 0
        let result = AXUIElementGetAttributeValueCount(element, attribute, &count)
        note("count." + (attribute as String), error: result.rawValue, count: count)
        if optional && (result == .attributeUnsupported || result == .noValue) { return [] }
        guard result == .success, count >= 0, count <= limit else { throw OrcaUIReadError.incomplete }
        if count == 0 { return [] }
        var values: CFArray?
        let copied = AXUIElementCopyAttributeValues(element, attribute, 0, count, &values)
        note("array." + (attribute as String), error: copied.rawValue, count: count)
        guard copied == .success, let values, CFArrayGetCount(values) == count else { throw OrcaUIReadError.incomplete }
        return try (0..<count).map { index in
            let value = unsafeBitCast(CFArrayGetValueAtIndex(values, index), to: CFTypeRef.self)
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw OrcaUIReadError.incomplete }
            return try intern(unsafeBitCast(value, to: AXUIElement.self))
        }
    }
}
