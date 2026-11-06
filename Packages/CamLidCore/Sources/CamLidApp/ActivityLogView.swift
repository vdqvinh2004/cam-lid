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
    @State private var showsSensorUpdates = false

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
        VStack(alignment: .leading, spacing: 10) {
            filterBar
            if !transitions.isEmpty {
                summaryRow
            }
            if storageError != nil {
                errorBanner
            }
            if isLoading && transitions.isEmpty {
                ProgressView("Loading activity…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("camlid.activity.loading")
            } else if transitions.isEmpty {
                if storageError == nil { emptyState }
            } else if filtered.isEmpty && !isLoading {
                filteredEmptyState
            } else if !filtered.isEmpty {
                List(ActivityPresentation.collapsed(filtered), id: \.record.id) { run in
                    row(run.record, repeats: run.count)
                }
                .listStyle(.plain)
                .frame(minHeight: 120, maxHeight: .infinity)
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

    private var summaryRow: some View {
        HStack(spacing: 8) {
            Text(countText).font(.caption).foregroundStyle(.secondary)
            if isLoading {
                ProgressView().controlSize(.mini)
                Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if hiddenSensorCount > 0 {
                Button("Show \(hiddenSensorCount) routine updates") { showsSensorUpdates = true }
                    .buttonStyle(.link).font(.caption)
                    .help("Sensor availability changes and repeated agent checks are routine and hidden by default")
            } else if showsSensorUpdates && sensorCount > 0 && !filter.isActive {
                Button("Hide routine updates") { showsSensorUpdates = false }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .accessibilityIdentifier("camlid.activity.count")
    }

    private var errorBanner: some View {
        CamLidNoticeCard(
            tone: .warning, systemImage: "exclamationmark.triangle.fill",
            title: transitions.isEmpty ? "History could not be read." : "History could not be refreshed. Showing previously loaded activity.",
            message: "Your saved activity hasn’t changed. Check available storage and try again.",
            actionTitle: "Retry", onAction: onRefresh
        )
        .accessibilityIdentifier("camlid.activity.error")
    }

    private var emptyState: some View {
        CamLidEmptyState(
            systemImage: "clock.arrow.circlepath", title: "No activity yet",
            message: "Session, safety and agent changes will appear here.",
            actionTitle: "Refresh", onAction: onRefresh
        )
    }

    private var filteredEmptyState: some View {
        CamLidEmptyState(
            systemImage: "line.3.horizontal.decrease.circle",
            title: hiddenSensorCount > 0 ? "Only routine updates are available." : "No events match these filters.",
            actionTitle: hiddenSensorCount > 0 ? "Show Sensor Updates" : (filter.isActive ? "Clear Filters" : nil),
            onAction: {
                if hiddenSensorCount > 0 { showsSensorUpdates = true }
                else if filter.isActive { filter = ActivityFilter() }
            }
        )
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
                    Divider()
                    Toggle("Include routine updates", isOn: $showsSensorUpdates)
                    Divider()
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
        if filter.isActive || hiddenSensorCount > 0 {
            return "\(filtered.count) of \(transitions.count) events"
        }
        return transitions.count == 1 ? "1 event" : "\(transitions.count) events"
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

    private var sensorCount: Int {
        transitions.filter(filter.matches).filter(ActivityPresentation.isRoutineSensorUpdate).count
    }

    private var hidesSensorUpdates: Bool {
        !filter.isActive && !showsSensorUpdates && sensorCount > 0
    }

    private var hiddenSensorCount: Int {
        hidesSensorUpdates ? sensorCount : 0
    }

    private var filtered: [StoredTransition] {
        var rows = transitions.filter(filter.matches).sorted { $0.timestamp > $1.timestamp }
        if hidesSensorUpdates {
            rows.removeAll(where: ActivityPresentation.isRoutineSensorUpdate)
        }
        return rows
    }

    private func row(_ record: StoredTransition, repeats: Int = 1) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                if [ActivityCategory.configuration, .enrollment].contains(record.category), !record.reasonCodes.isEmpty {
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
                if !record.reasonCodes.isEmpty {
                    Text("Reason codes: " + record.reasonCodes.joined(separator: ", ")).textSelection(.enabled)
                }
            }.font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: ActivityPresentation.symbol(record))
                    .font(.callout)
                    .foregroundStyle(ActivityPresentation.isAttention(record) ? Color.orange : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(ActivityPresentation.title(record)).font(.body)
                        if repeats > 1 {
                            Text("×\(repeats)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                .help("\(repeats) identical events in a row; the newest is shown")
                                .accessibilityLabel("\(repeats) times")
                        }
                        Spacer()
                        Text(relativeTimestamp(record.timestamp))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            .help(activityDateFormatter.string(from: record.timestamp))
                    }
                    // A second line only when it says something the title doesn't.
                    let detail = record.reasonCodes.map(ActivityPresentation.readableReason).joined(separator: ", ")
                    if ![ActivityCategory.configuration, .enrollment].contains(record.category),
                       ActivityPresentation.agentState(record) == nil, detail != ActivityPresentation.title(record) {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.disclosureGroupStyle(RowDisclosureStyle()).padding(.vertical, 3)
    }

    /// Hosts feed the returned receipt back here to surface the count.
    public func receiptText(_ receipt: DeletionReceipt) -> String {
        "Deleted \(receipt.removedCount) record(s) (\(receipt.scope.rawValue)) at \(activityDateFormatter.string(from: receipt.deletedAt))."
    }
}

/// Labels are a presentation layer; stored categories, reasons and states stay intact.
enum ActivityPresentation {
    /// Consecutive identical events (same title, state, agent, session and reasons) shown once with a count.
    /// `rows` is newest first; the newest of each run represents it.
    static func collapsed(_ rows: [StoredTransition]) -> [(record: StoredTransition, count: Int)] {
        var runs: [(record: StoredTransition, count: Int)] = []
        for row in rows {
            if let last = runs.last?.record, last.category == row.category, last.newState == row.newState,
               last.providerKind == row.providerKind, last.sessionID == row.sessionID,
               last.reasonCodes == row.reasonCodes, title(last) == title(row) {
                runs[runs.count - 1].count += 1
            } else { runs.append((row, 1)) }
        }
        return runs
    }
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
    /// Hidden by default: sensor availability flips, and the per-poll agent checks older builds recorded.
    static func isRoutineSensorUpdate(_ record: StoredTransition) -> Bool {
        record.reasonCodes == ["agentObservation"] || record.category == .configuration && record.reasonCodes.contains {
            $0 == "lidAvailabilityChanged" || $0 == "temperatureAvailabilityChanged"
        }
    }
    /// "orca:working" → "Orca: Working".
    static func agentState(_ record: StoredTransition) -> String? {
        guard record.reasonCodes.first == "agentStateChanged", record.reasonCodes.count > 1 else { return nil }
        let parts = record.reasonCodes[1].split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let name = AgentProviderCatalog.info(for: parts[0])?.title ?? parts[0].capitalized
        return name + ": " + parts[1].capitalized
    }
    static func isAttention(_ record: StoredTransition) -> Bool {
        record.category == .safetyStop || record.category == .capExpiry || record.category == .recovery
    }
    static func symbol(_ record: StoredTransition) -> String {
        if record.reasonCodes.first == "agentStateChanged", record.reasonCodes.count > 1 {
            switch record.reasonCodes[1].split(separator: ":").last?.lowercased() {
            case "working": return "play.circle"
            case "idle": return "pause.circle"
            case "waiting": return "hourglass"
            case "unknown": return "questionmark.circle"
            default: break
            }
        }
        if record.reasonCodes.contains("temperatureAvailabilityChanged") { return "thermometer" }
        if record.reasonCodes.contains("lidAvailabilityChanged") { return "laptopcomputer" }
        switch record.category {
        case .stateTransition: return "arrow.left.arrow.right"
        case .safetyStop: return "exclamationmark.triangle.fill"
        case .grace: return "moon.zzz"
        case .capExpiry: return "timer"
        case .recovery: return "arrow.counterclockwise"
        case .enrollment: return "person.2"
        case .configuration: return "slider.horizontal.3"
        }
    }
    static func title(_ record: StoredTransition) -> String {
        if let agent = agentState(record) { return agent }
        if ![ActivityCategory.configuration, .enrollment].contains(record.category),
            let previous = record.previousState, previous != record.newState {
            return CamLidAccessibility.StatusStyle.style(for: previous).text + " → "
                + CamLidAccessibility.StatusStyle.style(for: record.newState).text
        }
        return record.reasonCodes.first.map(readableReason) ?? record.category.rawValue.capitalized
    }

    static func readableReason(_ code: String) -> String {
        if code.hasPrefix("exitStatus:") { return "Command exited with status \(code.dropFirst("exitStatus:".count))" }
        if code.hasPrefix("durationSeconds:") { return "Command ran for \(code.dropFirst("durationSeconds:".count)) s" }
        switch code {
        case "agentToolFailed": return "Agent tool failed; turn outcome is separate"
        case "backendUnverified": return "Closed-lid backend unavailable"
        case "agentEvent": return "Agent activity updated"
        case "sleepBlocked": return "Sleep request blocked"
        case "configApplied": return "Settings updated"
        case "modeChanged": return "Mode changed"
        case "appLaunched": return "CamLid opened"
        case "appQuitNoOwnedPower": return "CamLid quit without a session"
        case "onboardingComplete": return "Welcome completed"
        case "sessionStarted": return "Session started"
        case "sessionStopped": return "Session stopped"
        case "modeOff": return "Mode turned off"
        case "agentStateChanged": return "Agent state changed"
        case "agentObservation": return "Agent checked"
        case "sessionTimerChanged": return "Timer changed"
        case "sessionSleepDelayChanged": return "Sleep when done changed"
        case "lidAvailabilityChanged": return "Lid reading availability changed"
        case "temperatureAvailabilityChanged": return "Temperature availability changed"
        case "batteryFloor": return "Battery below minimum"
        case "notCharging": return "AC power required"
        case "thermalCritical": return "Critical thermal pressure"
        case "cliQuit": return "Quit from the command line"
        case "appQuit": return "CamLid quit"
        case "releaseComplete": return "Sleep setting restored"
        case "graceExpired": return "Sleep when done finished"
        case "sleepRequested": return "Sleep requested"
        case "capReached": return "Time limit reached"
        case "cpuSustained", "cpuStop": return "CPU stayed busy"
        case "configWriteFailed": return "Settings could not be saved"
        case "configConflict": return "Settings changed elsewhere"
        case "configCommitUnconfirmed": return "Settings write unconfirmed"
        case "untestedConfigurationAccepted": return "Untested Mac allowed"
        case "untestedConfigurationWithdrawn": return "Untested Mac no longer allowed"
        case "safetyLatched": return "Stopped by safety"
        case "lastTaskStopped": return "Last agent task stopped"
        case "gracePending": return "Waiting to sleep"
        case "commandStarted": return "Command started"
        case "commandFinished": return "Command finished"
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
