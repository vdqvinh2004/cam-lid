import Foundation

/// Spec 026 FR-004: the signer of a bundle, read from its designated requirement.
public enum CodeSignature {
    /// SHA-1 of the leaf certificate named in a designated requirement, `… certificate leaf = H"<40 lowercase hex>"`.
    /// Nil for an ad-hoc signature, which names no certificate.
    public static func leaf(inDesignatedRequirement text: String) -> String? {
        guard let range = text.range(of: "certificate leaf = H\"") else { return nil }
        let rest = text[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let hash = String(rest[..<end])
        return hash.count == 40 && hash.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) ? hash : nil
    }
}
