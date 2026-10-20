import Foundation

public struct ProviderDiagnostic: Codable, Sendable {
    public let provider: String
    public let outcome: ProviderToolOutcome
    public init(provider: String, outcome: ProviderToolOutcome) { self.provider = provider; self.outcome = outcome }
    public func validate() throws {
        guard provider == "codex", outcome.failed,
              ["failed", "completed", "unknown"].contains(outcome.status) else {
            throw IPCError.invalidInput("invalidToolDiagnostic")
        }
    }
}
