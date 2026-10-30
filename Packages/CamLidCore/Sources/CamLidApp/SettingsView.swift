import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CamLidCore

/// Single-field validation failure. `field` selects where the message renders.
public struct SettingsFieldError: Sendable, Equatable, Identifiable {
    public enum Field: String, Sendable, CaseIterable {
        case timer
        case completionDelay
        case waitRetention
        case batteryFloor
        case batteryEntry
        case batteryCap
        case runCap
        case adapters
    }

    public var id: Field { field }
    public let field: Field
    public let message: String
}

/// Editable draft mirroring Configuration. Bounds MUST match
/// Configuration.validate() ranges (authority); they are duplicated here so
/// the UI can explain errors beside each field before atomic apply.
public struct SettingsDraft: Sendable, Equatable {
    // Authority: Configuration.validate(). Keep in sync.
    public static let completionDelayRange = 0...30
    public static let waitRetentionRange = 0...30
    public static let batteryFloorRange = 10...50
    public static let batteryEntryRange = 20...80
    public static let batteryCapRange = 15...240
    public static let runCapRange = 5...480

    public var mode: RequestedMode
    public var closedLidOptIn: Bool
    public var completionDelayMinutes: Int
    public var waitRetentionMinutes: Int
    public var batteryFloorPercent: Int
    public var chargingOnly: Bool
    public var batteryModeAllowed: Bool
    public var batteryEntryPercent: Int
    public var batteryCapMinutes: Int
    public var runCapMinutes: Int
    public var timerMinutes: Int?
    var defaultTimerMinutes: Int { timerMinutes ?? (mode == .manual ? 0 : runCapMinutes) }
    public var allowDisplaySleep: Bool?
    public var cpuStopEnabled: Bool
    /// Free-text editing surface for adapterEnrollment; parsed on apply.
    public var adapterEnrollmentText: String
    public var orcaMetadataConsent: Bool?
    public var notificationCategories: [NotificationCategory]?
    public var launchAtLogin: Bool
    public var telemetryEnabled: Bool
    public var lifetimeRules: [LifetimeRule]?

    public init(configuration: Configuration) {
        mode = configuration.mode
        closedLidOptIn = configuration.closedLidOptIn
        completionDelayMinutes = configuration.completionDelayMinutes
        waitRetentionMinutes = configuration.waitRetentionMinutes
        batteryFloorPercent = configuration.batteryFloorPercent
        chargingOnly = configuration.chargingOnly
        batteryModeAllowed = configuration.batteryModeAllowed
        batteryEntryPercent = configuration.batteryEntryPercent
        batteryCapMinutes = configuration.batteryCapMinutes
        runCapMinutes = configuration.runCapMinutes
        timerMinutes = configuration.timerMinutes
        allowDisplaySleep = configuration.allowDisplaySleep
        cpuStopEnabled = configuration.cpuStopEnabled
        adapterEnrollmentText = configuration.adapterEnrollment.joined(separator: "\n")
        orcaMetadataConsent = configuration.orcaMetadataConsent
        notificationCategories = configuration.notificationCategories
        launchAtLogin = configuration.launchAtLogin
        telemetryEnabled = configuration.telemetryEnabled
        lifetimeRules = configuration.lifetimeRules
    }

    public func validate() -> [SettingsFieldError] {
        var errors: [SettingsFieldError] = []
        func check(_ field: SettingsFieldError.Field, _ value: Int, _ range: ClosedRange<Int>, unit: String) {
            guard !range.contains(value) else { return }
            errors.append(SettingsFieldError(
                field: field,
                message: "Must be \(range.lowerBound)–\(range.upperBound) \(unit); got \(value)."
            ))
        }
        check(.completionDelay, completionDelayMinutes, Self.completionDelayRange, unit: "minutes")
        check(.waitRetention, waitRetentionMinutes, Self.waitRetentionRange, unit: "minutes")
        check(.batteryFloor, batteryFloorPercent, Self.batteryFloorRange, unit: "percent")
        check(.batteryEntry, batteryEntryPercent, Self.batteryEntryRange, unit: "percent")
        check(.batteryCap, batteryCapMinutes, Self.batteryCapRange, unit: "minutes")
        if batteryEntryPercent <= batteryFloorPercent {
            errors.append(SettingsFieldError(field: .batteryEntry, message: "Entry level must be above the stop level."))
        }
        check(.runCap, runCapMinutes, Self.runCapRange, unit: "minutes")
        if let timerMinutes, timerMinutes != 0, !Self.runCapRange.contains(timerMinutes) {
            errors.append(SettingsFieldError(field: .timer, message: "Use 0 for Infinite or 5–480 minutes."))
        }
        for entry in parsedAdapters() where entry.count > PolicyLimits.maxStringLength {
            errors.append(SettingsFieldError(field: .adapters, message: "Entry exceeds 256 characters."))
            break
        }
        return errors
    }

