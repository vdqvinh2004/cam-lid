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
