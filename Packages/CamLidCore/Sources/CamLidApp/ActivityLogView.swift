import SwiftUI
import CamLidCore

/// Filter for the activity timeline. Injected alongside the snapshot rows;
/// matching is local and case-insensitive.
public struct ActivityFilter: Sendable, Equatable {
    public var query: String
    public var sessionPseudonym: String?
    public var reasonCode: String?
    public var category: ActivityCategory?

    public init(
        query: String = "",
        sessionPseudonym: String? = nil,
        reasonCode: String? = nil,
        category: ActivityCategory? = nil
    ) {
        self.query = query
        self.sessionPseudonym = sessionPseudonym
        self.reasonCode = reasonCode
        self.category = category
    }

    public var isActive: Bool {
        !query.isEmpty || sessionPseudonym != nil || reasonCode != nil || category != nil
    }

    public func matches(_ record: StoredTransition) -> Bool {
        if let sessionPseudonym, record.sessionID != sessionPseudonym { return false }
        if let reasonCode, !record.reasonCodes.contains(reasonCode) { return false }
        if let category, record.category != category { return false }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        let words = [record.sessionID ?? "", record.previousState?.rawValue ?? "",
            record.newState.rawValue, record.category.rawValue, record.providerKind ?? "",
            ActivityPresentation.title(record)] + record.reasonCodes + record.reasonCodes.map(ActivityPresentation.readableReason)
        return words.joined(separator: " ").lowercased().contains(needle)
    }

}

private let activityDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

/// Retains the last readable snapshot while a newer request is pending.
/// Request identity prevents late replies from replacing a newer read.
struct ActivitySnapshot: Sendable {
    private(set) var records: [StoredTransition] = []
    private(set) var error: String?
    private(set) var outcome: String?
    private(set) var isLoading = true
    private var requestID: UUID?

    mutating func beginRead(_ id: UUID) {
        requestID = id; isLoading = true; error = nil
    }
    @discardableResult mutating func completeRead(_ id: UUID, records: [StoredTransition],
                                                  error: String?, outcome: String?) -> Bool {
        guard requestID == id else { return false }
        requestID = nil; isLoading = false
        if error == nil { self.records = records }
        self.error = error; self.outcome = outcome
        return true
    }
}

/// Searchable session/reason timeline (specs/005-native-ux T008, FR-016).
/// Binds to ActivityStore snapshots injected by the host (`transitions` +
/// `filter`); the view owns no storage. Export shows a pseudonymized preview
/// note; delete requires explicit confirmation and reports the tombstone
/// receipt count via `onDeleteResult`.
public struct ActivityLogView: View {
    static func preferredHeight(recordCount: Int, hasError: Bool) -> CGFloat {
        min(480, max(220, 112 + CGFloat(min(6, max(0, recordCount))) * 52 + (hasError ? 64 : 0)))
    }
    public let transitions: [StoredTransition]
    public let storageError: String?
    public let outcome: String?
    public let isLoading: Bool
    public let onRefresh: () -> Void
    public let onExportRedacted: () -> Void
    public let onDeleteSession: (String) -> Void
    public let onDeleteAll: () -> Void
    public let onDeleteResult: (DeletionReceipt) -> Void

    @State private var filter = ActivityFilter()
    @State private var pendingSessionDelete: String?
    @State private var confirmingDeleteAll = false
    @State private var lastReceiptText: String?