    public func parsedAdapters() -> [String] {
        adapterEnrollmentText
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Atomic apply: returns a validated Configuration or throws ConfigError;
    /// the caller's stored config is untouched on failure.
    public func makeConfiguration() throws(ConfigError) -> Configuration {
        var patch = ConfigPatch()
        patch.mode = mode
        patch.closedLidOptIn = closedLidOptIn
        patch.completionDelayMinutes = completionDelayMinutes
        patch.waitRetentionMinutes = waitRetentionMinutes
        patch.batteryFloorPercent = batteryFloorPercent
        patch.chargingOnly = chargingOnly
        patch.batteryModeAllowed = batteryModeAllowed
        patch.batteryEntryPercent = batteryEntryPercent
        patch.batteryCapMinutes = batteryCapMinutes
        patch.runCapMinutes = runCapMinutes
        patch.timerMinutes = timerMinutes
        patch.allowDisplaySleep = allowDisplaySleep
        patch.cpuStopEnabled = cpuStopEnabled
        patch.adapterEnrollment = parsedAdapters()
        patch.orcaMetadataConsent = orcaMetadataConsent
        patch.notificationCategories = notificationCategories
        patch.launchAtLogin = launchAtLogin
        patch.telemetryEnabled = telemetryEnabled
        patch.lifetimeRules = lifetimeRules
        let base = try Configuration()
        return try base.applying(patch)
    }
}

/// One detected provider row for the Agents tab.
public struct IntegrationRow: Sendable, Equatable, Identifiable {
    public var id: String { provider }
    public let provider: String
    public let version: String?
    public let confidence: Confidence
    public let enrolled: Bool

    public init(provider: String, version: String? = nil, confidence: Confidence, enrolled: Bool) {
        self.provider = provider
        self.version = version
        self.confidence = confidence
        self.enrolled = enrolled
    }
}

/// Pending opt-in integration change previewed before apply.
public struct IntegrationDiff: Sendable, Equatable {
    public let added: [String]
    public let removed: [String]

    public init(added: [String] = [], removed: [String] = []) {
        self.added = added
        self.removed = removed
    }

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }
}

/// Single native Settings scene (specs/005-native-ux T003, FR-015).
/// Native panes with immediate, revision-aware preference persistence.
/// Failed or pending edits remain visible and native close is guarded.
/// Hosted by the real app in a Settings scene (Cmd-comma where active).
public struct SettingsView: View {
    @ObservedObject public var editor: SettingsEditor
    @State private var safetyExpanded = false
    public let statusSummary: String
    public let onCommit: (ConfigPatch, Int) -> SettingsCommitResult
    public let onClose: () -> Void
    public let onOpenActivityLog: () -> Void
    public let onSectionChange: (SettingsSection) -> Void
    public let onOpenSleepDiagnostics: (() -> Void)?
    public let showsPanePicker: Bool

