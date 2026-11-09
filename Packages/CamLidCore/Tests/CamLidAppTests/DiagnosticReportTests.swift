import CamLidCore
import Foundation
import Testing
@testable import CamLidApp

/// Spec 023, User Story 2 (FR-006, SC-003): the copied report carries its allowed fields and no excluded detail.
@Suite("Copyable diagnostics")
struct DiagnosticReportTests {
    private func snapshot(source: String, explanation: String, pid: Int?) -> DiagnosticSnapshot {
        var snapshot = DiagnosticSnapshot(observedAt: Date(timeIntervalSince1970: 1_800_000_000),
            coverage: ["preventing": .complete], configuredMode: .auto, activeSessionMode: .auto,
            protection: .requested, preventedBy: ["Brave Browser"])
        snapshot.blockers = [DiagnosticBlocker(id: "blocker-1", type: "PreventUserIdleDisplaySleep", effect: .displayIdle,
            source: source, owner: "Brave Browser", pid: pid, explanation: explanation)]
        return snapshot
    }

    @Test func theReportCarriesTheAllowedFields() {
        let text = DiagnosticReport.text(for: snapshot(source: "source", explanation: "explained", pid: 1), appVersion: "0.2.0")
        #expect(text.hasPrefix("CamLid 0.2.0 sleep diagnostics\n"))
        #expect(text.contains("Configured mode: auto\n"))
        #expect(text.contains("Active session: auto\n"))
        #expect(text.contains("Protection: requested\n"))
        #expect(text.contains("Prevented by: Brave Browser\n"))
        #expect(text.contains("Blockers: PreventUserIdleDisplaySleep (displayIdle)\n"))
        #expect(text.contains("Coverage: preventing=complete\n"))
        #expect(text.contains("Errors: none\n"))
    }

    @Test func excludedDetailNeverAppears() {
        let detail = "/Users/someone/project/.env SECRET_TOKEN=abc prompt: summarise my notes"
        let text = DiagnosticReport.text(for: snapshot(source: detail, explanation: detail, pid: 4242), appVersion: "0.2.0")
        for forbidden in ["/Users", "someone", ".env", "SECRET_TOKEN", "prompt", "summarise", "4242", "explained"] {
            #expect(!text.contains(forbidden), "the report must not contain \(forbidden)")
        }
    }

    @Test func anEmptySnapshotReadsAsNone() {
        let text = DiagnosticReport.text(for: DiagnosticSnapshot(), appVersion: "0.2.0")
        #expect(text.contains("Prevented by: none\n"))
        #expect(text.contains("Blockers: none\n"))
        #expect(text.contains("Active session: none\n"))
    }
}