    public init(
        transitions: [StoredTransition],
        storageError: String? = nil, outcome: String? = nil, isLoading: Bool = false,
        onRefresh: @escaping () -> Void = {},
        onExportRedacted: @escaping () -> Void,
        onDeleteSession: @escaping (String) -> Void,
        onDeleteAll: @escaping () -> Void,
        onDeleteResult: @escaping (DeletionReceipt) -> Void = { _ in }
    ) {
        self.transitions = transitions
        self.storageError = storageError; self.outcome = outcome
        self.isLoading = isLoading; self.onRefresh = onRefresh
        self.onExportRedacted = onExportRedacted
        self.onDeleteSession = onDeleteSession
        self.onDeleteAll = onDeleteAll
        self.onDeleteResult = onDeleteResult
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            filterBar
            if !transitions.isEmpty {
                Text(countText).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("camlid.activity.count")
            }
            if isLoading {
                ProgressView(transitions.isEmpty ? "Loading activity…" : "Refreshing activity…")
                    .controlSize(.small).accessibilityIdentifier("camlid.activity.loading")
            }
            if storageError != nil {
                HStack(alignment: .top) {
                    Label(transitions.isEmpty ? "History could not be read." : "History could not be refreshed. Showing previously loaded activity.",
                          systemImage: "exclamationmark.triangle")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Retry", action: onRefresh)
                }.accessibilityIdentifier("camlid.activity.error")
                Text("Check storage permissions and available space.").font(.caption).foregroundStyle(.secondary)
            }
            if transitions.isEmpty {
                if !isLoading && storageError == nil {
                    Text("No activity yet. Session and settings changes will appear here.")
                        .font(.body).foregroundStyle(.secondary)
                }
            } else if filtered.isEmpty {
                Text("No transitions match the current filter.")
                    .font(.body).foregroundStyle(.secondary)
            } else {
                List(filtered, id: \.id) { record in
                    row(record)
                }
                .frame(minHeight: 120)
                .accessibilityIdentifier(CamLidAccessibility.IDs.activityList)
            }
            if let receipt = outcome ?? lastReceiptText {
                Text(receipt).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 200, maxHeight: .infinity, alignment: .topLeading)
        .alert(
            "Delete this session's history?",
            isPresented: Binding(
                get: { pendingSessionDelete != nil },
                set: { if !$0 { pendingSessionDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingSessionDelete = nil }
            Button("Delete", role: .destructive) {
                if let session = pendingSessionDelete {
                    onDeleteSession(session)
                    pendingSessionDelete = nil
                }
            }
            .disabled(isLoading || storageError != nil)
        } message: {
            Text("This permanently removes the session’s activity. You cannot undo this action.")
        }
        .alert("Delete all history?", isPresented: $confirmingDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete everything", role: .destructive) { onDeleteAll() }
                .disabled(isLoading || storageError != nil)
        } message: {
            Text("This permanently removes all local activity. Export a redacted copy first if you want to keep it.")
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search activity", text: $filter.query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search activity")
                    .accessibilityIdentifier(CamLidAccessibility.IDs.activitySearch)
                if filter.isActive { Button("Clear") { filter = ActivityFilter() } }
            }
            HStack {
                Picker("Type", selection: $filter.category) {
                    Text("All activity").tag(nil as ActivityCategory?)
                    ForEach(ActivityCategory.allCases, id: \.self) { category in
                        Text(ActivityPresentation.categoryName(category)).tag(category as ActivityCategory?)
                      }
                  }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("camlid.activity.category")
                    .help("Filter activity by event type")
                Picker("Reason", selection: $filter.reasonCode) {
                    Text("All reasons").tag(nil as String?)
                    ForEach(allReasonCodes, id: \.self) { code in
                        Text(ActivityPresentation.readableReason(code)).tag(code as String?)
                      }
                  }
                .frame(maxWidth: .infinity, alignment: .leading).help("Filter activity by reason")
                Button("Export…", action: onExportRedacted)
                    .disabled(isLoading || storageError != nil || transitions.isEmpty)
                    .help("Export a copy with pseudonymized identifiers and no prompts, code or transcripts")
                    .accessibilityIdentifier(CamLidAccessibility.IDs.activityExport)
                Menu {
                    Button("Refresh", action: onRefresh).disabled(isLoading)
                    Button("Delete all history…", role: .destructive) { confirmingDeleteAll = true }
                        .disabled(isLoading || storageError != nil || transitions.isEmpty)
                        .accessibilityIdentifier(CamLidAccessibility.IDs.activityDelete)
                  } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Activity actions")
                    .help("Refresh or delete local activity")
            }
        }
    }


    private var countText: String {
        if !filter.isActive { return transitions.count == 1 ? "1 record" : "\(transitions.count) records" }
        return "\(filtered.count) of \(transitions.count) records"
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "Just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    private var allReasonCodes: [String] {
        Array(Set(transitions.flatMap(\.reasonCodes))).sorted()
    }