    public init(editor: SettingsEditor, statusSummary: String,
        onCommit: @escaping (ConfigPatch, Int) -> SettingsCommitResult,
        onClose: @escaping () -> Void, onOpenActivityLog: @escaping () -> Void,
        onSectionChange: @escaping (SettingsSection) -> Void = { _ in },
        showsPanePicker: Bool = true, onOpenSleepDiagnostics: (() -> Void)? = nil) {
        self.editor = editor; self.statusSummary = statusSummary
        self.onCommit = onCommit; self.onClose = onClose
        self.onOpenActivityLog = onOpenActivityLog; self.onSectionChange = onSectionChange
        self.showsPanePicker = showsPanePicker
        self.onOpenSleepDiagnostics = onOpenSleepDiagnostics
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsPanePicker {
                Picker("Settings section", selection: $editor.section) {
                    ForEach(SettingsSection.allCases, id: \.self) { section in
                        Label(section.title, systemImage: section.symbol).tag(section).help(section.title + " settings")
                    }
                }
                .pickerStyle(.segmented).labelsHidden().accessibilityLabel("Settings sections")
                .padding(12).accessibilityIdentifier(CamLidAccessibility.IDs.settingsTabs)
                Divider()
            }
            ScrollView { settingsForm }
                .accessibilityIdentifier("camlid.settings.scroll")
            if let message = editor.message, editor.fieldMessages.isEmpty,
                !["Applied", "Changes saved.", "Current settings loaded.", "Editing…", "Applying…"].contains(message) {
                CamLidStatusLabel(message, systemImage: "exclamationmark.circle",
                                  tone: .danger, help: message)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 160, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: editor.section) { _, section in onSectionChange(section) }
        .onAppear { editor.configureAutosave(onCommit) }
    }

    private var settingsForm: some View {
        Form {
            switch editor.section {
            case .defaults: SettingsDefaultsPane(editor: editor)
            case .agents: SettingsAgentsPane(editor: editor)
            case .lifetime: SettingsLifetimePane(editor: editor)
            case .safety: SettingsSafetyPane(editor: editor, onOpenSleepDiagnostics: onOpenSleepDiagnostics, isExpanded: $safetyExpanded)
            case .permissions: SettingsPermissionsPane(editor: editor)
            case .activity: SettingsActivityPane(onOpen: onOpenActivityLog)
            }
        }.formStyle(.grouped).padding(8)
    }
}

private struct SettingsPermissionsPane: View {
    @ObservedObject var editor: SettingsEditor

    private var canRequest: Bool {
        ["notDetermined", "unavailable"].contains(editor.notificationPermission)
    }

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                PermissionStatusLabel(status: editor.notificationPermission)
                    .accessibilityIdentifier("camlid.permissions.notifications.status")
                Spacer()
                Button { editor.onRefreshPermissions?() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Check notification permission again")
                .accessibilityLabel("Refresh permission status")
                .accessibilityIdentifier("camlid.permissions.refresh")
            }
            if canRequest {
                Button("Allow Notifications…") { editor.onAuthorizeNotifications?() }
                    .accessibilityIdentifier("camlid.permissions.notifications.request")
            }
            Button("Open Notifications Settings…") { editor.onOpenNotificationSettings?() }
                .accessibilityLabel("Open Notifications in System Settings")
                .accessibilityIdentifier("camlid.permissions.notifications.settings")
            if let error = editor.permissionSettingsError {
                CamLidStatusLabel(error, systemImage: "exclamationmark.triangle", tone: .warning)
            }
        } header: {
            Text("Notifications — optional", bundle: .module)
        } footer: {
            Text("Choose alert categories in Defaults. CamLid doesn’t need Screen Recording or Full Disk Access.", bundle: .module)
        }
    }
}

private struct PermissionStatusLabel: View {
    let status: String
    var body: some View {
        switch status {
        case "granted", "authorized":
            CamLidStatusLabel(Text("Allowed", bundle: .module), systemImage: "checkmark.circle", tone: .success)
        case "provisional":
            CamLidStatusLabel(Text("Allowed — quiet delivery", bundle: .module), systemImage: "checkmark.circle", tone: .success)
        case "notGranted", "denied":
            CamLidStatusLabel(Text("Not allowed", bundle: .module), systemImage: "lock.circle", tone: .warning)
        case "notDetermined":
            CamLidStatusLabel(Text("Not requested", bundle: .module), systemImage: "questionmark.circle")
        case "requesting":
            CamLidStatusLabel(Text("Waiting for macOS approval", bundle: .module), systemImage: "clock")
        case "unavailable":
            CamLidStatusLabel(Text("Unavailable in this app host", bundle: .module), systemImage: "exclamationmark.circle", tone: .warning)
        default:
            CamLidStatusLabel(Text("Unknown", bundle: .module), systemImage: "questionmark.circle")
        }
    }
}

