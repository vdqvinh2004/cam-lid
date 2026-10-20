import Foundation

public enum ProtectionBuildKind: String, Codable, Sendable, Equatable {
    case preview
    case development
    case release
}

public enum ProtectionOwnershipEvidence: String, Codable, Sendable, Equatable {
    /// No conclusion is safe. Matching a global assertion value does not prove ownership.
    case unknown
    case noExternalOverride
    case verifiedCamLidOwnership
    case conflict
}

public enum ProtectionEffectiveState: String, Codable, Sendable, Equatable {
    case preview = "Preview"
    case needsSetup = "Needs setup"
    case untestedConfiguration = "Untested configuration"
    case conflict = "Conflict"
    case recoveryRequired = "Recovery required"
    case ready = "Ready"
    case protected = "Protected"
}

/// Immutable evidence supplied by the service/backend boundary. This type only
/// projects status; it cannot create a helper, assertion, lease, or power action.
public struct ProtectionReadinessFacts: Codable, Sendable, Equatable {
    public var buildKind: ProtectionBuildKind
    public var supportRowID: String?
    /// True only when the row matches this product, model, OS build, and backend.
    public var supportRowQualified: Bool
    public var helperTrusted: Bool
    public var helperAvailable: Bool
    public var recoveryRequired: Bool
    public var recoveryJournalReady: Bool
    public var ownershipEvidence: ProtectionOwnershipEvidence
    /// A matching global value still needs journal-backed ownership evidence.
    public var matchingGlobalOverrideObserved: Bool
    public var backendVerified: Bool
    public var leaseVerified: Bool
    public var safetyQualifying: Bool
    public var requestedClosedLidIntent: Bool

    public init(
        buildKind: ProtectionBuildKind,
        supportRowID: String?,
        supportRowQualified: Bool,
        helperTrusted: Bool,
        helperAvailable: Bool,
        recoveryRequired: Bool,
        recoveryJournalReady: Bool,
        ownershipEvidence: ProtectionOwnershipEvidence,
        matchingGlobalOverrideObserved: Bool,
        backendVerified: Bool,
        leaseVerified: Bool,
        safetyQualifying: Bool,
        requestedClosedLidIntent: Bool
    ) {
        self.buildKind = buildKind
        self.supportRowID = supportRowID
        self.supportRowQualified = supportRowQualified
        self.helperTrusted = helperTrusted
        self.helperAvailable = helperAvailable
        self.recoveryRequired = recoveryRequired
        self.recoveryJournalReady = recoveryJournalReady
        self.ownershipEvidence = ownershipEvidence
        self.matchingGlobalOverrideObserved = matchingGlobalOverrideObserved
        self.backendVerified = backendVerified
        self.leaseVerified = leaseVerified
        self.safetyQualifying = safetyQualifying
        self.requestedClosedLidIntent = requestedClosedLidIntent
    }
}

/// Pure presentation projection. Protected is reachable only when every proof
/// gate is satisfied by current facts from a qualified non-preview backend.
public struct ProtectionReadiness: Codable, Sendable, Equatable {
    public let state: ProtectionEffectiveState
    /// Only a qualified current support row is public; otherwise JSON contains null.
    public let supportRowID: String?
    public let backendVerified: Bool
    public let leaseVerified: Bool
    public let recoveryRequired: Bool
    public let requestedClosedLidIntent: Bool
    public let blockerCodes: [String]

    public var blockerDetails: [String] { blockerCodes.map(Self.detail(for:)) }
    public var blockerDetail: String? { blockerDetails.first }

    public init(facts: ProtectionReadinessFacts) {
        let qualifiedRowID = Self.qualifiedRowID(facts)
        let ownershipBlocked = Self.ownershipBlocked(facts)
        let configurationUntested = facts.buildKind == .development || qualifiedRowID == nil
        let needsSetup = !facts.helperAvailable || !facts.recoveryJournalReady || !facts.backendVerified

        if facts.recoveryRequired {
            state = .recoveryRequired
        } else if ownershipBlocked {
            state = .conflict
        } else if !facts.helperTrusted {
            state = .needsSetup
        } else if configurationUntested {
            state = .untestedConfiguration
        } else if needsSetup {
            state = .needsSetup
        } else if facts.buildKind == .preview {
            state = .preview
        } else if facts.leaseVerified && facts.safetyQualifying && facts.requestedClosedLidIntent {
            state = .protected
        } else {
            state = .ready
        }

        supportRowID = qualifiedRowID
        backendVerified = facts.backendVerified
        leaseVerified = facts.leaseVerified
        recoveryRequired = facts.recoveryRequired
        requestedClosedLidIntent = facts.requestedClosedLidIntent
        blockerCodes = Self.blockers(for: facts, qualifiedRowID: qualifiedRowID)
    }

