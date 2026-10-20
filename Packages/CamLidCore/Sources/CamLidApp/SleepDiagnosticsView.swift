import SwiftUI
import CamLidCore

public struct SleepDiagnosticsView: View {
    @State private var snapshot: DiagnosticSnapshot?
    @State private var isLoading = false
    private let read: @MainActor () async -> DiagnosticSnapshot
    public init(snapshot: DiagnosticSnapshot? = nil,
                read: @escaping @MainActor () async -> DiagnosticSnapshot = { await SleepDiagnosticReader.shared.snapshot() }) {
        _snapshot = State(initialValue: snapshot); self.read = read
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Why is my Mac awake?").font(.headline)
                    if let snapshot {
                        Text("Checked \(snapshot.observedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small).accessibilityLabel("Reading sleep requests") }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .disabled(isLoading).help("Read current macOS sleep requests")
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityIdentifier("camlid.sleepDiagnostics.refresh")
            }
            if let snapshot { DiagnosticContent(snapshot: snapshot) }
            else { ContentUnavailableView("Reading sleep requests…", systemImage: "moon.zzz") }
            Text("Read-only snapshot. Other apps, devices and macOS can still postpone sleep. A request is not proof of actual protection or sleep.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(minWidth: 500, minHeight: 300)
        .task { if snapshot == nil { await refresh() } }
    }
    @MainActor private func refresh() async {
        guard !isLoading else { return }; isLoading = true
        let result = await read()
        if !Task.isCancelled { snapshot = result }
        isLoading = false
    }
}
private struct DiagnosticContent: View {
    let snapshot: DiagnosticSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.activeSessionMode.map { "CamLid: \($0.rawValue.capitalized) · Preview only" } ?? "CamLid: stopped · Preview only")
                .font(.callout).accessibilityIdentifier("camlid.sleepDiagnostics.summary")
            if !snapshot.errors.isEmpty {
                Label("Some information is unavailable or incomplete. Refresh to check again.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if snapshot.blockers.isEmpty {
                ContentUnavailableView(snapshot.hasCoverage ? "No requests found in the available data" : "Sleep requests unavailable",
                    systemImage: "moon.zzz", description: Text("Hardware, recent input and macOS policies can still postpone sleep."))
            } else {
                List(snapshot.blockers) { blocker in DiagnosticRow(blocker: blocker) }
                    .listStyle(.inset).accessibilityIdentifier("camlid.sleepDiagnostics.requests")
            }
            Text("App requests: \(snapshot.coverage["userAssertions"]?.rawValue ?? "unavailable") · Global setting: \(snapshot.coverage["global"]?.rawValue ?? "unavailable") · Devices: \(snapshot.coverage["kernel"]?.rawValue ?? "unavailable")")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
private struct DiagnosticRow: View {
    let blocker: DiagnosticBlocker
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                Text(blocker.explanation).textSelection(.enabled)
                Text(blocker.type + " · " + blocker.source).font(.caption).foregroundStyle(.secondary)
                if let pid = blocker.pid { Text("PID \(pid)").font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 4)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(blocker.owner ?? (blocker.effect == .global ? "macOS power settings" : blocker.effect == .kernel ? "Devices and kernel" : "Owner unknown"))
                Text(blocker.effect.title).font(.caption).foregroundStyle(.secondary)
            }
        }.disclosureGroupStyle(RowDisclosureStyle()).help("Show the sleep effect and observation source")
    }
}