private struct SettingsDefaultsPane: View {
    @ObservedObject var editor: SettingsEditor
    var body: some View {
        Section {
            SettingsNumberField(editor: editor, title: "Default Timed duration", field: .timer, unit: "minutes")
            SettingsNumberField(editor: editor, title: "Default Sleep when done", field: .completionDelay, unit: "minutes")
        } header: {
            Text("New sessions")
        } footer: {
            Text("Defaults apply when starting a mode. Dashboard edits apply to the current session.")
        }
        Section("App") {
            Toggle("Launch at login", isOn: Binding(get: { editor.draft.launchAtLogin }, set: editor.setLaunchAtLogin))
                .help("Open CamLid at login without starting a session")
                .accessibilityLabel("Launch at login")
                .accessibilityIdentifier("camlid.settings.launchAtLogin")
            Text(editor.loginMessage).font(.caption).foregroundStyle(.secondary)
            if editor.loginState == "error" || editor.loginState == "requiresApproval" || (editor.draft.launchAtLogin != (editor.loginState == "enabled")) {
                Button("Apply startup preference") { editor.onApplyLogin?() }
            }
            SettingsFieldOutcome(editor: editor, key: "launchAtLogin")
        }
        Section("Notifications") {
            ForEach(NotificationCategory.allCases, id: \.self) { category in
                Toggle(category.title, isOn: Binding(get: { editor.draft.notificationCategories?.contains(category) ?? false },
                    set: { editor.setNotification(category, enabled: $0) }))
                    .help("Send a local notification for " + category.title.lowercased())
                    .accessibilityLabel(category.title)
                    .accessibilityIdentifier("camlid.settings.notification." + category.rawValue)
            }
            Text(notificationMessage)
                .font(.caption).foregroundStyle(.secondary)
            if ["notDetermined", "unavailable"].contains(editor.notificationPermission), !(editor.draft.notificationCategories ?? []).isEmpty {
                Button("Allow notifications…") { editor.onAuthorizeNotifications?() }
            }
            SettingsFieldOutcome(editor: editor, key: "notificationCategories")
        }
        Section("Display") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Allow display sleep", isOn: Binding(get: { editor.draft.allowDisplaySleep ?? true }, set: editor.setAllowDisplaySleep))
                    .help("Allow the display to sleep during an awake session; off keeps the display awake too")
                    .accessibilityLabel("Allow display sleep")
                    .accessibilityIdentifier("camlid.settings.allowDisplaySleep")
                Text("When on, the display may sleep while the system keeps running. When off, both stay awake during a session.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Saved preference only in this preview. Power control is unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsFieldOutcome(editor: editor, key: "allowDisplaySleep")
        }
    }
    private var notificationMessage: String {
        switch editor.notificationPermission {
        case "denied": "Notifications are disabled in macOS. Enable CamLid in System Settings → Notifications."
        case "requesting": "Waiting for macOS notification approval."
        case "authorized", "provisional": "Notifications allowed by macOS. Preview alerts never claim a power change."
        case "unavailable", "unknown": "Notification permission is unavailable. Retry from an installed app."
        default: "Alerts are local only. Turn on a category to request permission. Preview alerts never claim a power change."
        }
    }
}

private struct SettingsAgentsPane: View {
    @ObservedObject var editor: SettingsEditor
    private var orderedBadges: [AgentBadgeState] {
        AgentBadgeState.providers.map { provider in
            editor.badges.first { $0.provider == provider }
                ?? AgentBadgeState(provider: provider, enabled: editor.draft.parsedAdapters().contains(provider), tasks: [])
        }.sortedForAgentDisplay(detectedFirst: true)
    }
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                BadgeFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(orderedBadges) { state in
                        SettingsAgentBadge(state: state, enabled: editor.draft.parsedAdapters().contains(state.provider), showsCLIInstallation: true) {
                            editor.setProvider(state.provider, enabled: $0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(orderedBadges) { state in
                    SettingsFieldOutcome(editor: editor, key: "provider:" + state.provider)
                }
            }
        } header: {
            HStack {
                Text("Agents that may delay sleep")
                Spacer()
                Button("Enable all") { editor.enableAllProviders() }
                    .disabled(editor.selectableProviders.allSatisfy { editor.draft.parsedAdapters().contains($0) })
                    .help("Include all agents in sleep decisions")
                    .accessibilityIdentifier("camlid.agents.enableAll")
            }
        }
    }
}