    private static func qualifiedRowID(_ facts: ProtectionReadinessFacts) -> String? {
        guard facts.supportRowQualified,
              let identifier = facts.supportRowID,
              !identifier.isEmpty,
              identifier.count <= 128,
              identifier == identifier.trimmingCharacters(in: .whitespacesAndNewlines),
              identifier.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        return identifier
    }

    private static func ownershipBlocked(_ facts: ProtectionReadinessFacts) -> Bool {
        switch facts.ownershipEvidence {
        case .conflict, .unknown:
            return true
        case .noExternalOverride:
            return facts.matchingGlobalOverrideObserved
        case .verifiedCamLidOwnership:
            return false
        }
    }

    private static func blockers(
        for facts: ProtectionReadinessFacts,
        qualifiedRowID: String?
    ) -> [String] {
        var result: [String] = []
        if facts.recoveryRequired { result.append("recoveryRequired") }
        switch facts.ownershipEvidence {
        case .conflict:
            result.append("externalOwnershipConflict")
        case .unknown:
            result.append("externalOwnershipUnknown")
        case .noExternalOverride where facts.matchingGlobalOverrideObserved:
            result.append("externalOwnershipUnknown")
        case .noExternalOverride, .verifiedCamLidOwnership:
            break
        }
        if !facts.helperTrusted { result.append("helperUntrusted") }
        if facts.buildKind == .development { result.append("buildUnqualified") }
        if qualifiedRowID == nil { result.append("supportRowUnqualified") }
        if !facts.helperAvailable { result.append("helperUnavailable") }
        if !facts.recoveryJournalReady { result.append("recoveryJournalUnready") }
        if !facts.backendVerified { result.append("backendUnverified") }
        if facts.buildKind == .preview { result.append("previewPowerDisabled") }
        if facts.requestedClosedLidIntent && !facts.safetyQualifying {
            result.append("safetyEvidenceNotQualifying")
        }
        if facts.requestedClosedLidIntent && !facts.leaseVerified {
            result.append("leaseNotVerified")
        }
        return result
    }

    private static func detail(for code: String) -> String {
        switch code {
        case "recoveryRequired": return "Restore the previous system state before protection can continue."
        case "externalOwnershipConflict": return "Another power override is present; CamLid cannot safely claim or replace it."
        case "externalOwnershipUnknown": return "Override ownership is unknown; a matching value does not prove CamLid owns it."
        case "helperUntrusted": return "The privileged helper has not passed its trust checks."
        case "buildUnqualified": return "This development build has no qualified hardware support row."
        case "supportRowUnqualified": return "This Mac and system build have no qualified support row."
        case "helperUnavailable": return "The power helper is not installed or available."
        case "recoveryJournalUnready": return "The recovery journal is not ready to restore system state."
        case "backendUnverified": return "The closed-lid backend has not passed its verification checks."
        case "previewPowerDisabled": return "Preview mode does not control system power."
        case "safetyEvidenceNotQualifying": return "Current safety and agent evidence does not permit closed-lid protection."
        case "leaseNotVerified": return "The system is ready, but no protection lease is verified."
        default: return "Protection is blocked until its safety requirements are met."
        }
    }

    private enum CodingKeys: String, CodingKey {
        case state, supportRowID, backendVerified, leaseVerified
        case recoveryRequired, requestedClosedLidIntent, blockerCodes
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(supportRowID, forKey: .supportRowID)
        try container.encode(backendVerified, forKey: .backendVerified)
        try container.encode(leaseVerified, forKey: .leaseVerified)
        try container.encode(recoveryRequired, forKey: .recoveryRequired)
        try container.encode(requestedClosedLidIntent, forKey: .requestedClosedLidIntent)
        try container.encode(blockerCodes, forKey: .blockerCodes)
    }
}
