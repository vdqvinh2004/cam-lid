import SwiftUI
import CamLidCore

/// Plain-language answer to “Why is my Mac awake?”.
///
/// The main surface deliberately avoids assertion types, PIDs and coverage
/// values. Those stay available under each row and in Technical details.
public struct SleepDiagnosticsView: View {
    @State private var snapshot: DiagnosticSnapshot?
    @State private var isLoading = false
    private let read: @MainActor () async -> DiagnosticSnapshot
    public init(snapshot: DiagnosticSnapshot? = nil,
                read: @escaping @MainActor () async -> DiagnosticSnapshot = { await SleepDiagnosticReader.shared.snapshot() }) {
        _snapshot = State(initialValue: snapshot); self.read = read
    }
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let snapshot {
                ScrollView {
                    DiagnosticContent(snapshot: snapshot, refresh: { await refresh() })
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LoadingState()
            }
        }
        .frame(minWidth: 520, minHeight: 400)
        .task { if snapshot == nil { await refresh() } }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(headerStatus)
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if isLoading, snapshot != nil {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Refreshing sleep information")
            }
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                .disabled(isLoading).help("Refresh the sleep report (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityIdentifier("camlid.sleepDiagnostics.refresh")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    private var headerStatus: String {
        guard let snapshot else { return "Checking…" }
        if isLoading { return "Refreshing…" }
        return "Checked at \(snapshot.observedAt.formatted(date: .omitted, time: .shortened))"
    }
    @MainActor private func refresh() async {
        guard !isLoading else { return }; isLoading = true
        let result = await read()
        if !Task.isCancelled { snapshot = result }
        isLoading = false
    }
}

private struct LoadingState: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.regular)
                .accessibilityHidden(true)
            Text("Checking what's keeping your Mac awake…")
                .font(.callout)
            Text("This usually takes a moment.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityRepresentation {
            Text("Checking what's keeping your Mac awake. This usually takes a moment.")
        }
    }
}

private struct DiagnosticContent: View {
    let snapshot: DiagnosticSnapshot
    let refresh: @MainActor () async -> Void

    var body: some View {
        let causes = SleepDiagnosticsCopy.causes(for: snapshot)
        let appsCoverage = snapshot.coverage["userAssertions"]
        VStack(alignment: .leading, spacing: 16) {
            summary(causes, appsCoverage: appsCoverage)
            if causes.isEmpty {
                emptyMessage(appsCoverage: appsCoverage)
            } else {
                causeList(causes)
            }
            Text("CamLid only reads these details. Other apps, devices, and macOS activity can also affect sleep and may not appear here.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            technicalDetails
        }
    }
    private func summary(_ causes: [FriendlySleepCause], appsCoverage: DiagnosticCoverage?) -> some View {
        Text(SleepDiagnosticsCopy.summary(causes, appsCoverage: appsCoverage))
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("camlid.sleepDiagnostics.summary")
    }
    private func emptyMessage(appsCoverage: DiagnosticCoverage?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: emptySymbol(appsCoverage))
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(emptyMessageText(appsCoverage: appsCoverage))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Check again") { Task { await refresh() } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func emptySymbol(_ appsCoverage: DiagnosticCoverage?) -> String {
        switch appsCoverage ?? .unavailable {
        case .complete: "moon.zzz.fill"
        case .partial: "exclamationmark.circle"
        case .unavailable: "questionmark.circle"
        }
    }
    private func emptyMessageText(appsCoverage: DiagnosticCoverage?) -> String {
        switch appsCoverage ?? .unavailable {
        case .complete:
            return "If the screen is off and your Mac still seems busy, it may be finishing a short background task."
        case .partial:
            return "Some app activity wasn't returned, so another app may still be involved."
        case .unavailable:
            if snapshot.preventedBy.isEmpty {
                return "macOS didn't return the list of apps asking to stay awake."
            }
            return "macOS says \(snapshot.preventedBy.joined(separator: ", ")) may be preventing sleep, but the detailed list couldn't be read."
        }
    }
    private func causeList(_ causes: [FriendlySleepCause]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(causes.enumerated()), id: \.element.id) { index, cause in
                if index > 0 { Divider().padding(.vertical, 2) }
                CauseRow(cause: cause)
            }
        }
        .accessibilityIdentifier("camlid.sleepDiagnostics.requests")
    }
    private var technicalDetails: some View {
        DisclosureGroup("Technical details") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                detailRow("App requests", coverageText(snapshot.coverage["userAssertions"]))
                detailRow("Global setting", coverageText(snapshot.coverage["global"]))
                detailRow("Devices", coverageText(snapshot.coverage["kernel"]))
                detailRow("Preventing sleep", preventingText)
                detailRow("CamLid", snapshot.activeSessionMode.map { $0.rawValue.capitalized }
                    ?? "Stopped")
                if !snapshot.errors.isEmpty {
                    detailRow("Errors", snapshot.errors.joined(separator: ", "))
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
        .font(.caption)
    }
    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var preventingText: String {
        guard snapshot.coverage["preventing"] == .complete else { return "Not reported" }
        return snapshot.preventedBy.isEmpty ? "None reported" : snapshot.preventedBy.joined(separator: ", ")
    }
    private func coverageText(_ coverage: DiagnosticCoverage?) -> String {
        switch coverage {
        case .complete: "Available"
        case .partial: "Partial"
        case .unavailable, .none: "Unavailable"
        }
    }
}

private struct CauseRow: View {
    let cause: FriendlySleepCause
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(cause.details) { detail in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.owner).font(.callout).textSelection(.enabled)
                        Text(technicalLine(detail)).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.leading, 32)
            .padding(.vertical, 6)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: cause.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(cause.title).font(.body.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if cause.activeNow { ActiveNowLabel() }
                    }
                    Text(cause.subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .disclosureGroupStyle(RowDisclosureStyle())
    }
    private func technicalLine(_ detail: FriendlySleepDetail) -> String {
        var parts = [detail.type, detail.source]
        if let pid = detail.pid { parts.append("PID \(pid)") }
        return parts.joined(separator: " · ")
    }
}

private struct ActiveNowLabel: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(.green).frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text("Active now").font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}