private struct SettingsLifetimePane: View {
    @ObservedObject var editor: SettingsEditor
    @State private var selectorKind: LifetimeSelectorKind = .exactExecutablePath
    @State private var selectorValue = ""
    @State private var label = ""
    @State private var error: String?

    private var rules: [LifetimeRule] { editor.draft.lifetimeRules ?? [] }
    private var selectorTitle: String {
        selectorKind == .exactExecutablePath ? "Executable path" : "App bundle ID"
    }
    private var selectorPlaceholder: String {
        selectorKind == .exactExecutablePath ? "Path to an installed executable" : "com.example.app"
    }

    var body: some View {
        Section {
            if rules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("No watched programs yet", systemImage: "eye.slash")
                        .font(.callout)
                    Text("Add a program below to keep an Auto session awake while it runs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(rules) { rule in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Toggle(rule.label, isOn: Binding(
                            get: { rule.enabled },
                            set: { enabled in
                                var updated = rules
                                guard let index = updated.firstIndex(where: { $0.id == rule.id }) else { return }
                                updated[index].enabled = enabled
                                editor.setLifetimeRules(updated)
                            }))
                            .accessibilityIdentifier("camlid.settings.lifetime.enabled." + rule.id.uuidString)
                        Spacer()
                        Button("Remove") { editor.setLifetimeRules(rules.filter { $0.id != rule.id }) }
                            .accessibilityIdentifier("camlid.settings.lifetime.remove." + rule.id.uuidString)
                    }
                    Text((rule.selectorKind == .exactExecutablePath ? "Executable path · " : "App bundle ID · ") + rule.selectorValue)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
            SettingsFieldOutcome(editor: editor, key: "lifetimeRules")
        } header: {
            Text("Watched programs")
        } footer: {
            Text("Watching a program doesn’t start a session or prove AI work. It only keeps an already-started Auto session awake while the program runs.")
        }

        Section("Add a watched program") {
            Picker("Selection type", selection: $selectorKind) {
                Text("Executable path").tag(LifetimeSelectorKind.exactExecutablePath)
                Text("App bundle ID").tag(LifetimeSelectorKind.applicationBundleID)
            }
            .accessibilityIdentifier("camlid.settings.lifetime.selectorKind")
            .onChange(of: selectorKind) { _, _ in error = nil }
            LabeledContent(selectorTitle) {
                HStack(spacing: 8) {
                    TextField(selectorPlaceholder, text: $selectorValue)
                        .labelsHidden().textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("camlid.settings.lifetime.selectorValue")
                    Button("Choose…") { chooseProgram() }
                        .help(selectorKind == .exactExecutablePath ? "Choose an installed executable" : "Choose an installed app")
                }
            }
            LabeledContent("Label") {
                TextField("Name for this program", text: $label)
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("camlid.settings.lifetime.label")
            }
            Button("Add Program") { addRule() }
                .disabled(selectorValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || rules.count >= LifetimeRule.maximumRules)
                .help("Add this program to the watched list")
                .accessibilityIdentifier("camlid.settings.lifetime.add")
            if rules.count >= LifetimeRule.maximumRules {
                Text("The limit is 20 rules.").font(.caption).foregroundStyle(.secondary)
            }
            if let error {
                CamLidStatusLabel(error, systemImage: "exclamationmark.circle",
                                  tone: .danger, font: .caption)
                    .accessibilityIdentifier("camlid.settings.lifetime.error")
            }
        }
    }

    private func chooseProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if selectorKind == .applicationBundleID {
            panel.allowedContentTypes = [.application]
            panel.message = "Choose an application to watch."
        } else {
            panel.message = "Choose an executable to watch."
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if selectorKind == .applicationBundleID {
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
                error = "That app doesn’t have a bundle identifier."
                return
            }
            selectorValue = identifier
            if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                label = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
            }
        } else {
            selectorValue = url.path
            if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                label = url.lastPathComponent
            }
        }
        error = nil
    }

    private func addRule() {
        let value = selectorValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let ruleLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rules.count < LifetimeRule.maximumRules else { error = "The limit is 20 rules."; return }
        if selectorKind == .exactExecutablePath {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: value, isDirectory: &isDirectory), !isDirectory.boolValue,
                  FileManager.default.isExecutableFile(atPath: value) else {
                error = "Choose an installed executable file."; return
            }
        } else {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value),
                  Bundle(url: app)?.bundleIdentifier == value else {
                error = "Choose an installed app bundle ID."; return
            }
        }
        do {
            let rule = try LifetimeRule(selectorKind: selectorKind, selectorValue: value, label: ruleLabel)
            var updated = rules
            updated.append(rule)
            editor.setLifetimeRules(updated)
            guard editor.fieldMessages["lifetimeRules"] == nil else { error = editor.fieldMessages["lifetimeRules"]; return }
            selectorValue = ""; label = ""; error = nil
        } catch {
            self.error = "Use an exact normalized path or installed bundle ID, with a label of at most 80 characters."
        }
    }
}

