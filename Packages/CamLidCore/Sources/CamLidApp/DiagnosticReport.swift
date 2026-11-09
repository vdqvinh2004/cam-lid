import CamLidCore
import Foundation

/// Spec 023, User Story 2 (FR-005, FR-006): a plain-text report for a support request. Only the fields written here are
/// included. Blocker sources, explanations and process IDs are left out, since they can carry paths or other detail.
/// Prompts, transcripts, command output, environment values and agent task identifiers are never part of a report.
enum DiagnosticReport {
    static func text(for snapshot: DiagnosticSnapshot, appVersion: String) -> String {
        let blockers = snapshot.blockers.map { "\($0.type) (\($0.effect.rawValue))" }
        let coverage = snapshot.coverage.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.rawValue)" }
        let lines = [
            "CamLid \(appVersion) sleep diagnostics",
            "Observed: \(ISO8601DateFormatter().string(from: snapshot.observedAt))",
            "Configured mode: \(snapshot.configuredMode.rawValue)",
            "Active session: \(snapshot.activeSessionMode?.rawValue ?? "none")",
            "Protection: \(snapshot.protection.rawValue)",
            "Restoration: \(snapshot.restoration)",
            "Prevented by: \(list(snapshot.preventedBy))",
            "Blockers: \(list(blockers))",
            "Coverage: \(list(coverage))",
            "Errors: \(list(snapshot.errors))",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func list(_ items: [String]) -> String {
        items.isEmpty ? "none" : items.joined(separator: ", ")
    }
}
