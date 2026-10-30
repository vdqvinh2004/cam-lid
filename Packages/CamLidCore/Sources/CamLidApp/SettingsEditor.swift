import Foundation
import SwiftUI
import CamLidCore

public enum SettingsSection: String, Codable, CaseIterable, Sendable {
    case defaults, agents, lifetime, safety, permissions, activity
    public var title: String { self == .lifetime ? "Watched Programs" : rawValue.capitalized }
    public var symbol: String {
        switch self { case .defaults: "slider.horizontal.3"; case .agents: "terminal"; case .lifetime: "eye"; case .safety: "shield"; case .permissions: "lock.shield"; case .activity: "clock" }
    }
}

public enum SettingsCommitResult: Codable, Sendable {
    case saved(revision: Int)
    case conflict(configuration: Configuration, revision: Int)
    case failed(String)
    case unconfirmed(String)
}

/// Individual field edits validate and commit with revision-aware patches.
/// Failed or conflicting input remains visible until explicitly resolved.
@MainActor
public final class SettingsEditor: ObservableObject {
    @Published public var draft: SettingsDraft
    @Published public var numbers: [SettingsFieldError.Field: String]
    @Published public var section: SettingsSection
    @Published public private(set) var message: String?
    @Published public private(set) var conflict: Bool = false
    public private(set) var revision: Int
    private var persisted: Configuration
    private var commitPatch: ((ConfigPatch, Int) -> SettingsCommitResult)?
    private var asyncCommitPatch: (@MainActor (ConfigPatch, Int) async -> SettingsCommitResult)?
    private var asyncWorker: Task<Void, Never>?
    private var queuedKeys: [String] = []
    private var activeKey: String?
    private var overrideKeys: Set<String> = []
    private var editSequences: [String: Int] = [:]
    @Published public private(set) var pendingKeys: Set<String> = []
    @Published public var installationPending = false
    public var hasPendingWrites: Bool { installationPending || asyncWorker != nil || !pendingKeys.isEmpty }
    private var edits: [String: (base: Configuration, build: (Configuration) -> ConfigPatch)] = [:]
    private var customTasks: [SettingsFieldError.Field: Task<Void, Never>] = [:]
    private var numberBases: [SettingsFieldError.Field: Configuration] = [:]
    private var composingNumbers: Set<SettingsFieldError.Field> = []
    private var editingNumbers: Set<SettingsFieldError.Field> = []
    @Published public var customFields: Set<SettingsFieldError.Field> = []
    @Published public private(set) var fieldMessages: [String: String] = [:]
    @Published public var badges: [AgentBadgeState] = []
    @Published public var protection: ProtectionReadiness?
    @Published public var loginState = "notRegistered"
    @Published public var loginMessage = "Login registration has not been checked."
    @Published public var helperState = "unknown"
    @Published public var helperMessage = "Helper status has not been checked."
    @Published public var helperBusy = false
    public var onInstallHelper: (() -> Void)?
    public var onUninstallHelper: (() -> Void)?
    @Published public var notificationPermission = "notDetermined"
    @Published public var accessibilityPermission = "unavailable"
    @Published public var permissionSettingsError: String?
    public var onAuthorizeAccessibility: (() -> Void)?
    public var onOpenAccessibilitySettings: (() -> Void)?
    public var onOpenNotificationSettings: (() -> Void)?
    public var onRefreshPermissions: (() -> Void)?
    public var onAuthorizeNotifications: (() -> Void)?
    public var onApplyLogin: (() -> Void)?
    private var original: SettingsDraft
    private var originalNumbers: [SettingsFieldError.Field: String]
    private var latest: (Configuration, Int)?

    public init(configuration: Configuration, revision: Int,
        section: SettingsSection = .agents) {
        let initial = SettingsDraft(configuration: configuration)
        persisted = configuration
        draft = initial; original = initial
        customFields = Set(Self.numericFields.filter { !NumericChoice.presets($0).contains(Self.numberValue(initial, field: $0)) })
        numbers = Self.numberValues(initial); originalNumbers = Self.numberValues(initial)
        self.revision = revision; self.section = section
    }