private struct SettingsClosedLidSection: View {
    @ObservedObject var editor: SettingsEditor
    @State private var confirmingUntested = false

    private var systemText: String { "\(editor.systemModel), macOS \(editor.systemBuild)" }
    private var testedText: String {
        if editor.closedLidPermit.hasPrefix("qualified:") { return "Tested" }
        return editor.closedLidPermit == "untestedAcknowledged" ? "Untested — allowed" : "Not tested"
    }

    private var installed: Bool { ["installed", "installedNotLoaded", "needsReauthorization", "helperIdentityMismatch", "partial"].contains(editor.helperState) }

    var body: some View {
        Section {
            LabeledContent("Mode") {
                Text(PowerMode.standard.title)
            }
            .accessibilityElement(children: .combine)
            Text(PowerMode.standard.disclosure)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Strict (experimental)") {
                Text("Unavailable")
            }
            .accessibilityElement(children: .combine)
            Text(PowerMode.strict.disclosure)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("This Mac") {
                Text(systemText)
            }
            .accessibilityElement(children: .combine)
            LabeledContent("Testing") {
                Text(testedText)
            }
            .accessibilityElement(children: .combine)
            if !editor.closedLidPermit.hasPrefix("qualified:") {
                Toggle("Allow on this untested Mac", isOn: Binding(
                    get: { editor.closedLidPermit == "untestedAcknowledged" },
                    set: { allow in
                        if allow { confirmingUntested = true } else { editor.onSetUntestedAcknowledgement?(false) }
                    }))
                    .help("Closed lid has not been tested on this model and macOS build")
                    .accessibilityIdentifier("camlid.settings.closedLid.allowUntested")
            }
            ForEach(editor.conflictingHelpers, id: \.self) { app in
                Label("\(app) resets the sleep setting and will interrupt closed lid. Quit \(app) or remove its helper.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Helper") {
                Text(editor.helperBusy ? "Working…" : helperLabel)
            }
            .accessibilityElement(children: .combine)
            Text(editor.helperMessage)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(installed ? "Reinstall helper…" : "Install helper…") { editor.onInstallHelper?() }
                    .disabled(editor.helperBusy)
                    .help("Asks for an administrator password once")
                    .accessibilityIdentifier("camlid.settings.helper.install")
                if installed {
                    Button("Remove helper…") { editor.onUninstallHelper?() }
                        .disabled(editor.helperBusy)
                        .accessibilityIdentifier("camlid.settings.helper.remove")
                }
            }
        } header: {
            Text("Closed lid")
        } footer: {
            Text("Installing the helper doesn’t start a session or change sleep settings by itself.")
        }
        .alert("Allow closed lid on an untested Mac?", isPresented: $confirmingUntested) {
            Button("Allow") { editor.onSetUntestedAcknowledgement?(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("CamLid hasn’t been tested on \(systemText). If something fails, this Mac may stay awake with the lid closed until the helper or its recovery job restores the sleep setting. This applies to this Mac and macOS build only; you can turn it off at any time.")
        }
    }

    private var helperLabel: String {
        switch editor.helperState {
        case "installed": "Installed"
        case "notInstalled": "Not installed"
        case "unknown": "Not checked"
        default: "Needs attention"
        }
    }
}

private struct SettingsSafetyPane: View {
    @ObservedObject var editor: SettingsEditor
    let onOpenSleepDiagnostics: (() -> Void)?
    @Binding var isExpanded: Bool

