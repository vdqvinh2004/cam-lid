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
    public var powerMode: PowerMode
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
    public var lifetimeRules: [LifetimeRule]?

    public init(configuration: Configuration) {
        mode = configuration.mode
        closedLidOptIn = configuration.closedLidOptIn
        powerMode = configuration.powerMode
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
        lifetimeRules = configuration.lifetimeRules
    }

    public func validate() -> [SettingsFieldError] {
        var errors: [SettingsFieldError] = []
        func check(_ field: SettingsFieldError.Field, _ value: Int, _ range: ClosedRange<Int>, unit: String) {
            guard !range.contains(value) else { return }
            errors.append(SettingsFieldError(
                field: field,
                message: trf("Must be %lld–%lld %@; got %lld.", range.lowerBound, range.upperBound, unit, value)
            ))
        }
        check(.completionDelay, completionDelayMinutes, Self.completionDelayRange, unit: "minutes")
        check(.waitRetention, waitRetentionMinutes, Self.waitRetentionRange, unit: "minutes")
        check(.batteryFloor, batteryFloorPercent, Self.batteryFloorRange, unit: "percent")
        check(.batteryEntry, batteryEntryPercent, Self.batteryEntryRange, unit: "percent")
        check(.batteryCap, batteryCapMinutes, Self.batteryCapRange, unit: "minutes")
        if batteryEntryPercent <= batteryFloorPercent {
            errors.append(SettingsFieldError(field: .batteryEntry, message: tr("Entry level must be above the stop level.")))
        }
        check(.runCap, runCapMinutes, Self.runCapRange, unit: "minutes")
        if let timerMinutes, timerMinutes != 0, !Self.runCapRange.contains(timerMinutes) {
            errors.append(SettingsFieldError(field: .timer, message: tr("Use 0 for Infinite or 5–480 minutes.")))
        } else if let timerMinutes, timerMinutes > runCapMinutes {
            errors.append(SettingsFieldError(field: .timer, message: trf("Use 0 for Infinite, or at most %lld minutes (the session time limit).", runCapMinutes)))
        }
        for entry in parsedAdapters() where entry.count > PolicyLimits.maxStringLength {
            errors.append(SettingsFieldError(field: .adapters, message: tr("Entry exceeds 256 characters.")))
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
        patch.powerMode = powerMode
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
    public let showsPanePicker: Bool

    public init(editor: SettingsEditor, statusSummary: String,
        onCommit: @escaping (ConfigPatch, Int) -> SettingsCommitResult,
        onClose: @escaping () -> Void, onOpenActivityLog: @escaping () -> Void,
        onSectionChange: @escaping (SettingsSection) -> Void = { _ in },
        showsPanePicker: Bool = true) {
        self.editor = editor; self.statusSummary = statusSummary
        self.onCommit = onCommit; self.onClose = onClose
        self.onOpenActivityLog = onOpenActivityLog; self.onSectionChange = onSectionChange
        self.showsPanePicker = showsPanePicker
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsPanePicker {
                Picker(tr("Settings section"), selection: $editor.section) {
                    ForEach(SettingsSection.allCases, id: \.self) { section in
                        Label(section.title, systemImage: section.symbol).tag(section).help(trf("%@ settings", section.title))
                    }
                }
                .pickerStyle(.segmented).labelsHidden().accessibilityLabel(tr("Settings sections"))
                .padding(12).accessibilityIdentifier(CamLidAccessibility.IDs.settingsTabs)
                Divider()
            }
            ScrollView { settingsForm }
                .accessibilityIdentifier("camlid.settings.scroll")
            if let stored = editor.message, editor.fieldMessages.isEmpty,
                !["Applied", "Changes saved.", "Current settings loaded.", "Editing…", "Applying…"].contains(stored) {
                let message = Localization.display(stored)
                CamLidStatusLabel(message, systemImage: "exclamationmark.circle",
                                  tone: .danger, help: message)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: editor.section) { _, section in onSectionChange(section) }
        .onAppear { editor.configureAutosave(onCommit) }
    }

    private var settingsForm: some View {
        Form {
            switch editor.section {
            case .general: SettingsGeneralPane(editor: editor, onOpenActivity: onOpenActivityLog)
            case .agents: SettingsAgentsPane(editor: editor)
            case .safety: SettingsSafetyPane(editor: editor, isExpanded: $safetyExpanded)
            }
        }.formStyle(.grouped).padding(.horizontal, 8)
    }
}

/// Defaults for new sessions, the app, notifications (with their permission) and history.
private struct SettingsGeneralPane: View {
    @ObservedObject var editor: SettingsEditor
    let onOpenActivity: () -> Void

    private static let categories = NotificationCategory.allCases
    private var permissionNeedsAction: Bool { !["granted", "authorized", "provisional"].contains(editor.notificationPermission) }

    var body: some View {
        Section {
            SettingsNumberField(editor: editor, title: tr("Default Timed duration"), field: .timer, unit: "minutes")
            SettingsNumberField(editor: editor, title: tr("Default Sleep when done"), field: .completionDelay, unit: "minutes")
            Toggle(tr("Let the display sleep during sessions"), isOn: Binding(get: { editor.draft.allowDisplaySleep ?? true },
                set: { editor.setAllowDisplaySleep($0) }))
                .help(tr("Off keeps the display on while a session keeps the Mac awake. The change applies to the next session."))
                .accessibilityLabel(tr("Let the display sleep during sessions"))
                .accessibilityIdentifier("camlid.settings.displaySleep")
        } header: {
            Text(tr("New sessions"))
        } footer: {
            Text(tr("The Dashboard changes only the current session."))
        }
        Section {
            Picker(tr("Language"), selection: Binding(get: { editor.language }, set: { editor.setLanguage($0) })) {
                Text(tr("System")).tag(AppLanguage.system)
                Text("English").tag(AppLanguage.english)
                Text("Tiếng Việt").tag(AppLanguage.vietnamese)
            }
            .help(tr("Applies right away. System follows the macOS language."))
            .accessibilityIdentifier("camlid.settings.language")
        }
        Section {
            Toggle(tr("Launch at login"), isOn: Binding(get: { editor.draft.launchAtLogin }, set: editor.setLaunchAtLogin))
                .help(tr("Open CamLid at login without starting a session"))
                .accessibilityLabel(tr("Launch at login"))
                .accessibilityIdentifier("camlid.settings.launchAtLogin")
            if editor.loginState == "error" || editor.loginState == "requiresApproval" || (editor.draft.launchAtLogin != (editor.loginState == "enabled")) {
                Text(Localization.display(editor.loginMessage)).font(.caption).foregroundStyle(.secondary)
                Button(tr("Apply startup preference")) { editor.onApplyLogin?() }
            }
            SettingsFieldOutcome(editor: editor, key: "launchAtLogin")
            LabeledContent(tr("Activity history")) {
                Button(tr("Open Activity…"), action: onOpenActivity)
                    .help(tr("Search, export or delete local activity"))
            }
        } footer: {
            Text(tr("Activity stays on this Mac for 14 days; it never holds prompts, code or transcripts."))
        }
        Section {
            ForEach(Self.categories, id: \.self) { category in
                Toggle(tr(category.title), isOn: Binding(get: { editor.draft.notificationCategories?.contains(category) ?? false },
                    set: { editor.setNotification(category, enabled: $0) }))
                    .help(tr("Send a local notification for ") + tr(category.title).lowercased())
                    .accessibilityLabel(tr(category.title))
                    .accessibilityIdentifier("camlid.settings.notification." + category.rawValue)
            }
            if !(editor.draft.notificationCategories ?? []).isEmpty, permissionNeedsAction {
                HStack(alignment: .firstTextBaseline) {
                    PermissionStatusLabel(status: editor.notificationPermission)
                        .accessibilityIdentifier("camlid.permissions.notifications.status")
                    Spacer()
                    if ["notDetermined", "unavailable"].contains(editor.notificationPermission) {
                        Button(tr("Allow Notifications…")) { editor.onAuthorizeNotifications?() }
                            .accessibilityIdentifier("camlid.permissions.notifications.request")
                    } else {
                        Button(tr("Open System Settings…")) { editor.onOpenNotificationSettings?() }
                            .accessibilityLabel(tr("Open Notifications in System Settings"))
                            .accessibilityIdentifier("camlid.permissions.notifications.settings")
                    }
                }
            }
            if let error = editor.permissionSettingsError {
                CamLidStatusLabel(error, systemImage: "exclamationmark.triangle", tone: .warning)
            }
            SettingsFieldOutcome(editor: editor, key: "notificationCategories")
        } header: {
            Text(tr("Notifications"))
        }
        Section {
            Toggle(tr("Check for new releases once a day"), isOn: Binding(get: { editor.automaticUpdateChecks },
                set: { editor.setAutomaticUpdateChecks($0) }))
                .help(tr("Ask GitHub once a day whether a newer release exists"))
                .accessibilityLabel(tr("Check for new releases once a day"))
                .accessibilityIdentifier("camlid.settings.updateChecks")
        } header: {
            Text(tr("Updates"))
        } footer: {
            Text(tr("Off by default. When on, CamLid asks GitHub’s public releases API once a day, with no account, cookies or system profile. It only tells you that a newer release exists; it never downloads or installs anything."))
        }
        Section {
            Toggle(tr("Let AI agents use CamLid"), isOn: Binding(get: { editor.agentSkillPath != nil },
                set: { editor.onSetAgentSkill?($0) }))
                .help(tr("Write the CamLid skill file to ~/.agents/skills/camlid/SKILL.md"))
                .accessibilityLabel(tr("Let AI agents use CamLid"))
                .accessibilityIdentifier("camlid.settings.agentSkill")
            if let path = editor.agentSkillPath {
                Text(trf("Installed at %@", (path as NSString).abbreviatingWithTildeInPath))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
        } header: {
            Text(tr("AI agents"))
        } footer: {
            Text(tr("Off by default. When on, CamLid writes one file, ~/.agents/skills/camlid/SKILL.md, in your home folder, where AI agents on this Mac can read it. Turning it off removes that file unless you have changed it. CamLid never writes it at launch."))
        }
    }
}

private struct PermissionStatusLabel: View {
    let status: String
    var body: some View {
        switch status {
        case "granted", "authorized":
            CamLidStatusLabel(Text(tr("Allowed")), systemImage: "checkmark.circle", tone: .success)
        case "provisional":
            CamLidStatusLabel(Text(tr("Allowed — quiet delivery")), systemImage: "checkmark.circle", tone: .success)
        case "notGranted", "denied":
            CamLidStatusLabel(Text(tr("Not allowed")), systemImage: "lock.circle", tone: .warning)
        case "notDetermined":
            CamLidStatusLabel(Text(tr("Not requested")), systemImage: "questionmark.circle")
        case "requesting":
            CamLidStatusLabel(Text(tr("Waiting for macOS approval")), systemImage: "clock")
        case "unavailable":
            CamLidStatusLabel(Text(tr("Unavailable in this app host")), systemImage: "exclamationmark.circle", tone: .warning)
        default:
            CamLidStatusLabel(Text(tr("Unknown")), systemImage: "questionmark.circle")
        }
    }
}

private struct SettingsAgentsPane: View {
    @ObservedObject var editor: SettingsEditor
    @State private var showsOthers = false
    private var orderedBadges: [AgentBadgeState] {
        AgentBadgeState.providers.map { provider in
            editor.badges.first { $0.provider == provider }
                ?? AgentBadgeState(provider: provider, enabled: editor.draft.parsedAdapters().contains(provider), tasks: [])
        }.sortedForAgentDisplay(detectedFirst: true)
    }
    /// Agents that are selected or installed here; the rest (not installed, or not supported yet) sit under "Other agents".
    private func isRelevant(_ state: AgentBadgeState) -> Bool {
        editor.draft.parsedAdapters().contains(state.provider) || state.cliDetected == true || state.appDetected == true
    }
    private var supported: [AgentBadgeState] { orderedBadges.filter(isRelevant) }
    private var others: [AgentBadgeState] { orderedBadges.filter { !isRelevant($0) } }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                badges(supported)
                // The all-or-none action shares the "Other agents" row; the expanded list keeps the full width below it.
                if !others.isEmpty {
                    DisclosureGroup(trf("Other agents (%lld)", others.count), isExpanded: $showsOthers) { badges(others) }
                        .disclosureGroupStyle(RowDisclosureStyle(trailing: AnyView(allProvidersButton)))
                        .help(tr("Not installed on this Mac, or not supported yet"))
                } else {
                    HStack { Spacer(); allProvidersButton }
                }
                ForEach(orderedBadges) { state in
                    SettingsFieldOutcome(editor: editor, key: "provider:" + state.provider)
                }
            }
        } header: {
            Text(tr("Agents that may delay sleep"))
        }
        Section {
            BadgeFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(MusicSource.listedSources(installed: MusicSource.installed).sorted { $0.chipTitle < $1.chipTitle }, id: \.self) { source in
                    MusicSourceChip(source: source, enabled: editor.watchedMusic.contains(source)) {
                        editor.setMusicSource(source, $0)
                    }
                }
                AnyAudioChip(enabled: editor.anyAudioHold) { editor.setAnyAudioHold($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text(tr("Music that may delay sleep"))
        }
        WatchedProgramsSection(editor: editor)
    }

    private var allProvidersButton: some View {
        Button(editor.allProvidersEnabled ? tr("Disable All") : tr("Enable All")) {
            editor.allProvidersEnabled ? editor.disableAllProviders() : editor.enableAllProviders()
        }
        .disabled(editor.selectableProviders.isEmpty)
        .help(editor.allProvidersEnabled ? tr("Ignore every agent for sleep decisions") : tr("Include all agents in sleep decisions"))
        .accessibilityIdentifier("camlid.agents.enableAll")
    }

    private func badges(_ states: [AgentBadgeState]) -> some View {
        BadgeFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(states) { state in
                SettingsAgentBadge(state: state, enabled: editor.draft.parsedAdapters().contains(state.provider), showsCLIInstallation: true) {
                    editor.setProvider(state.provider, enabled: $0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Programs that keep an Auto session awake while they run; the add form opens in a sheet.
private struct WatchedProgramsSection: View {
    @ObservedObject var editor: SettingsEditor
    @State private var adding = false
    private var rules: [LifetimeRule] { editor.draft.lifetimeRules ?? [] }

    var body: some View {
        Section {
            ForEach(rules) { rule in
                HStack {
                    Toggle(isOn: Binding(
                        get: { rule.enabled },
                        set: { enabled in
                            var updated = rules
                            guard let index = updated.firstIndex(where: { $0.id == rule.id }) else { return }
                            updated[index].enabled = enabled
                            editor.setLifetimeRules(updated)
                        })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.label)
                            Text(rule.selectorValue).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .accessibilityIdentifier("camlid.settings.lifetime.enabled." + rule.id.uuidString)
                    Button(tr("Remove")) { editor.setLifetimeRules(rules.filter { $0.id != rule.id }) }
                        .accessibilityIdentifier("camlid.settings.lifetime.remove." + rule.id.uuidString)
                }
            }
            HStack {
                Text(rules.isEmpty ? tr("None") : trf("%lld of %lld", rules.count, LifetimeRule.maximumRules))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(tr("Add Program…")) { adding = true }
                    .disabled(rules.count >= LifetimeRule.maximumRules)
                    .help(tr("Keep an Auto session awake while a program runs"))
                    .accessibilityIdentifier("camlid.settings.lifetime.add")
            }
            SettingsFieldOutcome(editor: editor, key: "lifetimeRules")
        } header: {
            Text(tr("Watched programs"))
        } footer: {
            Text(tr("A watched program keeps an Auto session awake while it runs; it doesn’t start a session."))
        }
        .sheet(isPresented: $adding) { AddWatchedProgramSheet(editor: editor, isPresented: $adding) }
    }
}

private struct AddWatchedProgramSheet: View {
    @ObservedObject var editor: SettingsEditor
    @Binding var isPresented: Bool
    @State private var selectorKind: LifetimeSelectorKind = .exactExecutablePath
    @State private var selectorValue = ""
    @State private var label = ""
    @State private var error: String?

    private var rules: [LifetimeRule] { editor.draft.lifetimeRules ?? [] }
    private var selectorTitle: String {
        selectorKind == .exactExecutablePath ? tr("Executable path") : tr("App bundle ID")
    }
    private var selectorPlaceholder: String {
        selectorKind == .exactExecutablePath ? tr("Path to an installed executable") : "com.example.app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Add a watched program")).font(.headline)
            Form {
                Picker(tr("Selection type"), selection: $selectorKind) {
                    Text(tr("Executable path")).tag(LifetimeSelectorKind.exactExecutablePath)
                    Text(tr("App bundle ID")).tag(LifetimeSelectorKind.applicationBundleID)
                }
                .accessibilityIdentifier("camlid.settings.lifetime.selectorKind")
                .onChange(of: selectorKind) { _, _ in error = nil }
                LabeledContent(selectorTitle) {
                    HStack(spacing: 8) {
                        TextField(selectorPlaceholder, text: $selectorValue)
                            .labelsHidden().textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("camlid.settings.lifetime.selectorValue")
                        Button(tr("Choose…")) { chooseProgram() }
                            .help(selectorKind == .exactExecutablePath ? tr("Choose an installed executable") : tr("Choose an installed app"))
                    }
                }
                LabeledContent(tr("Label")) {
                    TextField(tr("Name for this program"), text: $label)
                        .labelsHidden().textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("camlid.settings.lifetime.label")
                }
            }
            if let error {
                CamLidStatusLabel(error, systemImage: "exclamationmark.circle", tone: .danger, font: .caption)
                    .accessibilityIdentifier("camlid.settings.lifetime.error")
            }
            HStack {
                Spacer()
                Button(tr("Cancel"), role: .cancel) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(tr("Add")) { addRule() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectorValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func chooseProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if selectorKind == .applicationBundleID {
            panel.allowedContentTypes = [.application]
            panel.message = tr("Choose an application to watch.")
        } else {
            panel.message = tr("Choose an executable to watch.")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if selectorKind == .applicationBundleID {
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
                error = tr("That app doesn’t have a bundle identifier.")
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
        guard rules.count < LifetimeRule.maximumRules else { error = tr("The limit is 20 rules."); return }
        if selectorKind == .exactExecutablePath {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: value, isDirectory: &isDirectory), !isDirectory.boolValue,
                  FileManager.default.isExecutableFile(atPath: value) else {
                error = tr("Choose an installed executable file."); return
            }
        } else {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value),
                  Bundle(url: app)?.bundleIdentifier == value else {
                error = tr("Choose an installed app bundle ID."); return
            }
        }
        do {
            let rule = try LifetimeRule(selectorKind: selectorKind, selectorValue: value, label: ruleLabel)
            var updated = rules
            updated.append(rule)
            editor.setLifetimeRules(updated)
            guard editor.fieldMessages["lifetimeRules"] == nil else { error = editor.fieldMessages["lifetimeRules"].map(Localization.display); return }
            isPresented = false
        } catch {
            self.error = tr("Use an exact normalized path or installed bundle ID, with a label of at most 80 characters.")
        }
    }
}

private struct SettingsClosedLidSection: View {
    @ObservedObject var editor: SettingsEditor
    @State private var confirmingUntested = false
    @State private var showsDetails = false

    private var systemText: String { "\(editor.systemModel), macOS \(editor.systemBuild)" }
    private var testedText: String {
        // Each mode is tested separately (ADR 0003).
        if editor.draft.powerMode == .strict { return editor.strictTested ? tr("Tested") : tr("Not tested") }
        if editor.closedLidPermit.hasPrefix("qualified:") { return tr("Tested") }
        return editor.closedLidPermit == "untestedAcknowledged" ? tr("Untested — allowed") : tr("Not tested")
    }


    var body: some View {
        Section {
            // The one status line; details below on request.
            PreviewBuildNotice(text: editor.capabilityText.isEmpty ? nil : editor.capabilityText)
            // Helper actions sit up front only when something needs doing; otherwise they live under Details.
            // The helper's actions sit in one place for every state: install, reinstall and remove.
            helperButtons
            ForEach(editor.keepAwakeApps.filter(\.resetsSleepSetting), id: \.self) { app in
                Label(trf("%@ resets the sleep setting and will interrupt closed lid. Quit %@ or remove its helper.", app.name, app.name),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let others = editor.keepAwakeApps.filter { !$0.resetsSleepSetting }.map(\.name)
            if !others.isEmpty {
                Label(trf("Also keeping the Mac awake: %@.", others.joined(separator: ", ")), systemImage: "info.circle")
                    .font(.caption)
                    .help(tr("They won’t stop closed lid, but your Mac may stay awake after CamLid finishes."))
            }
            Toggle(tr("Keep awake with the lid closed"), isOn: Binding(get: { editor.draft.closedLidOptIn }, set: editor.setClosedLidOptIn))
                .disabled(!ClosedLidOffer.optionEnabled(helperState: editor.helperState, optionOn: editor.draft.closedLidOptIn))
                .help(tr("Lets sessions keep this Mac awake with the lid closed, within the safety limits"))
                .accessibilityLabel(Text(tr("Keep awake with the lid closed")))
                .accessibilityIdentifier("camlid.settings.closedLid.enabled")
            ClosedLidSuggestion(editor: editor)
            Text(tr("With the lid open, a session keeps this Mac awake whether or not this is on. This option also keeps it awake with the lid closed, which needs the helper."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsFieldOutcome(editor: editor, key: "closedLidOptIn")
            VStack(alignment: .leading, spacing: 4) {
                Picker(tr("Mode"), selection: Binding(get: { editor.draft.powerMode }, set: editor.setPowerMode)) {
                    Text(tr(PowerMode.standard.title)).tag(PowerMode.standard)
                    Text(tr(PowerMode.strict.title)).tag(PowerMode.strict)
                        .selectionDisabled(!editor.strictTested && editor.draft.powerMode != .strict)
                }
                .help(tr(editor.draft.powerMode.disclosure))
                .accessibilityLabel(Text(tr("Closed-lid mode")))
                .accessibilityIdentifier("camlid.settings.closedLid.mode")
                Text(tr(editor.draft.powerMode.summary) + (editor.strictTested ? "" : tr(" Strict isn’t tested on this Mac.")))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsFieldOutcome(editor: editor, key: "powerMode")
            if editor.draft.powerMode == .standard, !editor.closedLidPermit.hasPrefix("qualified:") {
                Toggle(tr("Allow on this untested Mac"), isOn: Binding(
                    get: { editor.closedLidPermit == "untestedAcknowledged" },
                    set: { allow in
                        if allow { confirmingUntested = true } else { editor.onSetUntestedAcknowledgement?(false) }
                    }))
                    .help(tr("Closed lid has not been tested on this model and macOS build"))
                    .accessibilityIdentifier("camlid.settings.closedLid.allowUntested")
            }
            DisclosureGroup(tr("Details"), isExpanded: $showsDetails) {
                ValueRow(title: tr("This Mac"), value: systemText)
                ValueRow(title: tr("Testing"), value: testedText)
                ValueRow(title: "Helper", value: editor.helperBusy ? tr("Working…") : helperLabel)
                Text(Localization.display(editor.helperMessage))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disclosureGroupStyle(RowDisclosureStyle())
        }
        .alert(tr("Allow closed lid on an untested Mac?"), isPresented: $confirmingUntested) {
            Button(tr("Allow")) { editor.onSetUntestedAcknowledgement?(true) }
            Button(tr("Cancel"), role: .cancel) {}
        } message: {
            Text(trf("CamLid hasn’t been tested on %@. If something fails, this Mac may stay awake with the lid closed until the helper or its recovery job restores the sleep setting. This applies to this Mac and macOS build only; you can turn it off at any time.", systemText))
        }
    }

    private var helperButtons: some View { HelperButtons(editor: editor) }

    private var helperLabel: String {
        switch editor.helperState {
        case "installed": "Installed"
        case "notInstalled": tr("Not installed")
        case "unknown": tr("Not checked")
        default: tr("Needs attention")
        }
    }
}

/// Under the closed-lid toggle: the one next step, from the helper state (spec 027). Nothing shows when the option is on and the helper is ready.
private struct ClosedLidSuggestion: View {
    @ObservedObject var editor: SettingsEditor

    var body: some View {
        let offer = ClosedLidOffer.offer(helperState: editor.helperState, optionOn: editor.draft.closedLidOptIn,
                                         macAllowed: editor.closedLidAllowed)
        switch offer {
        case .installHelper, .reinstallHelper:
            Label(hint(for: offer), systemImage: editor.draft.closedLidOptIn ? "exclamationmark.triangle" : "info.circle")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("camlid.settings.closedLid.helperHint")
        case .turnOn:
            HStack {
                Label(tr("The helper is ready. Turn this on to keep the Mac awake with the lid closed."), systemImage: "checkmark.circle")
                    .font(.caption)
                Button(tr("Turn On")) { editor.setClosedLidOptIn(true) }
                    .accessibilityIdentifier("camlid.settings.closedLid.turnOn")
            }
        case .none, .openSettings:
            EmptyView()
        }
    }

    private func hint(for offer: ClosedLidOffer) -> String {
        let verb = offer == .reinstallHelper ? tr("reinstall") : tr("install")
        if editor.draft.closedLidOptIn {
            return trf("Closing the lid will sleep this Mac until you %@ the closed-lid helper below.", tr(verb))
        }
        let capitalized = offer == .reinstallHelper ? tr("Reinstall") : tr("Install")
        return trf("%@ the closed-lid helper below to turn this on.", tr(capitalized))
    }
}

/// Install, reinstall and remove the closed-lid helper. Each asks for an administrator password.
private struct HelperButtons: View {
    @ObservedObject var editor: SettingsEditor
    private var installed: Bool { ["installed", "installedNotLoaded", "needsReauthorization", "needsHelperUpdate", "helperIdentityMismatch", "partial"].contains(editor.helperState) }
    var body: some View {
        HStack {
            Button(installed ? tr("Reinstall helper…") : tr("Install helper…")) { editor.onInstallHelper?() }
                .disabled(editor.helperBusy)
                .help(tr("Asks for an administrator password once. Installing doesn’t start a session or change sleep settings."))
                .accessibilityIdentifier("camlid.settings.helper.install")
            if installed {
                Button(tr("Remove helper…")) { editor.onUninstallHelper?() }
                    .disabled(editor.helperBusy)
                    .help(tr("Restores the sleep setting and removes the helper"))
                    .accessibilityIdentifier("camlid.settings.helper.remove")
            }
            if editor.helperBusy { ProgressView().controlSize(.small) }
        }
    }
}

private struct SettingsSafetyPane: View {
    @ObservedObject var editor: SettingsEditor
    @Binding var isExpanded: Bool

    var body: some View {
        SettingsClosedLidSection(editor: editor)
        Section {
            Toggle(tr("Allow on battery"), isOn: Binding(get: { editor.batteryAllowed }, set: editor.setBatteryAllowed))
                .accessibilityLabel(Text(tr("Allow on battery")))
                .accessibilityIdentifier("camlid.settings.batteryMode")
                .help(tr("Off: sessions need the charger. On: sessions may run on battery within the limits below."))
            SettingsFieldOutcome(editor: editor, key: "batteryAllowed")
            if editor.batteryAllowed {
                SettingsNumberField(editor: editor, title: tr("Stop below battery level"), field: .batteryFloor, unit: "%")
                SettingsNumberField(editor: editor, title: tr("Battery time limit"), field: .batteryCap, unit: "minutes")
            }
        } header: {
            Text(tr("Battery"))
        } footer: {
            if editor.batteryAllowed {
                Text(tr("Counted from the start of the session; plugging in doesn’t extend it."))
            }
        }
        Section {
            SettingsNumberField(editor: editor, title: tr("Session time limit"), field: .runCap, unit: "minutes")
        } header: {
            Text(tr("Limits"))
        } footer: {
            Text(tr("Overheating, low battery and the time limit stop every session. Infinite Timed ignores the time limit only on the charger."))
        }
        Section {
            DisclosureGroup(tr("Advanced"), isExpanded: $isExpanded) {
                SettingsNumberField(editor: editor, title: tr("Start on battery at or above"), field: .batteryEntry, unit: "%")
                VStack(alignment: .leading, spacing: 4) {
                    SettingsNumberField(editor: editor, title: tr("Retain waiting sessions"), field: .waitRetention, unit: "minutes")
                    Text(tr("Waiting never keeps the Mac awake."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(tr("Stop if CPU stays busy"), isOn: Binding(get: { editor.draft.cpuStopEnabled }, set: editor.setCPUStop))
                    .accessibilityLabel(Text(tr("Stop if CPU stays busy")))
                    .accessibilityIdentifier("camlid.settings.cpuStopEnabled")
                    .help(tr("Stops a session at 90% CPU for 2 minutes"))
                SettingsFieldOutcome(editor: editor, key: "cpuStopEnabled")
            }.disclosureGroupStyle(RowDisclosureStyle()).help(tr("Battery start level, waiting and CPU preferences"))
        }
    }
}

private struct SettingsFieldOutcome: View {
    @ObservedObject var editor: SettingsEditor
    let key: String
    var body: some View {
        if let message = editor.fieldMessages[key] {
            let shown = Localization.display(message)
            VStack(alignment: .leading, spacing: 4) {
                CamLidStatusLabel(shown,
                                  systemImage: message == "Applying…" ? "clock" : "exclamationmark.circle",
                                  tone: message == "Applying…" ? .neutral : .danger,
                                  help: shown)
                if message != "Applying…" {
                    HStack {
                        if message == "Changed elsewhere" {
                            Button(tr("Use current")) { editor.useCurrent(key: key) }
                            Button(tr("Apply my value")) { editor.applyMyValue(key: key) }
                        } else { Button(tr("Retry")) { editor.retry(key: key) } }
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
                ForEach(choices, id: \.self) { value in
                    Text(NumericChoice.label(value, field: field)).tag(value)
                }
                // A saved default above the session limit stays shown until it is changed; its error below says why.
                if !editor.customFields.contains(field), let saved = NumericChoice.parse(editor.numbers[field] ?? ""), !choices.contains(saved) {
                    Text(NumericChoice.label(saved, field: field)).tag(saved)
                }
                Text(tr("Custom…")).tag(-1)
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
    /// Default Timed choices stop at the session limit; the other fields offer their presets.
    private var choices: [Int] {
        field == .timer ? NumericChoice.timerChoices(upTo: editor.draft.runCapMinutes) : NumericChoice.presets(field)
    }
    private var helpText: String {
        switch field {
        case .timer: tr("Default for new Timed sessions; Infinite bypasses time limits only on charger power. Battery and thermal limits always apply.")
        case .completionDelay: tr("Default delay after selected work ends in a new Auto session")
        case .waitRetention: tr("How long a waiting task may hold an Auto session")
        case .batteryFloor: tr("End the session below this battery level")
        case .batteryEntry: tr("20–80 percent, strictly above the stop level; checked when starting on battery")
        case .batteryCap: tr("15–240 minutes, bounded by the session limit; applies even to Infinite")
        case .runCap: tr("Time limit for Auto and finite timers; Infinite bypasses this limit only on charger power")
        case .adapters: tr("Agents included in sleep decisions")
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
        view.placeholderString = trf("Custom %@", unit)
        Task { @MainActor [weak view] in
            guard let view, let window = view.window, window.isKeyWindow else { return }
            window.makeFirstResponder(view)
        }
        return view
    }
    func updateNSView(_ view: NSTextField, context: Context) {
        context.coordinator.parent = self
        let text = editor.numbers[field] ?? ""
        // numbers mirrors every keystroke, so a difference here is an outside change (e.g. the CLI), even while focused.
        if view.stringValue != text { view.stringValue = text }
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

/// A label/value row VoiceOver reads as both ("This Mac: Mac17,3, macOS 26A434"). In a Form these rows are exposed
/// without a value attribute (combined or explicit), so the value is part of the label.
private struct ValueRow: View {
    let title: String
    let value: String
    var body: some View {
        LabeledContent(title) { Text(value) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(title): \(value)"))
    }
}