    public var isDirty: Bool { hasPendingWrites || !edits.isEmpty || !editingNumbers.isEmpty || draft != original || numbers != originalNumbers }
    public var errors: [SettingsFieldError] {
        var errors: [SettingsFieldError] = []
        var candidate = draft
        for field in Self.numericFields {
            guard let value = NumericChoice.parse(numbers[field] ?? "") else {
                errors.append(SettingsFieldError(field: field, message: "Enter a whole number.")); continue
            }
            Self.assign(value, field: field, to: &candidate)
        }
        return errors + candidate.validate().filter { error in !errors.contains { $0.field == error.field } }
    }

    @discardableResult
    public func save(using commit: (Configuration, Int) -> SettingsCommitResult) -> Bool {
        guard errors.isEmpty else { message = "Correct the highlighted fields before saving."; return false }
        var candidate = draft
        for field in Self.numericFields { Self.assign(NumericChoice.parse(numbers[field] ?? "")!, field: field, to: &candidate) }
        do {
            let configuration = try candidate.makeConfiguration()
            switch commit(configuration, revision) {
            case .saved(let next):
                draft = candidate; original = candidate
                numbers = Self.numberValues(candidate); originalNumbers = numbers
                revision = next; conflict = false; latest = nil; message = "Changes saved."
                return true
            case .conflict(let current, let next):
                latest = (current, next); conflict = true
                message = "Settings changed elsewhere. Your draft is preserved. Reload current settings before saving."
                return false
            case .failed(let reason), .unconfirmed(let reason): message = reason; return false
            }
        } catch { message = "Settings could not be validated. Your draft is preserved."; return false }
    }

    public func reloadAfterConflict() {
        guard let (configuration, next) = latest else { return }
        draft = SettingsDraft(configuration: configuration); original = draft
        numbers = Self.numberValues(draft); originalNumbers = numbers
        revision = next; conflict = false; latest = nil; message = "Current settings loaded."
    }
    public func discard() {
        for task in customTasks.values { task.cancel() }
        asyncWorker?.cancel(); queuedKeys.removeAll(); overrideKeys.removeAll()
        for key in editSequences.keys { editSequences[key, default: 0] += 1 }
        customTasks.removeAll(); numberBases.removeAll(); composingNumbers.removeAll(); editingNumbers.removeAll(); edits.removeAll(); fieldMessages.removeAll()
        draft = original; numbers = originalNumbers
        message = installationPending ? "Outcome unconfirmed — a write already started and may apply later." : nil
        conflict = false
    }