    private var powerSourceSummary: String {
        if editor.draft.chargingOnly {
            return editor.draft.batteryModeAllowed
                ? "Charger required. Battery is allowed but won’t be used until Require charger is off."
                : "Sessions require the charger. Battery sessions are off."
        }
        return editor.draft.batteryModeAllowed
            ? "Sessions can run on battery within the limits below."
            : "Sessions won’t start on battery until Allow battery sessions is on."
    }

    var body: some View {
        Section {
            PreviewBuildNotice()
        }
        SettingsClosedLidSection(editor: editor)
        Section {
            Toggle("Require charger", isOn: Binding(get: { editor.draft.chargingOnly }, set: editor.setChargingOnly))
                .accessibilityLabel(Text("Require charger", bundle: .module))
                .help("Battery sessions remain blocked while the charger is required")
            Toggle("Allow battery sessions", isOn: $editor.batterySessionsAllowed)
                .accessibilityIdentifier("camlid.settings.batteryMode")
                .accessibilityLabel(Text("Allow battery sessions", bundle: .module))
                .help("Takes effect when Require charger is off")
            SettingsFieldOutcome(editor: editor, key: "chargingOnly")
            SettingsFieldOutcome(editor: editor, key: "batteryModeAllowed")
            Text(powerSourceSummary)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Power source", bundle: .module)
        }
        Section {
            SettingsNumberField(editor: editor, title: "Start on battery at or above", field: .batteryEntry, unit: "%")
            SettingsNumberField(editor: editor, title: "Stop below battery level", field: .batteryFloor, unit: "%")
            SettingsNumberField(editor: editor, title: "Battery session limit", field: .batteryCap, unit: "minutes")
            Text("Battery sessions stop at the shorter battery or session limit, measured from session start. Reconnecting the charger doesn’t extend this deadline.", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Battery limits", bundle: .module)
        }
        Section {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Overheating protection", value: "Always on")
                    .help("Uses macOS thermal pressure, independently of the temperature reading")
                Text("Stops immediately at critical thermal pressure, or after 30 seconds at serious pressure.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsNumberField(editor: editor, title: "Session time limit", field: .runCap, unit: "minutes")
            Text("Auto and finite Timed stop at this limit. Infinite ignores it only on charger power.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Safety limits", bundle: .module)
        } footer: {
            Text("Low battery and overheating stop every mode. Keep the Mac ventilated.", bundle: .module)
        }
        if let onOpenSleepDiagnostics {
            Section {
                Button("Why is my Mac awake?…", action: onOpenSleepDiagnostics)
                    .help("Inspect current sleep requests by app or process; no power settings are changed")
                    .accessibilityIdentifier("camlid.settings.sleepDiagnostics")
            }
        }
        Section {
            DisclosureGroup("Advanced", isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    SettingsNumberField(editor: editor, title: "Retain waiting sessions", field: .waitRetention, unit: "minutes")
                    Text("Waiting sessions remain tracked for this long. Waiting never keeps the Mac awake.", bundle: .module)
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Stop if CPU stays busy", isOn: Binding(get: { editor.draft.cpuStopEnabled }, set: editor.setCPUStop))
                        .accessibilityLabel(Text("Stop if CPU stays busy", bundle: .module))
                        .accessibilityIdentifier("camlid.settings.cpuStopEnabled")
                        .help("Optional stop at 90% CPU for 2 minutes; thermal protection always applies")
                    Text("Stops at 90% CPU for 2 minutes.").font(.caption).foregroundStyle(.secondary)
                }
                SettingsFieldOutcome(editor: editor, key: "cpuStopEnabled")
            }.disclosureGroupStyle(RowDisclosureStyle()).help("Waiting and CPU safety preferences")
        }
    }
}

private struct SettingsActivityPane: View {
    let onOpen: () -> Void
    var body: some View {
        Section {
            Label("History stays on this Mac", systemImage: "lock.shield")
                .font(.callout)
            Text("CamLid records mode changes, safety stops and agent activity — never prompts, code or transcripts.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Kept for 14 days or up to 20 MiB, whichever comes first. Exports hide identifiers.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Open Activity…", action: onOpen)
                    .help("Search, export or delete local activity")
            }
        } header: {
            Text("Private history")
        } footer: {
            Text("Search, export or delete local activity at any time.")
        }
    }
}

private struct SettingsFieldOutcome: View {
    @ObservedObject var editor: SettingsEditor
    let key: String
    var body: some View {
        if let message = editor.fieldMessages[key] {
            VStack(alignment: .leading, spacing: 4) {
                CamLidStatusLabel(message,
                                  systemImage: message == "Applying…" ? "clock" : "exclamationmark.circle",
                                  tone: message == "Applying…" ? .neutral : .danger,
                                  help: message)
                if message != "Applying…" {
                    HStack {
                        if message == "Changed elsewhere" {
                            Button("Use current") { editor.useCurrent(key: key) }
                            Button("Apply my value") { editor.applyMyValue(key: key) }
                        } else { Button("Retry") { editor.retry(key: key) } }
                    }
                }
            }
        }
    }
}

private struct SettingsNumberField: View {
    @ObservedObject var editor: SettingsEditor
    let title: String
    let field: SettingsFieldError.Field
    let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: Binding<Int>(get: {
                editor.customFields.contains(field) ? -1 : (NumericChoice.parse(editor.numbers[field] ?? "") ?? -1)
            }, set: { value in
                if value == -1 { editor.chooseCustom(field) } else { editor.selectPreset(value, field: field) }
            })) {
                ForEach(NumericChoice.presets(field), id: \.self) { value in
                    Text(NumericChoice.label(value, field: field)).tag(value)
                }
                Text("Custom…").tag(-1)
            }.accessibilityIdentifier("camlid.settings.\(field.rawValue).choice")
                .accessibilityLabel(Text(title)).help(helpText)
            if editor.customFields.contains(field) {
                CustomNumberInput(editor: editor, title: title, field: field, unit: unit)
            }
            if let error = editor.errors.first(where: { $0.field == field }) {
                CamLidStatusLabel(error.message, systemImage: "exclamationmark.circle",
                                  tone: .danger, help: error.message)
            }
            SettingsFieldOutcome(editor: editor, key: SettingsEditor.key(field))
        }
    }
    private var helpText: String {
        switch field {
        case .timer: "Default for new Timed sessions; Infinite bypasses time limits only on charger power. Battery and thermal limits always apply."
        case .completionDelay: "Default delay after selected work ends in a new Auto session"
        case .waitRetention: "How long a waiting task may hold an Auto session"
        case .batteryFloor: "End the session below this battery level"
        case .batteryEntry: "20–80 percent, strictly above the stop level; checked when starting on battery"
        case .batteryCap: "15–240 minutes, bounded by the session limit; applies even to Infinite"
        case .runCap: "Time limit for Auto and finite timers; Infinite bypasses this limit only on charger power"
        case .adapters: "Agents included in sleep decisions"
        }
    }
}