    private var filtered: [StoredTransition] {
        transitions.filter(filter.matches).sorted { $0.timestamp > $1.timestamp }
    }

    private func row(_ record: StoredTransition) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                if [ActivityCategory.configuration, .enrollment].contains(record.category) {
                    Text(record.reasonCodes.map(ActivityPresentation.readableReason).joined(separator: ", "))
                }
                Text("State: " + CamLidAccessibility.StatusStyle.style(for: record.newState).text)
                if let provider = record.providerKind { Text("Agent: " + provider.capitalized) }
                if let cleanup = record.cleanupOutcome { Text("Cleanup: " + cleanup.rawValue) }
                if let session = record.sessionID {
                    HStack {
                        Text("Session: " + session).textSelection(.enabled)
                        Spacer()
                        Button("Delete session…", role: .destructive) { pendingSessionDelete = session }
                            .buttonStyle(.link)
                            .disabled(isLoading || storageError != nil)
                    }
                }
                Text("Reason codes: " + record.reasonCodes.joined(separator: ", ")).textSelection(.enabled)
            }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ActivityPresentation.title(record)).font(.body)
                    Spacer()
                    Text(relativeTimestamp(record.timestamp))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .help(activityDateFormatter.string(from: record.timestamp))
                }
                if ![ActivityCategory.configuration, .enrollment].contains(record.category) {
                    Text(record.reasonCodes.map(ActivityPresentation.readableReason).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.disclosureGroupStyle(RowDisclosureStyle()).padding(.vertical, 2)
    }

    /// Hosts feed the returned receipt back here to surface the count.
    public func receiptText(_ receipt: DeletionReceipt) -> String {
        "Deleted \(receipt.removedCount) record(s) (\(receipt.scope.rawValue)) at \(activityDateFormatter.string(from: receipt.deletedAt))."
    }
}

/// Labels are a presentation layer; stored categories, reasons and states stay intact.
enum ActivityPresentation {
    static func categoryName(_ category: ActivityCategory) -> String {
        switch category {
        case .stateTransition: "Session state"
        case .safetyStop: "Safety stops"
        case .grace: "Sleep when done"
        case .capExpiry: "Session limit"
        case .recovery: "Recovery"
        case .enrollment: "Agent activity"
        case .configuration: "Settings & sensors"
        }
    }
    static func title(_ record: StoredTransition) -> String {
        if ![ActivityCategory.configuration, .enrollment].contains(record.category),
            let previous = record.previousState, previous != record.newState {
            return CamLidAccessibility.StatusStyle.style(for: previous).text + " → "
                + CamLidAccessibility.StatusStyle.style(for: record.newState).text
        }
        return record.reasonCodes.first.map(readableReason) ?? record.category.rawValue.capitalized
    }

    static func readableReason(_ code: String) -> String {
        switch code {
        case "agentToolFailed": return "Agent tool failed; turn outcome is separate"
        case "backendPendingM1", "backendUnverified": return "Closed-lid backend unavailable"
        case "agentEvent": return "Agent activity updated"
        case "sleepBlocked": return "Sleep request blocked"
        case "configApplied": return "Settings updated"
        case "modeChanged": return "Mode changed"
        case "appLaunched": return "CamLid opened"
        case "onboardingComplete": return "Welcome completed"
        case "previewSessionStarted": return "Preview session started"
        case "previewSessionStopped": return "Preview session stopped"
        case "sessionTimerChanged": return "Timer changed"
        case "sessionSleepDelayChanged": return "Sleep when done changed"
        case "lidAvailabilityChanged": return "Lid reading availability changed"
        case "temperatureAvailabilityChanged": return "Temperature availability changed"
        case "batteryFloor": return "Battery below minimum"
        case "notCharging": return "AC power required"
        case "thermalCritical": return "Critical thermal pressure"
        default: return code.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
        }
    }
}

#Preview("Loading activity") {
    ActivityLogView(transitions: [], isLoading: true,
                    onExportRedacted: {}, onDeleteSession: { _ in }, onDeleteAll: {})
}

#Preview("Unavailable history") {
    ActivityLogView(transitions: [], storageError: "Read unavailable",
                    onExportRedacted: {}, onDeleteSession: { _ in }, onDeleteAll: {})
}