    public static func key(_ field: SettingsFieldError.Field) -> String {
        switch field { case .timer: "timerMinutes"; case .completionDelay: "completionDelayMinutes"; case .waitRetention: "waitRetentionMinutes";
        case .batteryFloor: "batteryFloorPercent"; case .batteryEntry: "batteryEntryPercent"; case .batteryCap: "batteryCapMinutes"; case .runCap: "runCapMinutes"; case .adapters: "adapterEnrollment" }
    }
    private static func numberValue(_ draft: SettingsDraft, field: SettingsFieldError.Field) -> Int {
        switch field { case .timer: draft.defaultTimerMinutes; case .completionDelay: draft.completionDelayMinutes; case .waitRetention: draft.waitRetentionMinutes;
        case .batteryFloor: draft.batteryFloorPercent; case .batteryEntry: draft.batteryEntryPercent; case .batteryCap: draft.batteryCapMinutes; case .runCap: draft.runCapMinutes; case .adapters: 0 }
    }
    public func configureAutosave(_ commit: @escaping (ConfigPatch, Int) -> SettingsCommitResult) { commitPatch = commit }
    public func configureAsyncAutosave(_ commit: @escaping @MainActor (ConfigPatch, Int) async -> SettingsCommitResult) { asyncCommitPatch = commit }
    public func receive(configuration: Configuration, revision next: Int) {
        guard next > revision else { return }
        persisted = configuration; revision = next
        for key in Array(edits.keys) where fieldMessages[key]?.hasPrefix("Outcome unconfirmed") == true {
            guard let edit = edits[key], let desired = try? persisted.applying(edit.build(persisted)),
                  value(desired, key: key) == value(persisted, key: key) else { continue }
            clearApplied(key); message = "Applied"
        }
        reconcile()
        for field in Self.numericFields where !editingNumbers.contains(field) {
            if !NumericChoice.presets(field).contains(Self.numberValue(original, field: field)) { customFields.insert(field) }
        }
    }
    public func installationFinished(success: Bool) {
        installationPending = false
        guard !success else { return }
        for key in fieldMessages.keys where fieldMessages[key]?.hasPrefix("Outcome unconfirmed") == true {
            fieldMessages[key] = "Not applied — storage could not finish the write. Retry the edit."
        }
        if message?.hasPrefix("Outcome unconfirmed") == true {
            message = "Not applied — storage could not finish the write. Retry the edit."
        }
    }
    public func chooseCustom(_ field: SettingsFieldError.Field) { customFields.insert(field) }
    public func selectPreset(_ value: Int, field: SettingsFieldError.Field) {
        customTasks.removeValue(forKey: field)?.cancel(); customFields.remove(field)
        if numberBases[field] == nil { numberBases[field] = persisted }
        numbers[field] = String(value); editingNumbers.insert(field); commitNumber(field)
    }
    public func editNumber(_ text: String, field: SettingsFieldError.Field, composing: Bool = false) {
        editSequences[Self.key(field), default: 0] += 1
        if numberBases[field] == nil { numberBases[field] = persisted }
        numbers[field] = text; editingNumbers.insert(field)
        message = "Editing…"
        customTasks.removeValue(forKey: field)?.cancel()
        if composing { composingNumbers.insert(field); return }
        composingNumbers.remove(field)
        customTasks[field] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.commitNumber(field)
        }
    }
    public func commitNumber(_ field: SettingsFieldError.Field) {
        customTasks.removeValue(forKey: field)?.cancel()
        guard !composingNumbers.contains(field), editingNumbers.contains(field) else { return }
        guard let value = NumericChoice.parse(numbers[field] ?? ""),
              !errors.contains(where: { $0.field == field }) else {
            message = "Not applied — correct the highlighted input."
            return
        }
        apply(key: Self.key(field)) { _ in
            var patch = ConfigPatch()
            switch field { case .timer: patch.timerMinutes = value
            case .completionDelay: patch.completionDelayMinutes = value
            case .waitRetention: patch.waitRetentionMinutes = value
            case .batteryFloor: patch.batteryFloorPercent = value
            case .batteryEntry: patch.batteryEntryPercent = value
            case .batteryCap: patch.batteryCapMinutes = value
            case .runCap: patch.runCapMinutes = value
            case .adapters: break }
            return patch
        }
    }
    public func cancelNumber(_ field: SettingsFieldError.Field) {
        editSequences[Self.key(field), default: 0] += 1
        if activeKey == Self.key(field) { asyncWorker?.cancel() }
        queuedKeys.removeAll { $0 == Self.key(field) }
        customTasks.removeValue(forKey: field)?.cancel(); composingNumbers.remove(field); numberBases.removeValue(forKey: field); editingNumbers.remove(field)
        edits.removeValue(forKey: Self.key(field)); fieldMessages.removeValue(forKey: Self.key(field))
        numbers[field] = originalNumbers[field]; conflict = fieldMessages.values.contains("Changed elsewhere")
    }
    public func setMode(_ mode: RequestedMode) { draft.mode = mode; apply(key: "mode") { _ in var p = ConfigPatch(); p.mode = mode; return p } }
    public var batterySessionsAllowed: Bool {
        get { draft.batteryModeAllowed }
        set { setBatteryModeAllowed(newValue) }
    }
    public func setBatteryModeAllowed(_ enabled: Bool) {
        draft.batteryModeAllowed = enabled
        apply(key: "batteryModeAllowed") { _ in var patch = ConfigPatch(); patch.batteryModeAllowed = enabled; return patch }
    }
    public func setChargingOnly(_ enabled: Bool) { draft.chargingOnly = enabled; apply(key: "chargingOnly") { _ in var p = ConfigPatch(); p.chargingOnly = enabled; return p } }
    public func setLaunchAtLogin(_ enabled: Bool) { draft.launchAtLogin = enabled; apply(key: "launchAtLogin") { _ in var p = ConfigPatch(); p.launchAtLogin = enabled; return p } }
    public func setNotification(_ category: NotificationCategory, enabled: Bool) {
        var values = draft.notificationCategories ?? []
        values.removeAll { $0 == category }; if enabled { values.append(category) }
        draft.notificationCategories = values
        apply(key: "notificationCategories") { config in
            var p = ConfigPatch(); var values = config.notificationCategories ?? []
            values.removeAll { $0 == category }; if enabled { values.append(category) }
            p.notificationCategories = values; return p
        }
    }
    public func setAllowDisplaySleep(_ enabled: Bool) { draft.allowDisplaySleep = enabled; apply(key: "allowDisplaySleep") { _ in var p = ConfigPatch(); p.allowDisplaySleep = enabled; return p } }
    public func setCPUStop(_ enabled: Bool) { draft.cpuStopEnabled = enabled; apply(key: "cpuStopEnabled") { _ in var p = ConfigPatch(); p.cpuStopEnabled = enabled; return p } }
    public func setProvider(_ provider: String, enabled: Bool) {
        var selected = draft.parsedAdapters().filter { $0 != provider }; if enabled { selected.append(provider) }
        draft.adapterEnrollmentText = selected.joined(separator: "\n")
        apply(key: "provider:" + provider) { config in
            var patch = ConfigPatch(); var values = config.adapterEnrollment.filter { $0 != provider }
            if enabled { values.append(provider) }; patch.adapterEnrollment = values; return patch
        }
    }
    public func setLifetimeRules(_ rules: [LifetimeRule]) {
        do { try LifetimeRule.validateCollection(rules) }
        catch { fieldMessages["lifetimeRules"] = "Rules need unique exact selectors and at most 20 entries."; message = fieldMessages["lifetimeRules"]; return }
        draft.lifetimeRules = rules
        fieldMessages.removeValue(forKey: "lifetimeRules")
        apply(key: "lifetimeRules") { _ in var patch = ConfigPatch(); patch.lifetimeRules = rules; return patch }
    }
    /// Providers that are detected and have a working detector. Unsupported or
    /// absent agents stay visible in Settings but cannot be enabled.
    var selectableProviders: [String] {
        AgentBadgeState.providers.filter { provider in
            guard let badge = badges.first(where: { $0.provider == provider }) else { return false }
            return badge.settingsUnavailableReason == nil
        }
    }
    public func enableAllProviders() {
        for provider in selectableProviders where !draft.parsedAdapters().contains(provider) {
            setProvider(provider, enabled: true)
        }
    }
    private func value(_ config: Configuration, key: String) -> String {
        if key.hasPrefix("provider:") { return String(config.adapterEnrollment.contains(String(key.dropFirst(9)))) }
        if key == "allowDisplaySleep" { return String(config.displaySleepAllowed) }
        if key == "lifetimeRules" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            return String(decoding: (try? encoder.encode(config.lifetimeRules ?? [])) ?? Data(), as: UTF8.self)
        }
        let object = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(config))) as? [String: Any]
        return String(describing: object?[key] ?? "")
    }
    private func apply(key: String, build: @escaping (Configuration) -> ConfigPatch) {
        if let pending = edits[key] { edits[key] = (pending.base, build) }
        else {
            let field = Self.numericFields.first { Self.key($0) == key }
            edits[key] = (field.flatMap { numberBases[$0] } ?? persisted, build)
        }
        editSequences[key, default: 0] += 1
        attempt(key)
    }
    private func attempt(_ key: String, overriding: Bool = false) {
        if asyncCommitPatch != nil {
            if overriding { overrideKeys.insert(key) }
            if !queuedKeys.contains(key) { queuedKeys.append(key) }
            pendingKeys.insert(key)
            startAsyncWorker()
            return
        }
        guard let edit = edits[key], let commitPatch else { return }
        let patch = edit.build(persisted)
        let desired = try? persisted.applying(patch)
        if !overriding, value(edit.base, key: key) != value(persisted, key: key),
           desired.map({ value($0, key: key) != value(persisted, key: key) }) == true {
            fieldMessages[key] = "Changed elsewhere"; conflict = true
            message = "Changed elsewhere. Choose which value to keep."
            return
        }
        switch commitPatch(patch, revision) {
        case .saved(let next):
            if let saved = try? persisted.applying(patch) {
                persisted = saved; revision = next; edits.removeValue(forKey: key); fieldMessages.removeValue(forKey: key)
                if let field = Self.numericFields.first(where: { Self.key($0) == key }) { editingNumbers.remove(field); numberBases.removeValue(forKey: field) }
                reconcile(); message = "Applied"; conflict = fieldMessages.values.contains("Changed elsewhere")
            }
        case .failed(let reason), .unconfirmed(let reason): fieldMessages[key] = reason; message = reason
        case .conflict(let current, let next):
            let unchanged = value(edit.base, key: key) == value(current, key: key)
            let desired = try? current.applying(edit.build(current))
            let alreadyApplied = desired.map { value($0, key: key) == value(current, key: key) } ?? false
            persisted = current; revision = next
            if alreadyApplied {
                edits.removeValue(forKey: key); fieldMessages.removeValue(forKey: key)
                if let field = Self.numericFields.first(where: { Self.key($0) == key }) { editingNumbers.remove(field); numberBases.removeValue(forKey: field) }
                reconcile(); message = "Applied"; conflict = fieldMessages.values.contains("Changed elsewhere")
            } else if unchanged || overriding {
                // Exactly one retry; if another writer intervenes, retain conflict.
                let retry = edit.build(current)
                switch commitPatch(retry, next) {
                case .saved(let final):
                    persisted = try! current.applying(retry); revision = final; edits.removeValue(forKey: key); fieldMessages.removeValue(forKey: key)
                    if let field = Self.numericFields.first(where: { Self.key($0) == key }) { editingNumbers.remove(field); numberBases.removeValue(forKey: field) }
                    reconcile(); message = "Applied"; conflict = fieldMessages.values.contains("Changed elsewhere")
                case .failed(let reason), .unconfirmed(let reason): fieldMessages[key] = reason; message = reason
                case .conflict(let newer, let final): persisted = newer; revision = final; fieldMessages[key] = "Changed elsewhere"; conflict = true; message = "Changed elsewhere. Choose which value to keep."
                }
            } else { fieldMessages[key] = "Changed elsewhere"; conflict = true; message = "Changed elsewhere. Choose which value to keep." }
            reconcile()
        }
    }
    private func startAsyncWorker() {
        guard asyncWorker == nil, !queuedKeys.isEmpty else { return }
        asyncWorker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.queuedKeys.isEmpty {
                let key = self.queuedKeys.removeFirst()
                let override = self.overrideKeys.remove(key) != nil
                self.activeKey = key
                await self.attemptAsync(key, overriding: override)
                self.activeKey = nil
                if !self.queuedKeys.contains(key) { self.pendingKeys.remove(key) }
            }
            self.asyncWorker = nil
            self.pendingKeys = Set(self.queuedKeys)
            self.startAsyncWorker()
        }
    }

    private func attemptAsync(_ key: String, overriding: Bool) async {
        guard let edit = edits[key], let commit = asyncCommitPatch else { return }
        let sequence = editSequences[key, default: 0]
        let firstDesired = try? persisted.applying(edit.build(persisted))
        if !overriding, value(edit.base, key: key) != value(persisted, key: key),
           firstDesired.map({ value($0, key: key) != value(persisted, key: key) }) == true {
            markConflict(key); return
        }
        let indicator = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, self.editSequences[key] == sequence, self.pendingKeys.contains(key) else { return }
            self.fieldMessages[key] = "Applying…"; self.message = "Applying…"
        }
        defer { indicator.cancel() }
        for retry in 0...1 {
            let base = persisted
            let patch = edit.build(base)
            let result = await commit(patch, revision)
            guard !Task.isCancelled else { return }
            let isCurrent = editSequences[key] == sequence && edits[key] != nil
            switch result {
            case .saved(let next):
                guard let saved = try? base.applying(patch) else { return }
                if next > revision { persisted = saved; revision = next }
                if !isCurrent {
                    // An older successful edit may advance authority, never input.
                    if let newer = edits[key] { edits[key] = (persisted, newer.build) }
                    if let field = Self.numericFields.first(where: { Self.key($0) == key }), editingNumbers.contains(field) { numberBases[field] = persisted }
                    reconcile(); return
                }
                guard value(persisted, key: key) == value(saved, key: key) else { markConflict(key); reconcile(); return }
                clearApplied(key); reconcile(); message = "Applied"; return
            case .failed(let reason), .unconfirmed(let reason):
                guard isCurrent else { return }
                fieldMessages[key] = reason; message = reason; return
            case .conflict(let current, let next):
                if next > revision { persisted = current; revision = next }
                guard isCurrent else { reconcile(); return }
                let desired = try? persisted.applying(edit.build(persisted))
                if desired.map({ value($0, key: key) == value(persisted, key: key) }) == true {
                    clearApplied(key); reconcile(); message = "Applied"; return
                }
                let unchanged = value(edit.base, key: key) == value(persisted, key: key)
                guard retry == 0, unchanged || overriding else { markConflict(key); reconcile(); return }
            }
        }
    }
    private func markConflict(_ key: String) {
        fieldMessages[key] = "Changed elsewhere"; conflict = true
        message = "Changed elsewhere. Choose which value to keep."
    }
    private func clearApplied(_ key: String) {
        edits.removeValue(forKey: key); fieldMessages.removeValue(forKey: key)
        if let field = Self.numericFields.first(where: { Self.key($0) == key }) {
            editingNumbers.remove(field); numberBases.removeValue(forKey: field)
        }
        conflict = fieldMessages.values.contains("Changed elsewhere")
    }
    /// Close, Quit and update deferral share one bounded settlement condition.
    public func settle(timeout: Duration = .seconds(2)) async -> Bool {
        flush()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while hasPendingWrites, ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return false }
        }
        return !isDirty
    }

    public func applyMyValue(key: String) { attempt(key, overriding: true) }
    public func useCurrent(key: String) {
        editSequences[key, default: 0] += 1
        if activeKey == key { asyncWorker?.cancel() }
        queuedKeys.removeAll { $0 == key }
        edits.removeValue(forKey: key); fieldMessages.removeValue(forKey: key)
        if let field = Self.numericFields.first(where: { Self.key($0) == key }) { editingNumbers.remove(field); numberBases.removeValue(forKey: field) }
        reconcile(); conflict = fieldMessages.values.contains("Changed elsewhere")
        message = installationPending ? "Outcome unconfirmed — a write already started and may apply later." : nil
    }
    public func retry(key: String) { attempt(key) }
    public func flush() {
        for field in Self.numericFields where editingNumbers.contains(field) && !pendingKeys.contains(Self.key(field)) { commitNumber(field) }
    }
    private func reconcile() {
        original = SettingsDraft(configuration: persisted); originalNumbers = Self.numberValues(original)
        let oldDraft = draft; let pending = Set(edits.keys)
        draft = original
        if pending.contains("mode") { draft.mode = oldDraft.mode }
        if pending.contains("chargingOnly") { draft.chargingOnly = oldDraft.chargingOnly }
        if pending.contains("batteryModeAllowed") { draft.batteryModeAllowed = oldDraft.batteryModeAllowed }
        if pending.contains("allowDisplaySleep") { draft.allowDisplaySleep = oldDraft.allowDisplaySleep }
        if pending.contains("launchAtLogin") { draft.launchAtLogin = oldDraft.launchAtLogin }
        if pending.contains("notificationCategories") { draft.notificationCategories = oldDraft.notificationCategories }
        if pending.contains("cpuStopEnabled") { draft.cpuStopEnabled = oldDraft.cpuStopEnabled }
        for provider in AgentBadgeState.providers where pending.contains("provider:" + provider) {
            var selected = draft.parsedAdapters().filter { $0 != provider }
            if oldDraft.parsedAdapters().contains(provider) { selected.append(provider) }
            draft.adapterEnrollmentText = selected.joined(separator: "\n")
        }
        for field in Self.numericFields where !editingNumbers.contains(field) { numbers[field] = originalNumbers[field] }
    }

    private static let numericFields: [SettingsFieldError.Field] = [.timer, .completionDelay, .waitRetention, .batteryFloor, .batteryEntry, .batteryCap, .runCap]
    private static func numberValues(_ draft: SettingsDraft) -> [SettingsFieldError.Field: String] {
        [.timer: String(draft.defaultTimerMinutes), .completionDelay: String(draft.completionDelayMinutes), .waitRetention: String(draft.waitRetentionMinutes),
         .batteryFloor: String(draft.batteryFloorPercent), .batteryEntry: String(draft.batteryEntryPercent), .batteryCap: String(draft.batteryCapMinutes), .runCap: String(draft.runCapMinutes)]
    }
    private static func assign(_ value: Int, field: SettingsFieldError.Field, to draft: inout SettingsDraft) {
        switch field {
        case .timer: draft.timerMinutes = value
        case .completionDelay: draft.completionDelayMinutes = value
        case .waitRetention: draft.waitRetentionMinutes = value
        case .batteryFloor: draft.batteryFloorPercent = value
        case .batteryEntry: draft.batteryEntryPercent = value
        case .batteryCap: draft.batteryCapMinutes = value
        case .runCap: draft.runCapMinutes = value
        default: break
        }
    }
}