private struct CustomNumberInput: NSViewRepresentable {
    let editor: SettingsEditor
    let title: String
    let field: SettingsFieldError.Field
    let unit: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let view = NSTextField(); view.delegate = context.coordinator
        view.setAccessibilityLabel("\(title), \(unit)")
        view.setAccessibilityIdentifier("camlid.settings.\(field.rawValue)")
        view.placeholderString = "Custom \(unit)"
        Task { @MainActor [weak view] in
            guard let view, let window = view.window, window.isKeyWindow else { return }
            window.makeFirstResponder(view)
        }
        return view
    }
    func updateNSView(_ view: NSTextField, context: Context) {
        context.coordinator.parent = self
        let text = editor.numbers[field] ?? ""
        if view.stringValue != text, view.currentEditor() == nil { view.stringValue = text }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomNumberInput
        init(_ parent: CustomNumberInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextField else { return }
            let composing = (view.currentEditor() as? NSTextView)?.hasMarkedText() == true
            parent.editor.editNumber(view.stringValue, field: parent.field, composing: composing)
        }
        func controlTextDidEndEditing(_ notification: Notification) { parent.editor.commitNumber(parent.field) }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.editor.commitNumber(parent.field); return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.editor.cancelNumber(parent.field); control.stringValue = parent.editor.numbers[parent.field] ?? ""; return true
            }
            return false
        }
    }
}
