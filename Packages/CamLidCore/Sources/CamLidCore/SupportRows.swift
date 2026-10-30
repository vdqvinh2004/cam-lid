import Foundation

/// A Mac model and OS build on which closed-lid actuation has passed an owner-approved attended trial.
public struct SupportRow: Equatable, Sendable {
    public let id: String
    public let model: String
    public let osBuild: String

    public init(id: String, model: String, osBuild: String) {
        self.id = id; self.model = model; self.osBuild = osBuild
    }
}

public enum QualifiedSupportRows {
    /// Empty on purpose: a row is added only with the owner's approval after the attended trial in
    /// specs/014-persistent-helper/g2-trial.md passes. While it is empty no build asks the helper to hold power.
    public static let rows: [SupportRow] = []

    public static func matching(model: String?, osBuild: String?, in table: [SupportRow] = rows) -> String? {
        guard let model, let osBuild else { return nil }
        return table.first { $0.model == model && $0.osBuild == osBuild }?.id
    }

    public static func currentSystem() -> (model: String?, osBuild: String?) {
        (sysctlString("hw.model"), sysctlString("kern.osversion"))
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, (2...128).contains(size) else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// The user's explicit acceptance that closed lid may run on a Mac without a qualified row. Valid only for the exact
/// model and macOS build it was given on; a macOS update or another Mac asks again.
public struct UntestedAcknowledgement: Codable, Equatable, Sendable {
    public let model: String
    public let osBuild: String
    public let acceptedAt: Date

    public init(model: String, osBuild: String, acceptedAt: Date) {
        self.model = model; self.osBuild = osBuild; self.acceptedAt = acceptedAt
    }
}

/// Whether closed lid may ask the helper to hold power on this Mac (spec 014 FR-016).
public enum ClosedLidPermit: Equatable, Sendable {
    case qualified(rowID: String)
    case untestedAcknowledged
    case notPermitted

    public var allowsActuation: Bool { self != .notPermitted }

    public var statusCode: String {
        switch self {
        case .qualified(let id): "qualified:\(id)"
        case .untestedAcknowledged: "untestedAcknowledged"
        case .notPermitted: "notPermitted"
        }
    }

    public static func decide(model: String?, osBuild: String?, rows: [SupportRow] = QualifiedSupportRows.rows,
                              acknowledgement: UntestedAcknowledgement?) -> ClosedLidPermit {
        if let id = QualifiedSupportRows.matching(model: model, osBuild: osBuild, in: rows) { return .qualified(rowID: id) }
        guard let model, let osBuild, let acknowledgement,
              acknowledgement.model == model, acknowledgement.osBuild == osBuild else { return .notPermitted }
        return .untestedAcknowledged
    }
}

/// Apps whose helpers are known to reset `pmset disablesleep` set by another process (found in G2: LidRun resets it
/// 40–60 s later). Detection is read-only; CamLid never stops or changes them.
public enum ConflictingSleepHelpers {
    public static let known: [(label: String, name: String)] = [("com.lidrun.app.helper", "LidRun")]

    public static func detect(isLoaded: (String) -> Bool) -> [String] {
        known.filter { isLoaded($0.label) }.map(\.name)
    }
}
