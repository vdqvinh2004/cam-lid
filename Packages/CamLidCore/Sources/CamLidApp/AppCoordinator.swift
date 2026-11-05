import AppKit
import CamLidCore
import CamLidCLI
import Darwin

/// Live application coordinator (F01 remediation). Hosts the implemented views
/// with real local state: atomic validated file preferences,
/// a real ActivityStore recording genuine local transitions, and live
/// PolicyEngine/SafetyPolicy evaluation on a 1s tick.
///
/// HONESTY BOUNDARY: host power is actuated only through the closed-lid helper, and only when a qualified
/// support row matches (`QualifiedSupportRows`, empty in shipped code) or the user accepted this untested Mac, the user opted in and
/// the helper is installed. Otherwise there is no backend, telemetry is read-only, every surface carries the
/// preview banner and closed-lid arming is refused.
/// Start creates a *preview* session so grace/safety/cap transitions are
/// observable and recorded — safety immediately latches on unknown sensors,
/// which is the correct unknown-is-not-healthy behavior, not a bug.
enum TerminationDrainDecision {
    enum Choice: Equatable {
        case keepOpen
        case quitWithoutPendingHistory
    }

    static func shouldTerminate(
        editorSettled: Bool,
        settingsInstallSettled: Bool,
        historyDrained: Bool,
        choice: Choice? = nil
    ) -> Bool {
        if choice == .keepOpen { return false }
        let fullyDrained = editorSettled && settingsInstallSettled && historyDrained
        return fullyDrained || choice == .quitWithoutPendingHistory
    }
}

@MainActor
public final class AppCoordinator: NSObject, NSApplicationDelegate, MenuBarActions {
    private let menuBar = MenuBarController()
    private var config: Configuration = (try? Configuration()) ?? uncheckedDefaultConfig()
    private let history: AsyncHistoryRecorder
    private let sensors = LiveSensorProvider()
    private let healthReader: (() -> HealthSnapshot)?
    private let loginItem = LoginItemController()
    private let helper: HelperController
    private var holdReconciler = PowerHoldReconciler()
    private var holdTransport: (any PowerHoldTransport)?
    private let keepAwake = KeepAwakeAssertion()
    private let shortcut = GlobalHotKey()
    private var commandAdmissions = CommandAdmissions()
    /// Identifies this app instance in admissions: a relaunch makes older receipts stale.
    private let instanceID = UUID().uuidString
    private let instanceGeneration: UInt64 = 1
    private let makeHoldTransport: () -> any PowerHoldTransport
    /// Support row that qualifies closed-lid actuation on this Mac and OS build, or nil. `QualifiedSupportRows`
    /// is empty today, so the helper is never asked to hold power in a shipped build.
    private let closedLidSupportRow: () -> String?
    private let systemIdentity: () -> (model: String?, osBuild: String?)
    private static let untestedAcknowledgementKey = "CamLidUntestedClosedLidAcknowledgement"
    private let outcomeNotifications: OutcomeNotifications
    private let permissions: AppPermissions
    private var latestHealth: HealthSnapshot?
    private var latestReason: String?
    private var sensorAvailability: [String: String] = [:]
    private var omittedHistoryRecords = 0
    private var lastReportedEvidenceRejection: String?
    private var terminationHistorySealed = false
    private var terminationConfirmed = false
    private var terminationDeferredHistory: [StoredTransition] = []

    private var session: ProtectionSession?
    private var sessionBatteryDeadline: Double?
    private var sessionTimerMinutes: Int?
    private var sessionSleepDelayMinutes: Int?
    private var agents = RuntimeAgentStore()
    private let controlServer: LocalControlServer
    private let preferences: UserDefaults
    private let configURL: URL
    private let settingsWriter: @Sendable (Data, URL) throws -> Void
    private let settingsInstaller: @Sendable (URL, URL) throws -> Void
    private lazy var settingsPreparer = PreferenceWritePreparer(writer: settingsWriter, installer: settingsInstaller)
    private var settingsInstallToken: UUID?
    private var settingsPreparationCount = 0
    var hasPendingSettingsInstallation: Bool { settingsInstallToken != nil }
    var hasPendingSettingsWork: Bool { settingsPreparationCount > 0 || hasPendingSettingsInstallation }
    private var revision = 1
    private var safety = SafetyPolicy()
    private var cpu = CPUObserver()
    private var lastReportedState: EffectiveState = .off
    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private var orcaUITracker = OrcaUITracker()
    private var orcaUIIssue: String? = "accessibilityObservationRemoved"
    private var orcaUIReadDiagnostics = OrcaUIReadDiagnostics()
    private var orcaUISurvey: OrcaUIStructureSurveyResult?
    private var orcaMetadataTracker = OrcaUITracker()
    private var orcaMetadataPolling = false
    private var lastOrcaMetadataPoll = -Double.infinity
    private var lastOrcaMetadataSuccess = -Double.infinity
    private var orcaMetadataIssue = "orcaMetadataNotObserved"
    private var orcaMetadataEpoch = UUID()
    private var processPolling = false
    private var lastProcessPoll = -Double.infinity
    private var lastProcessSuccess = -Double.infinity
    private var lastProcessObservation = -Double.infinity
    private var processCandidates: [ProcessCandidate] = []
    /// Spec 015: outside-observed working/idle tasks for directly run agents, by provider.
    private var activityTasks: [String: [AgentTask]] = [:]
    private var activityMemory: [String: AgentActivityMemory] = [:]
    private let sampleActivityNow: @Sendable (_ excludeUnderOrca: Bool) -> (processes: [AgentActivityProcess], at: Double)
    private var installationSnapshot: AgentInstallationSnapshot?
    private var lifetimeTracker = LifetimeRuleTracker()
    private var lifetimeProcessSnapshot: LifetimeProcessSnapshot?
    private var exactTaskEpoch: String?
    private var latestLifetimeState: LifetimePolicyState?

    private var utilityUI: UtilityUIProcess?
    private var activityOutcome: String?
    private lazy var updates = UpdateController(safety: { [weak self] in
        guard let self else { var state = UpdateSafetyContext(); state.recoveryRequired = true; return state }
        return self.updateSafetyContext()
    })
    private var refusalNotice: String?
    private var authorityUnavailable = false
    private var terminationFlowActive = false

    private static let onboardedKey = "CamLidOnboarded"
    private static let configKey = "CamLidConfigurationV1"

    public override convenience init() {
        let arguments = ProcessInfo.processInfo.arguments
        let qaPath: String? = {
            if let index = arguments.firstIndex(of: "--qa-state-directory"), arguments.count > index + 1 { return arguments[index + 1] }
            return Bundle.main.object(forInfoDictionaryKey: "CamLidQAStateDirectory") as? String
        }()
        if let qaPath {
            let root = URL(fileURLWithPath: qaPath, isDirectory: true)
            let preferences = UserDefaults(suiteName: "CamLidQA." + root.lastPathComponent) ?? .standard
            self.init(historyDirectory: root.appendingPathComponent("history"),
                controlDirectory: root.appendingPathComponent("control"), preferences: preferences)
            return
        }
        self.init(historyDirectory: FileHistoryStorage.defaultDirectory)
    }

    init(historyDirectory: URL, controlDirectory: URL = LocalControlChannel.defaultDirectory,
         preferences: UserDefaults = .standard, settingsWriter: (@Sendable (Data, URL) throws -> Void)? = nil,
         settingsInstaller: (@Sendable (URL, URL) throws -> Void)? = nil,
         outcomeNotifications: OutcomeNotifications? = nil, permissions: AppPermissions? = nil,
         healthReader: (() -> HealthSnapshot)? = nil,
         helperController: HelperController? = nil,
         holdTransportFactory: (() -> any PowerHoldTransport)? = nil,
         closedLidSupportRow: (() -> String?)? = nil,
         systemIdentity: (() -> (model: String?, osBuild: String?))? = nil,
         activitySampler: (@Sendable (_ excludeUnderOrca: Bool) -> (processes: [AgentActivityProcess], at: Double))? = nil) {
        self.sampleActivityNow = activitySampler ?? { AppCoordinator.sampleActivity(NativeProcessList(), excludeUnderOrca: $0) }
        self.healthReader = healthReader
        self.helper = helperController ?? HelperController()
        self.makeHoldTransport = holdTransportFactory ?? { XPCPowerHoldTransport() }
        self.systemIdentity = systemIdentity ?? { QualifiedSupportRows.currentSystem() }
        self.closedLidSupportRow = closedLidSupportRow ?? {
            let system = QualifiedSupportRows.currentSystem()
            return QualifiedSupportRows.matching(model: system.model, osBuild: system.osBuild)
        }
        self.preferences = preferences
        self.outcomeNotifications = outcomeNotifications ?? OutcomeNotifications()
        self.permissions = permissions ?? AppPermissions()
        self.configURL = historyDirectory.appendingPathComponent(PersistedSettings.fileName)
        self.settingsInstaller = settingsInstaller ?? { source, destination in
            guard Darwin.rename(source.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        self.settingsWriter = settingsWriter ?? { data, url in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".preferences-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            guard rename(temporary.path, url.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        controlServer = LocalControlServer(directory: controlDirectory)
        let storage = FileHistoryStorage(directory: historyDirectory)
        history = AsyncHistoryRecorder(store: ActivityStore(storage: storage), diagnostic: { storage.lastOperationError() })
        super.init()
        loadPersistedConfig()
    }

    // MARK: - Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        start()
        _ = shortcut.register { [weak self] in self?.toggleAutoFromShortcut() }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        shortcut.unregister()
        // Closing the connection makes the helper restore at once; a crash does the same.
        holdTransport?.close()
        controlServer.stop()
        if let thermalObserver { NotificationCenter.default.removeObserver(thermalObserver) }
        utilityUI?.close(); utilityUI = nil
        menuBar.remove()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let helper = utilityUI, helper.isRunning {
            Task { @MainActor in
                guard await helper.prepareToQuit() else { sender.reply(toApplicationShouldTerminate: false); return }
                self.utilityUI = nil
                let reply = self.applicationShouldTerminate(sender)
                if reply != .terminateLater { sender.reply(toApplicationShouldTerminate: reply == .terminateNow) }
            }
            return .terminateLater
        }

        guard beginTerminationFlow() else { return .terminateCancel }

        func reply(_ shouldTerminate: Bool) {
            if !shouldTerminate { cancelTerminationFlow() }
            else { terminationConfirmed = true }
            sender.reply(toApplicationShouldTerminate: shouldTerminate)
        }

        func present(_ alert: NSAlert) async -> NSApplication.ModalResponse { alert.runModal() }

        func finishAfterDraining(editorSettled: Bool) async {
            let settingsInstallSettled = await settleSettingsInstallation(timeout: 2)
            // Admission is closed before the ordered barrier. Timer/sensor
            // callbacks cannot append a transition after a successful drain.
            sealTerminationHistory()
            let historyBarrierPassed = await history.flush(timeout: 2)
            let historyDrained = historyBarrierPassed && history.lastError == nil && omittedHistoryRecords == 0 && terminationDeferredHistory.isEmpty
            guard !TerminationDrainDecision.shouldTerminate(
                editorSettled: editorSettled,
                settingsInstallSettled: settingsInstallSettled,
                historyDrained: historyDrained
            ) else {
                reply(true)
                return
            }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Pending changes could not be confirmed"
            alert.informativeText = "CamLid could not confirm every settings and activity-history write before the quit deadline. An in-flight settings install may still apply after CamLid quits, and pending history may be lost. Keep CamLid open to let pending work finish, or quit with those changes unconfirmed."
            alert.addButton(withTitle: "Keep Open")
            alert.addButton(withTitle: "Quit Without Pending History")
            let response = await present(alert)
            let choice: TerminationDrainDecision.Choice = response == .alertSecondButtonReturn
                ? .quitWithoutPendingHistory : .keepOpen
            reply(TerminationDrainDecision.shouldTerminate(
                editorSettled: editorSettled,
                settingsInstallSettled: settingsInstallSettled,
                historyDrained: historyDrained,
                choice: choice
            ))
        }

        Task { @MainActor in await finishAfterDraining(editorSettled: true) }
        return .terminateLater
    }

    /// Admission closes before awaiting any quit work; cancelling quit restores
    /// it. These state changes perform no UI, storage, process or power action.
    @discardableResult func beginTerminationFlow() -> Bool {
        guard !terminationFlowActive else { return false }
        terminationFlowActive = true; return true
    }
    func sealTerminationHistory() { terminationHistorySealed = true; history.sealMutations() }
    func cancelTerminationFlow() {
        terminationHistorySealed = false; terminationFlowActive = false; terminationConfirmed = false; history.resumeMutations()
        let deferred = terminationDeferredHistory; terminationDeferredHistory.removeAll(keepingCapacity: true)
        for transition in deferred {
            if !history.record(transition), omittedHistoryRecords < Int.max { omittedHistoryRecords += 1 }
        }
    }

    func start() {
        startControlService()
        loginItem.refresh()
        helper.observe { [weak self] in
            guard let self else { return }
            self.utilityUI?.send(.update(self.utilityUIState()))
            self.refresh()
        }
        helper.refresh()
        outcomeNotifications.configure(categories: config.notificationCategories ?? [])
        outcomeNotifications.onPermissionChanged = { [weak self] in
            guard let self, self.utilityUI?.isRunning == true else { return }
            self.utilityUI?.send(.update(self.utilityUIState()))
        }
        Task { await outcomeNotifications.refresh() }
        menuBar.actions = self
        menuBar.onToggleDashboard = { [weak self] in self?.toggleDashboard() }
        menuBar.onOpenOptions = { [weak self] in self?.utilityUI?.send(.closeDashboard) }
        menuBar.install()
        record(category: .configuration, newState: .ready, reasons: ["appLaunched"])
        refresh()
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if !preferences.bool(forKey: Self.onboardedKey) {
            showOnboarding()
        }
    }

    // MARK: - MenuBarActions (preview sessions; never power actuation)

    public func menuBarStartProtection() { Task { await activateDashboardMode(.auto, expectedRevision: revision) } }

    func activateDashboardMode(_ mode: RequestedMode, expectedRevision: Int) async {
        guard !authorityUnavailable, !terminationFlowActive, !hasPendingSettingsWork else { return }
        guard revision == expectedRevision else {
            refusalNotice = "Settings changed. Retry the mode selection."; refresh(); return
        }
        if mode == .off || session?.requestedMode == mode {
            menuBarStopProtection()
            return
        }
        var patch = ConfigPatch(); patch.mode = mode
        if config.mode == .manual, config.timerMinutes == nil { patch.timerMinutes = 0 }
        guard case .saved = await applySettingsPatchAsync(patch, expectedRevision: expectedRevision) else {
            refusalNotice = "Mode not started. Settings could not be confirmed; retry."; refresh(); return
        }
        await startPreviewSession()
    }

    func startPreviewSession(mode requested: RequestedMode? = nil) async {
        guard !authorityUnavailable, !terminationFlowActive else { return }
        refusalNotice = nil
        guard (requested ?? config.mode) != .off else {
            refusalNotice = "Choose a mode before starting."
            refresh(); toggleDashboard(show: true); return
        }
        if config.closedLidOptIn, !closedLidAllowed {
            refusalNotice = "Closed lid isn’t available yet. Settings › Closed Lid shows what is missing."
            record(category: .configuration, newState: sessionStateForRecord(), reasons: ["backendUnverified"])
            refresh()
            toggleDashboard(show: true)
            return
        }
        guard session == nil else { return }
        let health = currentHealth()
        if let reason = config.batteryEntryRefusal(health: health) {
            refusalNotice = switch reason {
            case "batteryEntryLow": "Battery is below the start level. Connect the charger or check the entry level in Safety settings."
            case "batteryUnknown": "Battery reading is unavailable. Connect the charger or retry after readings recover."
            case "notCharging": "Connect the charger, or turn off Require charger and enable Allow battery sessions in Safety settings."
            default: "Power source is unavailable. Retry after readings recover."
            }
            record(category: .configuration, newState: sessionStateForRecord(), reasons: [reason])
            refresh(); toggleDashboard(show: true); return
        }
        helper.refresh()
        let mode = requested ?? config.mode
        let now = uptime()
        sessionBatteryDeadline = health.powerSource == .battery
            ? now + Double(min(config.runCapMinutes, config.batteryCapMinutes)) * 60 : nil
        guard let created = try? ProtectionSession(
            id: UUID().uuidString, requestedMode: mode, armedClosedLid: false,
            startedAtMonotonic: now,
            capDeadlineMonotonic: config.sessionDurationMinutes(for: mode, powerSource: health.powerSource).map { now + Double($0) * 60 }
        ) else { return }
        session = created
        let startTimerMaximum = sessionBatteryDeadline.map { max(0, Int(($0 - now) / 60)) }
            ?? (health.powerSource == .ac ? config.runCapMinutes : min(config.runCapMinutes, config.batteryCapMinutes))
        sessionTimerMinutes = config.timedDurationMinutes == 0 ? 0 : min(config.timedDurationMinutes, startTimerMaximum)
        sessionSleepDelayMinutes = config.completionDelayMinutes
        record(category: .enrollment, newState: created.effectiveState, reasons: ["sessionStarted"])
        refresh()
    }

    /// ⌃⌥⌘K: starts Auto when nothing is running, and stops the running session otherwise (spec 018 FR-009).
    func toggleAutoFromShortcut() {
        if session != nil {
            menuBarStopProtection()
        } else {
            Task { await startPreviewSession(mode: .auto) }
        }
    }

    public func menuBarStopProtection() {
        guard session != nil, !terminationFlowActive else { return }
        record(category: .stateTransition, newState: .ready, reasons: ["sessionStopped"])
        session = nil
        refresh()
    }

    public func menuBarShowWelcome() { showOnboarding() }
    public func menuBarOpenSettings() { showSettings() }
    public func menuBarOpenSleepDiagnostics() { showUtility(.sleepDiagnostics) }
    public func menuBarOpenActivityLog() { showActivityLog() }
    public func menuBarQuit() {
        // Without a qualified row no power state is owned. With one, closing the helper connection below makes
        // the helper restore at once, so an immediate terminate is still safe.
        record(category: .configuration, newState: .off, reasons: ["appQuit", releaseHoldForQuit()])
        NSApp.terminate(nil)
    }

    /// Drops the helper connection before quitting. The helper restores the sleep setting as soon as its client
    /// disconnects (G2 trial 3), so quitting with a held lease is safe; the outcome names what happened.
    @discardableResult
    func releaseHoldForQuit() -> String {
        let held = holdReconciler.status == .held || holdReconciler.status == .acquiring
        holdTransport?.close()
        keepAwake.release()
        return held ? "helperRestoresOnDisconnect" : "noPowerResourcesOwned"
    }

    public var menuBarCanStart: Bool { !authorityUnavailable && !terminationFlowActive && !hasPendingSettingsWork }
    /// Auto specifically needs at least one detection-enabled agent.
    public var menuBarAutoAvailable: Bool { !config.adapterEnrollment.isEmpty }
    public var menuBarCanStop: Bool { session != nil }
    public var menuBarActiveMode: RequestedMode? { session?.requestedMode }

    @discardableResult
    func changeTimerDuration(_ minutes: Int, expectedRevision: Int) -> Bool {
        let now = uptime()
        let maximum = timerMaximumMinutes(now: now)
        guard !authorityUnavailable, !terminationFlowActive, !hasPendingSettingsWork,
              revision == expectedRevision, var active = session,
              let duration = active.restartTimer(minutes: minutes, maximumMinutes: maximum, now: now) else {
            refusalNotice = "Timer not changed. Retry in a running Timed session."; refresh(); return false
        }
        sessionTimerMinutes = duration
        session = active
        let batteryLimited = sessionBatteryDeadline != nil || latestHealth?.powerSource != .ac
        let batteryRemaining = sessionBatteryDeadline.map { max(0, Int(($0 - now) / 60)) }
        if minutes > 0, let batteryRemaining, batteryRemaining < duration {
            refusalNotice = "Timer capped at \(batteryRemaining) min remaining by the battery safety limit. Connect power for a longer timer."
        } else if minutes > 0, duration < minutes {
            refusalNotice = batteryLimited
                ? "Timer capped at \(duration) min by the battery safety limit. Connect power for a longer timer."
                : "Timer capped at \(duration) min by the session limit."
        } else {
            refusalNotice = nil
        }
        record(category: .configuration, newState: active.effectiveState, reasons: ["sessionTimerChanged"])
        refresh()
        return true
    }

    /// Longest finite timer the active session can accept without extending
    /// the latched battery deadline. This is the stable safety cap, not the
    /// shrinking remaining time, so the picker always has a valid selection.
    /// Unknown power is treated conservatively as battery.
    private func timerMaximumMinutes(now: Double) -> Int {
        if sessionBatteryDeadline != nil || latestHealth?.powerSource != .ac {
            return min(config.runCapMinutes, config.batteryCapMinutes)
        }
        return config.runCapMinutes
    }

    private func timerLimitText(now: Double) -> String? {
        let power = latestHealth?.powerSource ?? .unknown
        let maximum = timerMaximumMinutes(now: now)
        guard let deadline = sessionBatteryDeadline else {
            guard power != .ac, maximum < config.runCapMinutes else { return nil }
            return "Battery safety limit: \(maximum) min. Connect power for a longer timer."
        }
        let remaining = max(0, Int((deadline - now) / 60))
        if remaining <= 0 { return "Battery safety limit reached. Connect power to start another timer." }
        return "Battery safety limit: \(maximum) min · \(remaining) min remaining."
    }

    @discardableResult
    func changeSleepDelay(_ minutes: Int, expectedRevision: Int) -> Bool {
        guard !authorityUnavailable, !terminationFlowActive, !hasPendingSettingsWork,
              revision == expectedRevision, var active = session,
              active.changeSleepDelay(minutes: minutes, previousMinutes: sessionSleepDelayMinutes ?? config.completionDelayMinutes) else {
            refusalNotice = "Sleep delay not changed. Retry in a running Auto session."; refresh(); return false
        }
        sessionSleepDelayMinutes = minutes
        session = active
        refusalNotice = nil
        record(category: .configuration, newState: active.effectiveState, reasons: ["sessionSleepDelayChanged"])
        refresh()
        return true
    }

    // MARK: - Live evaluation

    private func uptime() -> Double { ContinuousTime.now }

    private func currentHealth() -> HealthSnapshot {
        if let healthReader { return healthReader() }
        // Live read-only sensors where they exist (battery/thermal/display);
        // lid has a separate timestamp and CPU a separate interval sampler.
        let readings = sensors.read()
        return HealthMonitor().snapshot(from: readings, now: uptime()).snapshot
    }

    private func sessionStateForRecord() -> EffectiveState {
        session?.effectiveState ?? (config.mode == .off ? .off : .ready)
    }

    /// The Strict row for this Mac (ADR 0003). Strict has no untested acceptance: no row, no Strict.
    var strictRow: String? {
        let system = systemIdentity()
        return QualifiedSupportRows.matching(model: system.model, osBuild: system.osBuild, in: QualifiedSupportRows.strictRows)
    }

    /// Whether the chosen closed-lid mode may act on this Mac: Standard follows its permit, Strict its own row.
    var closedLidAllowed: Bool {
        config.powerMode == .strict ? strictRow != nil : closedLidPermit().allowsActuation
    }

    /// Refuses a mode change while a session or hold exists, or to Strict on a Mac without a Strict row.
    private func powerModeRefusal(_ patch: ConfigPatch) -> String? {
        guard let target = patch.powerMode else { return nil }
        let decision = PowerModeSwitch.decide(from: config.powerMode, to: target,
            leaseActive: session != nil || holdReconciler.status != .inactive, journalUnresolved: false,
            targetAvailable: target == .standard || strictRow != nil)
        return switch decision {
        case .allowed: nil
        case .refused(reason: "modeUnavailable"): "Strict isn’t tested on this Mac, so it can’t be chosen."
        case .refused: "Stop the session before changing the closed-lid mode."
        }
    }

    func closedLidPermit() -> ClosedLidPermit {
        if let row = closedLidSupportRow() { return .qualified(rowID: row) }
        let system = systemIdentity()
        let stored = preferences.data(forKey: Self.untestedAcknowledgementKey)
            .flatMap { try? JSONDecoder().decode(UntestedAcknowledgement.self, from: $0) }
        return ClosedLidPermit.decide(model: system.model, osBuild: system.osBuild, rows: [], acknowledgement: stored)
    }

    /// Records or withdraws the user's acceptance of closed lid on this untested model and macOS build (FR-017).
    /// Only reachable from the confirmed Settings action.
    func setUntestedAcknowledgement(_ accepted: Bool) {
        let system = systemIdentity()
        if accepted, let model = system.model, let osBuild = system.osBuild,
           let data = try? JSONEncoder().encode(UntestedAcknowledgement(model: model, osBuild: osBuild, acceptedAt: Date())) {
            preferences.set(data, forKey: Self.untestedAcknowledgementKey)
        } else {
            preferences.removeObject(forKey: Self.untestedAcknowledgementKey)
        }
        record(category: .configuration, newState: sessionStateForRecord(),
               reasons: [accepted ? "untestedConfigurationAccepted" : "untestedConfigurationWithdrawn"])
        refresh()
    }

    /// One line shown in the Dashboard and Settings in place of the old fixed preview notice.
    var closedLidCapabilityText: String {
        let permit = closedLidPermit()
        if config.powerMode == .strict {
            if strictRow == nil { return "Can’t keep your Mac awake · Strict isn’t tested on this Mac" }
        } else if !permit.allowsActuation { return "Can’t keep your Mac awake · this Mac isn’t tested" }
        switch helper.state {
        case "installed": break
        case "notInstalled": return "Can’t keep your Mac awake · helper not installed"
        case "needsReauthorization": return "Can’t keep your Mac awake · reinstall the helper after this update"
        case "needsHelperUpdate": return "Can’t keep your Mac awake · the helper has an update to install"
        case "installedNotLoaded": return "Can’t keep your Mac awake · the helper is installed but not running"
        default: return "Can’t keep your Mac awake · the helper needs attention in Settings › Closed Lid"
        }
        if !config.closedLidOptIn { return "Closed lid is off · turn it on in Settings › Closed Lid" }
        if config.powerMode == .strict { return "Closed lid ready · Strict (experimental)" }
        if case .qualified = permit { return "Closed lid ready · tested Mac" }
        return "Closed lid ready · untested Mac"
    }

    /// The fix for whatever `closedLidCapabilityText` says is missing, offered right on the Dashboard.
    var closedLidCapabilityAction: CapabilityAction? {
        guard !helper.busy else { return nil }
        let tested = config.powerMode == .strict ? strictRow != nil : closedLidPermit().allowsActuation
        guard tested else { return .openClosedLidSettings }
        switch helper.state {
        case "installed": return config.closedLidOptIn ? nil : .openClosedLidSettings
        case "notInstalled": return .installHelper
        case "needsReauthorization", "needsHelperUpdate", "installedNotLoaded": return .reinstallHelper
        default: return .openClosedLidSettings
        }
    }

    /// A refused or lost closed-lid lease ends a session only when the lid is closed. With the lid open the session
    /// carries on with the lid-open keep-awake, and closed-lid protection is reported as unavailable instead.
    static func holdSafetyReasons(lidState: LidState?, holdStops: [String]) -> [String] {
        lidState == .closed ? holdStops : []
    }

    /// Lid-open keep-awake: a working session keeps the Mac awake while the lid is not closed. A closed lid is the
    /// helper's job (`holdDesired`); without the helper, closing the lid sleeps the Mac.
    private var keepAwakeDesired: Bool {
        guard let state = session?.effectiveState, state == .protected || state == .completionGrace else { return false }
        return latestHealth?.lidState != .closed
    }

    private var holdDesired: Bool {
        guard closedLidAllowed, config.closedLidOptIn, helper.state == "installed",
              let state = session?.effectiveState else { return false }
        return state == .protected || state == .completionGrace
    }

    /// Reconciles the helper lease with the policy state after each evaluation. Never called with a held
    /// lease and no session: `desired` turns false, which releases it.
    private func driveHold(now: Double) {
        let remaining = session.map {
            min($0.capDeadlineMonotonic.map { $0 - now } ?? .infinity, Double(PowerHoldReconciler.maximumSessionSeconds))
        }
        guard let action = holdReconciler.next(desired: holdDesired, remainingSessionSeconds: remaining, now: now,
                                               strict: config.powerMode == .strict,
                                               // Battery sessions allowed in Settings › Closed Lid: the helper may hold on
                                               // battery down to the stop level, and stops itself below it.
                                               batteryFloor: config.chargingOnly || !config.batteryModeAllowed
                                                   ? nil : config.batteryFloorPercent) else { return }
        let transport = holdTransport ?? makeHoldTransport()
        holdTransport = transport
        Task { @MainActor [weak self] in
            let reply = await transport.send(action)
            guard let self else { return }
            let finished = self.uptime()
            if let reply {
                self.holdReconciler.received(reply, now: finished)
                if case .acquire(let seconds, _, _) = action, reply.accepted, var active = self.session {
                    // A fresh lease is bounded by the helper; the policy cap must not outlive it.
                    let limit = finished + Double(seconds)
                    active.capDeadlineMonotonic = min(active.capDeadlineMonotonic ?? limit, limit)
                    self.session = active
                }
            } else {
                self.holdReconciler.failed(now: finished)
            }
            self.refresh()
        }
    }

    private func closedLidMessage() -> String? {
        guard config.closedLidOptIn, let session else { return nil }
        let permit = closedLidPermit()
        let system = systemIdentity()
        let identity = "\(system.model ?? "unknown Mac"), macOS \(system.osBuild ?? "unknown build")"
        if config.powerMode == .strict, strictRow == nil {
            return "Strict isn’t tested on this Mac (\(identity)). Choose Standard in Settings › Closed Lid."
        }
        if config.powerMode == .standard, !permit.allowsActuation {
            return "Closed lid is off on this untested Mac (\(identity)). To allow it, see Settings › Closed Lid."
        }
        if helper.state != "installed" { return "Closed lid needs the helper. Install it in Settings › Closed Lid." }
        // The helper's refusal explains closed lid while the session runs, even when the lid is open and it does not
        // stop the session. A stopped session keeps the reason it latched.
        if let stop = (session.stopReasons + holdReconciler.stopReasons).first(where: { $0.hasPrefix("helper") }) {
            switch stop {
            case "helperLeaseLost": return "Closed lid lost contact with the helper; sleep was restored automatically."
            case "helperReleaseFailed": return "The sleep setting could not be restored yet. CamLid is retrying."
            default: return Self.helperReasonText(String(stop.dropFirst("helper:".count)))
            }
        }
        if let app = helper.keepAwakeApps.first(where: \.resetsSleepSetting)?.name {
            return "\(app) resets the sleep setting, so closed lid will be interrupted. Quit \(app) or remove its helper."
        }
        let others = helper.keepAwakeApps.filter { !$0.resetsSleepSetting }.map(\.name)
        if !others.isEmpty {
            return "Another keep-awake app is running (\(others.joined(separator: ", "))). It won’t stop closed lid, but your Mac may stay awake after CamLid finishes."
        }
        if permit == .untestedAcknowledged { return "Untested configuration: \(identity)." }
        switch holdReconciler.status {
        case .refused(let reason): return Self.helperReasonText(reason)
        case .lost: return "Closed lid lost contact with the helper; sleep will be restored automatically."
        case .releaseFailed: return "The sleep setting could not be restored yet. CamLid is retrying."
        default: return holdReconciler.unavailableReason == nil ? nil : "Closed lid can’t reach the helper. Retrying."
        }
    }

    static func helperReasonText(_ reason: String) -> String {
        switch reason {
        case "systemSleptWhileHeld": "The Mac slept during a Strict session (macOS can end Strict, for example when a display changes). Start a new session to continue."
        case "mechanismUnavailable": "The installed helper doesn’t offer Strict yet. Reinstall it in Settings › Closed Lid."
        case "safetyRefused": "Closed lid can only start with the lid open, normal temperature and no external display, on the charger (or on battery above the stop level when battery sessions are allowed)."
        case "preexistingOverride", "foreignGlobalSleepDisabled": "Another app already disables sleep, so CamLid left it alone."
        case "overrideChanged": "Another app changed the sleep setting (for example LidRun), so closed lid stopped."
        case "recoveryRequired", "restorationFailed", "startupInspectionFailed":
            "The helper needs recovery before it can hold the Mac awake. Restart the Mac or reinstall the helper in Settings › Closed Lid."
        case "notReady": "The helper isn’t ready. Reinstall it in Settings › Closed Lid or restart the Mac."
        case "safetyStop": "Stopped for safety: check power, battery, temperature and external displays."
        case "sessionExpired": "The closed-lid time limit was reached."
        case "invalidLease", "renewalRefused", "renewalExpiredDuringCommit", "heartbeatExpired", "clientDisconnected",
             "monitorFailed", "helperStopping", "helperRestart", "operationFailed", "operationFailedCleanup":
            "Closed lid lost its hold, and the sleep setting was restored. Start again to continue."
        // Unknown codes stay in the log and `camlid status`, never in the interface.
        default: "Closed lid stopped."
        }
    }

    private var helperSummary: String {
        switch helper.state {
        case "installed": "helper installed"
        case "notInstalled": "helper not installed"
        case "unknown": "helper not checked"
        default: "helper needs attention"
        }
    }

    private func refresh() {
        guard !terminationConfirmed else { return }
        permissions.refresh()
        agents.configure(waitRetentionSeconds: Double(config.waitRetentionMinutes) * 60)
        pollProcesses()
        pollOrcaMetadata()
        let now = uptime()
        if config.orcaMetadataAllowed, lastOrcaMetadataSuccess.isFinite, now - lastOrcaMetadataSuccess > 15 {
            invalidateOrcaMetadata(issue: "orcaMetadataStale")
        }
        let health = currentHealth()
        latestHealth = health
        recordSensorAvailability(health)
        if agents.lastRejection != lastReportedEvidenceRejection {
            lastReportedEvidenceRejection = agents.lastRejection
            record(category: .configuration, newState: sessionStateForRecord(),
                reasons: agents.lastRejection.map { ["agentEvidenceRejected", $0] } ?? ["agentEvidenceRecovered"])
        }
        let cpuEvaluation = cpu.evaluate(cpuPercent: health.cpuPercent, cpuStopEnabled: config.cpuStopEnabled, now: now)
        let baseSignal = safety.evaluate(
            health: health, config: config, cpuStop: cpuEvaluation.stop, now: now)
        // The helper's refusal or stop ends a closed-lid session; the app never works around it.
        let signal = SafetySignal(reasons: baseSignal.reasons + Self.holdSafetyReasons(
            lidState: latestHealth?.lidState, holdStops: holdReconciler.stopReasons))
        let lifetime = updateLifetimePolicy(now: now)
        if var active = session {
            // Battery exposure latches a cap from session start; AC return and timer edits cannot extend it.
            if health.powerSource != .ac || sessionBatteryDeadline != nil {
                let deadline = active.startedAtMonotonic + Double(min(config.runCapMinutes, config.batteryCapMinutes)) * 60
                sessionBatteryDeadline = min(sessionBatteryDeadline ?? deadline, deadline)
                if let batteryDeadline = sessionBatteryDeadline {
                    active.capDeadlineMonotonic = min(active.capDeadlineMonotonic ?? batteryDeadline, batteryDeadline)
                    if sessionTimerMinutes ?? 0 > 0 {
                        sessionTimerMinutes = min(sessionTimerMinutes ?? 0,
                                                   min(config.runCapMinutes, config.batteryCapMinutes))
                    }
                }
            }
            var policyConfig = config
            policyConfig.completionDelayMinutes = sessionSleepDelayMinutes ?? config.completionDelayMinutes
            let decision = PolicyEngine.evaluate(
                session: active, tasks: sleepRelevantTasks(now: now), health: health, config: policyConfig,
                armed: true, safety: signal, recoveryConflict: false,
                completionUncertain: agentCompletionUncertain()
                    || (!config.adapterEnrollment.isEmpty && now - lastProcessSuccess > 15),
                lifetimeHoldReason: commandHoldReason(now: now) ?? lifetime?.holdReason
                    ?? (hasLifetimeRules ? "lifetimeRuleUnknown" : nil),
                lifetimeCompletionSuppressed: lifetime?.suppressesAutoCompletion ?? hasLifetimeRules,
                nowMonotonic: now)
            let changed = decision.state != active.effectiveState
            active = decision.session
            session = active
            if changed {
                record(
                    category: decision.state == .safetyStopped ? .safetyStop
                        : decision.state == .completionGrace ? .grace
                        : decision.state == .expired ? .capExpiry : .stateTransition,
                    newState: decision.state, reasons: decision.reasons)
            }
        }
        driveHold(now: now)
        keepAwake.reconcile(wanted: keepAwakeDesired, now: now)
        let shown = session?.effectiveState ?? (config.mode == .off ? .off : .ready)
        if shown != lastReportedState {
            lastReportedState = shown
        }
        latestReason = statusReason(signal: signal)
        let activeMode = session?.requestedMode
        let agentWorking = activeMode == .auto && badgeStates().contains {
            $0.detectionEnabled && $0.workingCount > 0
        }
        let timerRemaining: Double? = if activeMode == .timed || activeMode == .manual {
            session?.capDeadlineMonotonic.map { max(0, $0 - now) }
        } else {
            nil
        }
        menuBar.update(status: MenuBarStatus(
            state: shown, reasonText: latestReason, leaseVerified: holdReconciler.leaseVerified(now: now),
            agentWorking: agentWorking, timerRemainingSeconds: timerRemaining,
            keepingAwakeWithLidOpen: shown == .protected && !holdReconciler.leaseVerified(now: now)
                && keepAwake.verified && health.lidState == .open))
        updates.refreshSafety()
        if utilityUI?.isRunning == true { utilityUI?.send(.update(utilityUIState())) }
    }

    private func sensorDetails(_ health: HealthSnapshot, now: Double) -> String {
        let lidAge = health.lid?.sampledAtMonotonic.map { String(format: "%.1f s old", max(0, now - $0)) } ?? "no fresh sample"
        let lidSource = health.lid?.source ?? "IOPMrootDomain.AppleClamshellState"
        return "Lid source: \(lidSource) · \(lidAge).\nTemperature: \(health.temperature.displayText).\nPressure is a macOS thermal state, not degrees."
    }

    private func recordSensorAvailability(_ health: HealthSnapshot) {
        let current = ["lid": health.lid?.availability ?? "error", "temperature": health.temperature.availability]
        for key in ["lid", "temperature"] {
            guard let availability = current[key], sensorAvailability[key] != availability else { continue }
            sensorAvailability[key] = availability
            // Only bounded machine codes, never raw system/provider errors.
            record(category: .configuration, newState: sessionStateForRecord(), reasons: [key + "AvailabilityChanged", key + availability.capitalized])
        }
    }

    private func protectionReadiness() -> ProtectionReadiness {
        let now = uptime()
        let permit = closedLidPermit()
        let row: String? = if case .qualified(let id) = permit { id } else { nil }
        let installed = helper.state == "installed"
        let leaseVerified = holdReconciler.leaseVerified(now: now)
        let ownership: ProtectionOwnershipEvidence = switch (holdReconciler.restoration, leaseVerified, installed) {
        case (.conflict, _, _): .conflict
        case (_, true, _): .verifiedCamLidOwnership
        case (_, _, true): .noExternalOverride
        default: .unknown
        }
        return ProtectionReadiness(facts: ProtectionReadinessFacts(buildKind: .current,
            supportRowID: row, supportRowQualified: row != nil, helperTrusted: installed,
            helperAvailable: installed, recoveryRequired: holdReconciler.restoration == .failed,
            recoveryJournalReady: installed, ownershipEvidence: ownership, matchingGlobalOverrideObserved: false,
            backendVerified: installed && holdReconciler.status != .lost, leaseVerified: leaseVerified,
            safetyQualifying: leaseVerified && holdReconciler.stopReasons.isEmpty,
            requestedClosedLidIntent: config.closedLidOptIn))
    }

    private func badgeStates() -> [AgentBadgeState] {
        AgentBadgeState.providers.map { provider in
            AgentBadgeState(provider: provider, enabled: config.adapterEnrollment.contains(provider), tasks: observedTasks(provider: provider, now: uptime()), evidenceAgeSeconds: agents.lastReceipt(provider: provider).map { max(0, uptime() - $0) },
                processCount: uptime() - lastProcessObservation <= 15 ? processCandidates.filter { $0.provider == provider }.count : 0,
                cliDetected: installationSnapshot?.cliDetected.contains(provider),
                appDetected: installationSnapshot?.appDetected.contains(provider) ?? false,
                observationKnown: uptime() - lastProcessSuccess <= 15
                    || (provider == "orca" && config.orcaMetadataAllowed && uptime() - lastOrcaMetadataSuccess <= 15))
        }
    }

    private func agentCompletionUncertain() -> Bool {
        // Owner decision (trial 8, option A): Orca's idle report counts as completion while its metadata is fresh;
        // without metadata consent or with stale metadata, completion stays uncertain.
        (config.adapterEnrollment.contains("orca")
            && !(config.orcaMetadataAllowed && uptime() - lastOrcaMetadataSuccess <= 15)) || badgeStates().contains {
            // An enabled agent with nothing running has nothing to finish (trial 8: idle Codex and OpenCode read
            // "Unknown" and blocked every completion). A failed scan (nil count) stays uncertain.
            guard $0.detectionEnabled, ($0.processCount ?? 1) > 0 else { return false }
            return $0.observedState == "Unknown"
                || (Self.activityProviders.contains($0.provider) && !activityClassified($0.provider))
        }
    }

    /// External observations stay visible independently of sleep selection.
    func sleepRelevantTasks(now: Double) -> [AgentTask] {
        agents.tasks(now: now).filter { task in
            guard let provider = agents.provider(for: task.id) else { return false }
            return config.adapterEnrollment.contains(provider)
        } + activityTasks.filter { config.adapterEnrollment.contains($0.key) }.values.flatMap { $0 }
    }

    private var hasLifetimeRules: Bool {
        (config.lifetimeRules ?? []).contains(where: \.enabled)
    }

    private func updateLifetimePolicy(now: Double) -> LifetimePolicyState? {
        let state = try? lifetimeTracker.update(
            rules: config.lifetimeRules ?? [], snapshot: lifetimeProcessSnapshot, now: now,
            sessionID: session?.id, exactTaskEpoch: exactTaskEpoch,
            waitRetentionSeconds: Double(config.waitRetentionMinutes) * 60)
        latestLifetimeState = state
        return state
    }

    private func statusReason(signal: SafetySignal) -> String? {
        if session == nil && config.mode == .off { return nil }
        if agents.lastRejection == "enrollmentFull" { return "Agent capacity reached: 20 holding tasks are already tracked." }
        if agents.lastRejection == "retirementHistoryFull" { return "Detection history full; new agent evidence is unavailable." }
        if session == nil { return Self.noSessionReason }
        if !signal.reasons.isEmpty {
            let labels = ["thermalCritical": "Critical thermal pressure", "thermalSerious": "Sustained serious thermal pressure",
                "thermalUnknown": "Thermal reading unavailable", "lidUnknown": "Lid reading unavailable",
                "powerUnknown": "Power source unavailable", "notCharging": "AC power required",
                "batteryFloor": "Battery below safety floor", "batteryUnknown": "Battery reading unavailable", "cpuStop": "Sustained CPU load exceeded limit"]
            return signal.reasons.map { labels[$0] ?? "Safety condition requires attention" }.joined(separator: ", ")
        }
        if session?.requestedMode == .auto {
            guard let lifetime = latestLifetimeState else {
                if hasLifetimeRules { return "Watched program status is unavailable." }
                return nil
            }
            if lifetime.hasActiveRule, let label = lifetime.statuses.first(where: { $0.presence == .present })?.label {
                return "Watched program is running: \(label)."
            }
            if lifetime.hasUnknownHold, let label = lifetime.statuses.first(where: { $0.presence == .unknown })?.label {
                return "Watched program status is uncertain: \(label)."
            }
            if lifetime.suppressesAutoCompletion {
                return "Watched program lifetime does not confirm AI task completion."
            }
        }
        return nil
    }

    /// Shown with "Ready" while no session runs (the menu bar label reads "CamLid: Ready, No session · …").
    nonisolated static let noSessionReason = "No session · choose Auto or Timed"

    func changeMode(_ mode: RequestedMode) {
        var patch = ConfigPatch(); patch.mode = mode
        guard let next = try? config.applying(patch) else { return }
        guard persistConfig(next) else { return }
        record(category: .configuration, newState: sessionStateForRecord(), reasons: ["modeChanged"])
        refresh()
    }

    // MARK: - Dashboard panel

    private func toggleDashboard(show: Bool? = nil) {
        let shouldShow = show ?? !(utilityUI?.dashboardVisible ?? false)
        if shouldShow { showUtility(.dashboard) } else { utilityUI?.send(.closeDashboard); menuBar.restoreFocusToStatusItem() }
    }

    private func utilityUIState() -> UtilityUIState {
        permissions.refresh()
        let anchor = menuBar.anchorButton
        let frame = anchor.flatMap { button in button.window?.convertToScreen(button.convert(button.bounds, to: nil)) } ?? .zero
        return UtilityUIState(dashboard: dashboardData(), configuration: config, revision: revision,
            protection: protectionReadiness(), settingsSection: SettingsSection(rawValue: preferences.string(forKey: "CamLidSettingsSection") ?? "") ?? .agents,
            anchorFrame: frame, installationPending: hasPendingSettingsWork,
            observationReady: uptime() - lastProcessSuccess <= 15,
            updates: updates.snapshot, canCheckUpdates: updates.canCheck,
            loginState: loginItem.state, loginMessage: loginItem.message,
            notificationPermission: outcomeNotifications.permissionState,
            accessibilityPermission: permissions.accessibility, permissionSettingsError: permissions.settingsError,
            helperState: helper.state, helperMessage: helper.message, helperBusy: helper.busy,
            closedLidPermit: closedLidPermit().statusCode, strictTested: strictRow != nil,
            systemModel: systemIdentity().model ?? "unknown", systemBuild: systemIdentity().osBuild ?? "unknown",
            keepAwakeApps: helper.keepAwakeApps, capabilityText: closedLidCapabilityText)
    }
    private func showUtility(_ surface: UtilitySurface) {
        if surface == .settings { loginItem.refresh(); Task { await outcomeNotifications.refresh() } }
        // Other keep-awake apps come and go; look again so a quit app's notice does not linger.
        if surface == .dashboard { helper.refresh() }
        guard !terminationFlowActive else { return }
        if utilityUI?.isRunning != true {
            do {
                utilityUI = try UtilityUIProcess(event: { [weak self] in self?.receiveUtilityEvent($0) }, exited: { [weak self] pid in
                    if self?.utilityUI?.pid == pid { self?.utilityUI = nil }
                })
            } catch { refusalNotice = "Couldn’t open CamLid UI. Retry from the menu."; refresh(); return }
        }
        // macOS 14+ activation is cooperative: this process got the menu-bar click and must hand activation to the
        // UI process, or its windows open behind the frontmost app.
        if let pid = utilityUI?.pid, let app = NSRunningApplication(processIdentifier: pid) {
            NSApp.yieldActivation(to: app)
        } else if let identifier = Bundle.main.bundleIdentifier {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: identifier)
        }
        utilityUI?.send(.show(surface, utilityUIState()))
    }
    func diagnosticSnapshot() async -> DiagnosticSnapshot {
        var snapshot = await SleepDiagnosticReader.shared.snapshot()
        snapshot.configuredMode = config.mode; snapshot.activeSessionMode = session?.requestedMode
        snapshot.protection = holdReconciler.leaseVerified(now: uptime()) ? .verified : .notRequested; snapshot.restoration = "noPowerResourcesOwned"
        return snapshot
    }
    func receiveUtilityEvent(_ event: UtilityUIEvent) {
        switch event {
        case .commit(let id, let patch, let revision):
            let recipient = utilityUI
            Task { @MainActor in
                let result = await self.applySettingsPatchAsync(patch, expectedRevision: revision)
                recipient?.send(.commitResult(id, result))
                if case .saved = result, !(patch.notificationCategories ?? []).isEmpty {
                    await self.outcomeNotifications.authorizeFromUserAction()
                }
            }
        case .authorizeAccessibility:
            permissions.requestAccessibility(); refresh()
        case .openPermissionSettings(let permission):
            permissions.open(permission); refresh()
        case .refreshPermissions:
            permissions.refresh(); refresh()
            Task { await outcomeNotifications.refresh() }
        case .authorizeNotifications:
            Task { await outcomeNotifications.authorizeFromUserAction() }
        case .visibility(_, let settings):
            if settings {
                permissions.refresh()
                loginItem.refresh()
                helper.refresh()
                utilityUI?.send(.update(utilityUIState()))
                Task { await outcomeNotifications.refresh() }
            }
        case .applyLoginPreference: loginItem.apply(config.launchAtLogin); refresh()
        case .installHelper: helper.install()
        case .setUntestedAcknowledgement(let accepted): setUntestedAcknowledgement(accepted)
        case .uninstallHelper: helper.uninstall()
        case .readDiagnostics(let id):
            let recipient = utilityUI
            Task { @MainActor in recipient?.send(.diagnostics(id, await self.diagnosticSnapshot())) }
        case .start: menuBarStartProtection()
        case .activateMode(let mode, let revision):
            Task { await activateDashboardMode(mode, expectedRevision: revision) }
        case .timerDuration(let minutes, let revision): changeTimerDuration(minutes, expectedRevision: revision)
        case .sleepDelay(let minutes, let revision): changeSleepDelay(minutes, expectedRevision: revision)
        case .stop: menuBarStopProtection()
        case .sleepDiagnostics: menuBarOpenSleepDiagnostics()
        case .activity: showActivityLog()
        case .reloadHistory: showActivityLog(show: false)
        case .onboarding: showOnboarding()
        case .updates: menuBarOpenUpdates()
        case .checkUpdates: updates.check(); refresh()
        case .notice(let message): refusalNotice = message; refresh()
        case .restoreStatusFocus: menuBar.restoreFocusToStatusItem()
        case .quit:
            // Leave the pipe's main-queue callback before AppKit's terminateLater loop.
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0.2)
        case .section(let section): preferences.set(section.rawValue, forKey: "CamLidSettingsSection")
        case .settings(let section):
            preferences.set(section.rawValue, forKey: "CamLidSettingsSection"); showSettings()
        case .activityOutcome(let outcome): activityOutcome = outcome; showActivityLog(show: false)
        case .exportHistory: exportLog()
        case .deleteHistory(let id): deleteHistory(sessionID: id)
        case .finishOnboarding(let id):
            let recipient = utilityUI
            recipient?.send(.onboardingResult(id, finishOnboarding()))
        case .cancelOnboarding: preferences.set(true, forKey: Self.onboardedKey)
        case .quitDecision, .editorState: break
        }
    }

    func dashboardData() -> DashboardData {
        let now = uptime()
        let active = session
        let state = active?.effectiveState ?? (config.mode == .off ? .off : .ready)
        let graceRemaining = active?.graceDeadlineMonotonic.map { max(0, $0 - now) }
        let capRemaining = active?.capDeadlineMonotonic.map { max(0, $0 - now) }
        var notices: [String] = []
        if let notice = refusalNotice { notices.append(notice) }
        if let notice = closedLidMessage() { notices.append(notice) }
        let health = latestHealth
        let summary = health.map(HealthSummary.from) ?? .unknown
        if let failure = history.lastError { notices.append("History unavailable: " + failure + ".") }
        if omittedHistoryRecords > 0 { notices.append("History omitted \(omittedHistoryRecords) transitions while storage was busy.") }
        let badges = badgeStates()
        let working = AgentBadgeState.workingSummary(badges)
        let waiting = AgentBadgeState.waitingSummary(badges)
        let summaryParts = [working, waiting].filter { !$0.hasPrefix("No ") }
        let taskSummary = summaryParts.isEmpty ? "No selected agents reporting work" : summaryParts.joined(separator: " · ")
        let data = DashboardData(
            mode: active?.requestedMode ?? config.mode, state: state,
            reasonText: latestReason ?? "",
            leaseVerified: holdReconciler.leaseVerified(now: now),
            powerActuationAvailable: holdReconciler.leaseVerified(now: now) || keepAwake.verified,
            lidDisplayText: summary.lidDisplay,
            capabilityText: closedLidCapabilityText, capabilityAction: closedLidCapabilityAction,
            tasks: allObservedTasks(now: now).map {
                DashboardTaskRow(id: $0.id, provider: agents.provider(for: $0.id) ?? activityProvider(for: $0.id) ?? "agent",
                    stateText: $0.state.rawValue, confidenceText: $0.confidence.rawValue)
            },
            taskSummaryText: taskSummary,
            batteryText: summary.battery, thermalText: summary.thermal,
            temperatureText: health?.temperature.displayText,
            sensorDetailsText: health.map { sensorDetails($0, now: now) },
            cpuText: health?.cpuPercent.map { String(format: "%.1f%%", $0) },
            freshnessText: "Read-only telemetry · backend unverified · Closed lid: \(PowerMode.standard.title), \(helperSummary)",
            isStale: health == nil,
            graceRemainingSeconds: graceRemaining,
            capRemainingSeconds: capRemaining,
            completionDelayText: "Sleep when done: \(sessionSleepDelayMinutes ?? config.completionDelayMinutes) min",
            banner: .unsupported, bannerMessage: notices.isEmpty ? nil : notices.joined(separator: " "),
            lastSessionText: active.map { "Session \($0.id.prefix(8)) rev \($0.stateRevision)" },
            stopEnabled: active != nil, startEnabled: menuBarCanStart && menuBarAutoAvailable, metrics: DashboardMetric.from(health), agents: badges,
            timerMinutes: active == nil ? nil : sessionTimerMinutes,
            timerMaximumMinutes: active == nil ? nil : timerMaximumMinutes(now: now),
            timerLimitText: active == nil ? nil : timerLimitText(now: now),
            sleepDelayMinutes: active == nil ? nil : sessionSleepDelayMinutes,
            keepingAwakeWithLidOpen: state == .protected && !holdReconciler.leaseVerified(now: now)
                && keepAwake.verified && health?.lidState == .open)
        return data
    }

    // MARK: - Settings / log / onboarding windows

    func applySettings(_ candidate: Configuration, expectedRevision: Int) -> SettingsCommitResult {
        guard revision == expectedRevision else {
            return .conflict(configuration: config, revision: revision)
        }
        do { try candidate.validate() } catch { return .failed("Settings failed validation. Nothing was saved.") }
        guard persistConfig(candidate) else { return .failed("Couldn’t save settings. Check storage and retry.") }
        record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configApplied"])
        refresh()
        return .saved(revision: revision)
    }

    /// Why a patch was refused. A stop level at or above the start level is the one refusal a user can cause from a
    /// menu (the stop menu offers up to 50 percent), so it names the other setting instead of a generic message.
    func settingsRefusal(for patch: ConfigPatch) -> String {
        do { _ = try config.applying(patch) } catch ConfigError.outOfRange(let field, _, _) where field == "batteryEntryPercent" {
            return "Not applied — the stop level must stay below “Start on battery at or above” (Advanced). Raise that first."
        } catch {}
        return "Invalid setting. Last applied value retained."
    }

    func applySettingsPatch(_ patch: ConfigPatch, expectedRevision: Int) -> SettingsCommitResult {
        guard revision == expectedRevision else {
            return .conflict(configuration: config, revision: revision)
        }
        if let refusal = powerModeRefusal(patch) { return .failed(refusal) }
        guard let candidate = try? config.applying(patch) else { return .failed(settingsRefusal(for: patch)) }
        return applySettings(candidate, expectedRevision: expectedRevision)
    }

    /// Runtime UI/RPC writes prepare away from the main thread. Revision and
    /// cancellation are checked again before installing the prepared inode.
    func applySettingsPatchAsync(_ patch: ConfigPatch, expectedRevision: Int,
                                 deadline: Double? = nil) async -> SettingsCommitResult {
        guard !authorityUnavailable, !terminationFlowActive else { return .failed("Not applied — the local authority is unavailable, quitting, or another CamLid instance owns it.") }
        guard !hasPendingSettingsInstallation else { return .unconfirmed("Outcome unconfirmed — a previous settings write is still finishing. Wait for confirmation before retrying.") }
        guard revision == expectedRevision else {
            record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configConflict"])
            return .conflict(configuration: config, revision: revision)
        }
        if let refusal = powerModeRefusal(patch) { return .failed(refusal) }
        guard revision < Int.max, let candidate = try? config.applying(patch),
              let data = try? JSONEncoder().encode(PersistedSettings(
                  schemaVersion: PersistedSettings.currentSchemaVersion, revision: revision + 1, configuration: candidate)) else {
            return .failed(settingsRefusal(for: patch))
        }
        let expires = min(deadline ?? (uptime() + 0.7), uptime() + 0.7)
        settingsPreparationCount += 1
        defer { settingsPreparationCount -= 1 }
        guard let prepared = await settingsPreparer.prepare(data, beside: configURL, deadline: expires) else {
            record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configWriteFailed"])
            return .failed("Not applied — storage is busy or unavailable. Retry the edit.")
        }
        defer { settingsPreparer.discard(prepared) }
        guard !Task.isCancelled, uptime() < expires, !terminationFlowActive, !authorityUnavailable else {
            record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configWriteFailed"])
            return .failed("Not applied — the write expired, was cancelled, or the authority is quitting. Retry when available.")
        }
        guard revision == expectedRevision, !hasPendingSettingsInstallation else {
            record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configConflict"])
            return .conflict(configuration: config, revision: revision)
        }
        let token = UUID()
        settingsInstallToken = token
        let outcome = await settingsPreparer.install(prepared, at: configURL, deadline: expires) { [weak self] success in
            Task { @MainActor in self?.finishSettingsInstallation(token: token, candidate: candidate, nextRevision: expectedRevision + 1, success: success) }
        }
        switch outcome {
        case .installed:
            finishSettingsInstallation(token: token, candidate: candidate, nextRevision: expectedRevision + 1, success: true)
            return .saved(revision: expectedRevision + 1)
        case .failed:
            finishSettingsInstallation(token: token, candidate: candidate, nextRevision: expectedRevision + 1, success: false)
            return .failed("Not applied — storage is unavailable. Retry the edit.")
        case .unconfirmed:
            record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configCommitUnconfirmed"])
            return .unconfirmed("Outcome unconfirmed — storage is still finishing the write. It may apply later; wait for confirmation before retrying.")
        }
    }

    private func finishSettingsInstallation(token: UUID, candidate: Configuration, nextRevision: Int, success: Bool) {
        guard settingsInstallToken == token else { return }
        settingsInstallToken = nil
        if success {
            acceptPersistedConfig(candidate, nextRevision: nextRevision)
            record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configApplied"])
        } else {
            record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configWriteFailed"])
        }
        refresh()
    }

    func settleSettingsInstallation(timeout: Double = 2) async -> Bool {
        let end = uptime() + max(0, min(timeout, 2))
        while hasPendingSettingsWork, uptime() < end {
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return false }
        }
        return !hasPendingSettingsWork
    }

    public func menuBarOpenUpdates() {
        showUtility(.updates)
    }

    private func updateSafetyContext() -> UpdateSafetyContext {
        var context = UpdateSafetyContext()
        context.sessionActive = session != nil
        context.recoveryRequired = session?.effectiveState == .recoveryRequired
        context.unsavedSettings = hasPendingSettingsWork || utilityUI?.settingsDirty == true
        context.agentWorkActive = allObservedTasks(now: uptime()).contains { [.working, .waiting, .unknown].contains($0.state) }
        return context
    }

    private func showSettings() { showUtility(.settings) }

    private func showActivityLog(show: Bool = true) {
        if show { showUtility(.activity) }
        let recipient = utilityUI
        let requestID = UUID()
        recipient?.send(.historyLoading(requestID))
        Task { [weak self] in
            guard let self else { return }
            let records = await self.history.transitions()
            guard recipient === self.utilityUI else { return }
            recipient?.send(.history(requestID, records ?? [],
                error: records == nil ? (self.history.lastError ?? "History read timed out. Retry to confirm current records.") : self.history.lastError,
                outcome: self.activityOutcome))
        }
    }

    private func deleteHistory(sessionID: String?) {
        guard !authorityUnavailable, !terminationFlowActive else {
            activityOutcome = "History changes unavailable: CamLid is quitting or another instance owns the authority."; showActivityLog(show: false); return
        }
        Task { [weak self] in
            guard let self else { return }
            guard !self.terminationFlowActive else { return }
            let receipt = await self.history.delete(sessionID: sessionID)
            if let receipt, self.history.lastError == nil {
                self.activityOutcome = "Deleted \(receipt.removedCount) records."
            } else {
                self.activityOutcome = "Deletion unconfirmed. Refresh history before retrying; a started operation may finish after its deadline."
            }
            self.showActivityLog(show: false)
        }
    }

    private func exportLog() {
        Task { [weak self] in
            guard let self, !self.terminationFlowActive else { return }
            guard let data = await self.history.exportRedactedJSON(salt: UUID().uuidString), self.history.lastError == nil else {
                self.activityOutcome = "Export unavailable: history could not be read."; self.showActivityLog(show: false); return
            }
            guard !self.terminationFlowActive else { return }
            self.utilityUI?.send(.exportData(data))
        }
    }

    func flushHistory(timeout: Double = 0.7) async -> Bool { await history.flush(timeout: timeout) }

    private func showOnboarding() { showUtility(.onboarding) }

    @discardableResult func finishOnboarding() -> Bool {
        guard !authorityUnavailable, !terminationFlowActive else { return false }
        guard !preferences.bool(forKey: Self.onboardedKey) else { return true }
        preferences.set(true, forKey: Self.onboardedKey)
        record(category: .configuration, newState: sessionStateForRecord(), reasons: ["onboardingComplete"])
        refresh(); return true
    }

    private func pollProcesses() {
        guard !processPolling, uptime() - lastProcessPoll >= 5 else { return }
        processPolling = true
        let started = uptime()
        lastProcessPoll = started
        let scanLifetimeRules = hasLifetimeRules && session?.requestedMode == .auto
        let lifetimeNames = NativeProcessList.kernelNames(of: config.lifetimeRules ?? [])
        let sampleActivity = sampleActivityNow
        let excludeUnderOrca = config.orcaMetadataAllowed
        Task { [weak self] in
            let (candidates, complete, installation, lifetime, activity) = await Task.detached(priority: .utility) {
                let installation = AgentCLIInstallation.snapshot()
                let processList = NativeProcessList()
                let snapshot = processList.agentSnapshot()
                let candidates = ProcessDiscovery(provider: InMemoryProcessList(records: snapshot.records),
                    patterns: AgentProviderCatalog.processPatterns, maxFallbackEntries: 20).discover()
                let lifetime = scanLifetimeRules ? processList.lifetimeSnapshot(ruleNames: lifetimeNames) : nil
                return (candidates, snapshot.complete, installation, lifetime, sampleActivity(excludeUnderOrca))
            }.value
            guard let self else { return }
            self.processPolling = false
            self.installationSnapshot = installation
            self.lifetimeProcessSnapshot = lifetime
            let orcaHosted = Set(activity.processes.filter(\.orcaHosted).map(\.pid))
            self.receiveProcessSnapshot(candidates.filter { !orcaHosted.contains($0.identity.pid) }, complete: complete, observedAt: started)
            self.receiveActivity(activity.processes, at: activity.at)
            // Presence never fabricates working/idle/completion or an Auto hold.
        }
    }

    private func pollOrcaMetadata() {
        guard config.orcaMetadataAllowed, Bundle.main.bundleURL.pathExtension == "app",
              !orcaMetadataPolling, uptime() - lastOrcaMetadataPoll >= 5 else { return }
        lastOrcaMetadataPoll = uptime(); orcaMetadataPolling = true
        let epoch = orcaMetadataEpoch
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try OrcaPoller().snapshot(consent: true) }
            }.value
            guard let self else { return }
            self.orcaMetadataPolling = false
            guard !self.terminationFlowActive, self.config.orcaMetadataAllowed, self.orcaMetadataEpoch == epoch else { return }
            switch result {
            case .success(let snapshot): self.receiveOrcaMetadataSnapshot(snapshot)
            case .failure(let error):
                // One failed poll keeps the last good state; `refresh` drops it once nothing good arrived for 15 s.
                self.orcaMetadataIssue = error is OrcaPollError ? "orcaMetadataUnavailable" : "orcaMetadataInvalid"
            }
        }
    }

    func receiveOrcaMetadataSnapshot(_ snapshot: OrcaMetadataSnapshot) {
        guard config.orcaMetadataAllowed else { return }
        let now = uptime(), duration = snapshot.receivedAt - snapshot.queryStartedAt
        let age = now - snapshot.receivedAt
        guard duration.isFinite, duration >= 0, duration <= 4.5, age.isFinite, age >= 0, age <= 1 else {
            orcaMetadataIssue = "orcaMetadataStale"; return   // a late reply is skipped, not trusted and not a reset
        }
        do {
            let events = try orcaMetadataTracker.consume(OrcaUISnapshot(statuses: snapshot.statuses,
                complete: true, observedAt: snapshot.receivedAt), now: now)
            for event in events { try receiveObservation(event) }
            lastOrcaMetadataSuccess = snapshot.receivedAt
            orcaMetadataIssue = "none"
        } catch { invalidateOrcaMetadata(issue: "orcaMetadataRejected") }
    }

    private func invalidateOrcaMetadata(issue: String) {
        orcaMetadataIssue = issue
        lastOrcaMetadataSuccess = -Double.infinity
        let now = uptime()
        if let events = try? orcaMetadataTracker.consume(OrcaUISnapshot(statuses: [], complete: false, observedAt: now), now: now) {
            for event in events { _ = try? receiveObservation(event) }
        }
    }

    func receiveOrcaUISnapshot(_ snapshot: OrcaUISnapshot) {
        do {
            let events = try orcaUITracker.consume(snapshot, now: uptime())
            orcaUIIssue = snapshot.complete ? nil : "orcaUIIncomplete"
            for event in events {
                do { try receiveObservation(event) }
                catch { orcaUIIssue = "orcaUIObservationRejected" }
            }
        } catch {
            orcaUIIssue = (error as? OrcaUIReadError)?.code ?? "orcaUIObservationRejected"
        }
    }

    /// Agents observed for activity: the terminal agents (spec 015). IDE-hosted agents (Antigravity, Cursor) are
    /// recognised by their app process, whose own CPU would read as work, so they stay presence-only.
    /// Idle levels measured 2026-11-01, all under the 0.03-core threshold: Claude Code 0.004–0.020, Codex 0–0.003,
    /// OpenCode 0.006–0.018, Freebuff 0.004–0.024, Pi 0.002–0.020.
    nonisolated static let activityProviders: Set<String> = ["claude", "codex", "opencode", "freebuff", "pi",
                                                             "copilot-cli", "aider", "gemini-cli", "amp", "goose"]

    nonisolated static func sampleActivity(_ list: NativeProcessList, excludeUnderOrca: Bool) -> (processes: [AgentActivityProcess], at: Double) {
        let observed = activityProviders
        var byName: [String: String] = [:]
        for info in AgentProviderCatalog.providers where observed.contains(info.id) {
            for name in info.processNames { byName[name] = info.id }
        }
        return (list.activityProcesses(providerByName: byName, excludeUnderOrca: excludeUnderOrca), ContinuousTime.now)
    }

    /// Classifies each observed agent process and keeps the result as `activity` tasks. A process that is gone has
    /// finished; its task is dropped, so the policy sees no holding work and runs its normal completion grace.
    func receiveActivity(_ processes: [AgentActivityProcess], at: Double) {
        var tasks: [String: [AgentTask]] = [:]
        var memory: [String: AgentActivityMemory] = [:]
        let previous = Dictionary(activityTasks.values.flatMap { $0 }.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a })
        for process in processes where !process.orcaHosted {
            let key = "activity-\(process.provider)-\(process.pid)-\(String(process.startTime.bitPattern, radix: 16))"
            var state = activityMemory[key] ?? AgentActivityMemory()
            let result = AgentActivityClassifier.step(&state, AgentActivitySample(at: at, alive: true, cpuSeconds: process.cpuSeconds,
                processAgeSeconds: Date().timeIntervalSince1970 - process.startTime),
                threshold: AgentActivityClassifier.busyThreshold(for: process.provider))
            memory[key] = state
            guard let task = try? AgentTask(id: key, sessionID: "activity-\(process.provider)", runID: key,
                state: result.state, evidenceKind: .activity, confidence: .inferred,
                unknownUntilMonotonic: result.state == .unknown ? at + AgentActivityClassifier.unknownHoldSeconds : nil) else { continue }
            tasks[process.provider, default: []].append(task)
            // History keeps the start and end of work only (sampling noise between idle and unknown is not news).
            if (previous[key] == .working) != (result.state == .working) {
                record(category: .stateTransition, newState: sessionStateForRecord(),
                       reasons: ["agentStateChanged", "\(process.provider):\(result.state.rawValue)"])
            }
        }
        activityMemory = memory
        activityTasks = tasks
    }

    /// Reported tasks plus outside-observed activity tasks for one provider.
    func sleepRelevantTasksForTesting(provider: String) -> [AgentTask] { activityTasks[provider] ?? [] }

    /// True when outside activity classifies this provider's running processes (none unknown).
    private func activityClassified(_ provider: String) -> Bool {
        guard let tasks = activityTasks[provider], !tasks.isEmpty else { return false }
        return !tasks.contains { $0.state == .unknown }
    }

    private func activityProvider(for id: String) -> String? {
        activityTasks.first { $0.value.contains { $0.id == id } }?.key
    }

    private func observedTasks(provider: String, now: Double) -> [AgentTask] {
        agents.tasks(provider: provider, now: now) + (activityTasks[provider] ?? [])
    }

    private func allObservedTasks(now: Double) -> [AgentTask] {
        agents.tasks(now: now) + activityTasks.values.flatMap { $0 }
    }

    func receiveProcessSnapshot(_ candidates: [ProcessCandidate], complete: Bool, observedAt: Double) {
        let age = uptime() - observedAt
        // A late or incomplete scan is skipped; completion turns uncertain only after 15 s without a good scan.
        guard age.isFinite, age >= 0, age <= 0.2 else { return }
        processCandidates = Array(candidates.prefix(20))
        lastProcessObservation = observedAt
        if complete && candidates.count <= 20 { lastProcessSuccess = observedAt }
    }

    // MARK: - Same-user preview control

    func startControlService() {
        do {
            try controlServer.start { [weak self] command, payload in
                let allowance = command == .diagnose ? 5.5 : 0.8
                let box = ControlReplyBox(timeout: allowance + 0.1)
                let deadline = ContinuousTime.now + allowance
                Task { @MainActor in
                    guard let self, ContinuousTime.now < deadline else {
                        box.finish(.failure(IPCError.unavailable)); return
                    }
                    do { box.finish(.success(try await self.handleControlAsync(command, payload: payload, deadline: deadline))) }
                    catch { box.finish(.failure(error)) }
                }
                return try box.wait()
            }
        } catch {
            authorityUnavailable = true
            if case IPCError.policyDenied(let reason) = error {
                refusalNotice = "Local control unavailable: " + reason
            } else { refusalNotice = "Local control couldn’t start; another copy of CamLid may be running." }
        }
    }

    func handleControlAsync(_ command: AllowlistedCommand, payload: Data, deadline: Double) async throws -> Data {
        try requireControlAdmission(command)
        if command == .admitCommand { return try await admitCommandRun(payload) }
        if command == .diagnose {
            _ = try BoundedPayload(payload)
            guard payload.isEmpty else { throw IPCError.invalidInput("diagnoseTakesNoPayload") }
            let snapshot = await diagnosticSnapshot()
            let bytes = try snapshot.boundedJSON()
            return try JSONEncoder().encode(CLIResult(json: String(decoding: bytes, as: UTF8.self), exitCode: snapshot.hasCoverage ? 0 : 4))
        }
        if command == .logsExport {
            _ = try BoundedPayload(payload)
            guard let data = await history.exportRedactedJSON(salt: UUID().uuidString,
                timeout: max(0, min(0.7, deadline - uptime()))) else { throw IPCError.unavailable }
            return data
        }
        if command == .start { return try JSONEncoder().encode(await startFromControl(payload)) }
        guard command == .configSet else { return try handleControl(command, payload: payload) }
        _ = try BoundedPayload(payload)
        let options = try JSONDecoder().decode(CLIOptions.self, from: payload)
        guard let raw = options.flags["patchJSON"] else { throw IPCError.invalidInput("missingPatch") }
        var context = CommandContext(historyStore: nil)
        context.config = config; context.revision = revision; context.session = session
        context.files["remote-patch"] = raw
        var sanitized = options; sanitized.flags["file"] = "remote-patch"
        let result = Commands.dispatch("config set", options: sanitized, context: &context)
        guard result.exitCode == 0, options.flags["dry-run"] == nil else { return try JSONEncoder().encode(result) }
        guard let dictionary = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { throw IPCError.invalidInput("invalidPatch") }
        let patch = try ConfigPatch(jsonDictionary: dictionary)
        switch await applySettingsPatchAsync(patch, expectedRevision: revision, deadline: deadline) {
        case .saved: return try JSONEncoder().encode(result)
        case .conflict:
            return try JSONEncoder().encode(CLIResult(json: "{\"schemaVersion\":1,\"accepted\":false,\"reason\":\"revisionConflict\"}", exitCode: 3))
        case .failed: throw IPCError.unavailable
        case .unconfirmed:
            return try JSONEncoder().encode(CLIResult(json: "{\"schemaVersion\":1,\"accepted\":false,\"reason\":\"commitUnconfirmed\",\"mayApplyLater\":true,\"readBackRequired\":true}", exitCode: 5))
        }
    }

    /// In-process observer metadata only; no provider/IPC producer can call this path.
    @discardableResult
    func receiveObservation(_ event: NormalizedEvent) throws -> String {
        guard AgentBadgeState.providers.contains(event.provider) else {
            throw IPCError.policyDenied("unsupportedObservedProvider")
        }
        let now = uptime()
        func matching() -> AgentTask? {
            agents.tasks(now: now).first {
                $0.sessionID == event.sessionID && $0.runID == event.runID && agents.provider(for: $0.id) == event.provider
            }
        }
        let stateBefore = matching()?.state
        let result = try agents.ingest(JSONEncoder().encode(event), now: now)
        if result == "applied", let task = agents.tasks(now: now).first(where: {
            $0.sessionID == event.sessionID && $0.runID == event.runID && agents.provider(for: $0.id) == event.provider
        }) {
            // A gap fill may apply a buffered terminal observation.
            let identity = EvidenceNormalizer.runKey(provider: event.provider,
                sessionID: event.sessionID, runID: event.runID) + "\0" + String(event.epoch)
            if task.evidenceKind != .process && (task.state == .working || task.state == .waiting) {
                exactTaskEpoch = identity
            }
            if task.evidenceKind != .process,
               task.state == .failed || (task.state == .completed && session?.requestedMode != .auto) {
                outcomeNotifications.emit(category: task.state == .failed ? .failure : .completion,
                    session: session?.id ?? "app", event: identity,
                    reason: "terminalEvidence", now: now)
            }
        }
        refresh()
        // Only a change is history: an unchanged state re-reported on every poll flooded Activity (20 521 of 21 489).
        if let stateAfter = matching()?.state, stateAfter != stateBefore {
            record(category: .stateTransition, newState: sessionStateForRecord(),
                   reasons: ["agentStateChanged", "\(event.provider):\(stateAfter.rawValue)"])
        }
        return result
    }

    func handleControl(_ command: AllowlistedCommand, payload: Data) throws -> Data {
        try requireControlAdmission(command)
        // Renewal and finish carry their own payloads, not CLIOptions, so they are handled before the options decode.
        if command == .renewCommand { return try JSONEncoder().encode(try renewCommandRun(payload)) }
        if command == .finishCommand { return try JSONEncoder().encode(try finishCommandRun(payload)) }
        _ = try BoundedPayload(payload)
        if command == .logsExport {
            // Real transport uses the ordered off-main read path above.
            throw IPCError.unavailable
        }
        let options = payload.isEmpty ? CLIOptions() : try JSONDecoder().decode(CLIOptions.self, from: payload)
        var context = CommandContext(historyStore: nil)
        context.config = config; context.revision = revision; context.session = session
        context.health = latestHealth; context.nowMonotonic = uptime()
        var result: CLIResult
        switch command {
        case .status, .doctor, .agentsList:
            latestHealth = currentHealth()
            let readiness = protectionReadiness()
            var object: [String: Any] = ["schemaVersion": 1, "available": true,
                "powerActuation": holdReconciler.leaseVerified(now: uptime()),
                "leaseVerified": holdReconciler.leaseVerified(now: uptime()),
                "backendVerified": holdReconciler.leaseVerified(now: uptime()),
                "configuredMode": config.mode.rawValue, "activeSessionMode": session?.requestedMode.rawValue as Any? ?? NSNull(),
                "closedLidPermit": closedLidPermit().statusCode,
                "keepAwakeApps": helper.keepAwakeApps.map { ["name": $0.name, "resetsSleepSetting": $0.resetsSleepSetting] },
                "restoration": holdReconciler.status == .inactive && holdReconciler.restoration == .verified
                    ? "noPowerResourcesOwned" : "\(holdReconciler.restoration)",
                "mode": config.mode.rawValue, "effectiveState": readiness.state.rawValue, "policyState": sessionStateForRecord().rawValue,
                "revision": revision, "reasonCodes": readiness.blockerCodes,
                "settingsCommitPending": hasPendingSettingsWork,
                "historyError": history.lastError as Any? ?? NSNull(),
                "omittedHistoryRecords": omittedHistoryRecords,
                "deferredHistoryRecords": terminationDeferredHistory.count,
                "toolDiagnostic": NSNull()]
            updates.refreshSafety()
            object["batteryModeActive"] = session != nil && config.batteryModeAllowed && !config.chargingOnly && latestHealth?.powerSource == .battery
            object["agentSourceLimitations"] = ["observation": "externalOSMetadataAndReadOnlyOrcaMetadata", "setupRequired": false,
                "providerConnections": config.orcaMetadataAllowed, "providerEventsAccepted": false,
                "processScanCompleteAndFresh": uptime() - lastProcessSuccess <= 15,
                "standaloneTurnLifecycle": "unknown", "remoteWork": "unverified", "processPresenceProvesWork": false] as [String: Any]
            object["orcaUIObservation"] = ["source": "removedAccessibilitySource",
                "lastIssue": orcaUIIssue as Any? ?? NSNull(), "qualification": "removed",
                "completionCoverageQualified": false, "providerConnection": false,
                "permissionPrompted": permissions.promptRequested ? NSNull() as Any : false,
                "permissionPromptRequested": permissions.promptRequested,
                "permissionState": permissions.accessibility,
                "readDiagnostics": ["stage": orcaUIReadDiagnostics.stage,
                    "nodesVisited": orcaUIReadDiagnostics.nodesVisited,
                    "axError": orcaUIReadDiagnostics.axError as Any? ?? NSNull(),
                    "arrayCount": orcaUIReadDiagnostics.arrayCount as Any? ?? NSNull(),
                    "ancestorPath": orcaUIReadDiagnostics.ancestorPath.map {
                        ["depth": $0.depth, "role": $0.role, "frame": $0.frame as Any? ?? NSNull()] as [String: Any]
                    }]] as [String: Any]
            object["orcaMetadataObservation"] = ["source": "readOnlyOrcaCLI", "enabled": config.orcaMetadataAllowed,
                "lastIssue": orcaMetadataIssue, "queryReceiptAgeSeconds": lastOrcaMetadataSuccess.isFinite ? max(0, uptime() - lastOrcaMetadataSuccess) as Any : NSNull(),
                "sourceStateFreshness": "unverified", "completionCoverageQualified": false,
                "mixedJSONTransientMemory": true, "contentSavedOrSentToAI": false] as [String: Any]
            object["orcaUIStructureSurvey"] = try orcaUISurvey.map {
                try JSONSerialization.jsonObject(with: JSONEncoder().encode($0))
            } ?? NSNull()
            object["permissions"] = ["accessibility": permissions.accessibility,
                "notifications": outcomeNotifications.permissionState,
                "settingsError": permissions.settingsError as Any? ?? NSNull()] as [String: Any]
            object["evidenceCapacity"] = ["holdingTasks": allObservedTasks(now: uptime()).filter { PolicyEngine.holdsSession($0, now: uptime()) }.count,
                "maxHoldingTasks": PolicyLimits.maxEnrolledTasks, "trackedRuns": agents.trackedRunCount,
                "retiredRuns": agents.retiredRunCount, "lastRejection": agents.lastRejection as Any? ?? NSNull()] as [String: Any]
            object["agentDetection"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(badgeStates()))
            object["keepAwake"] = ["held": keepAwake.held, "verified": keepAwake.verified,
                "issue": keepAwake.issue as Any? ?? NSNull()] as [String: Any]
            object["shortcut"] = ["keys": "control-option-command-K", "registered": shortcut.isRegistered]
            var protection = try JSONSerialization.jsonObject(with: JSONEncoder().encode(readiness)) as! [String: Any]
            protection["readinessState"] = protection.removeValue(forKey: "state")
            object["protection"] = protection
            object["updates"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(updates.snapshot))
            if let latestHealth {
                var health = try JSONSerialization.jsonObject(with: JSONEncoder().encode(latestHealth)) as! [String: Any]
                var temperature = try JSONSerialization.jsonObject(with: JSONEncoder().encode(latestHealth.temperature)) as! [String: Any]
                temperature["ageSeconds"] = latestHealth.temperature.sampledAtMonotonic.map { max(0, uptime() - $0) } as Any? ?? NSNull()
                health["temperature"] = temperature
                if var lid = health["lid"] as? [String: Any] {
                    lid["ageSeconds"] = latestHealth.lid?.sampledAtMonotonic.map { max(0, uptime() - $0) } as Any? ?? NSNull()
                    health["lid"] = lid
                }
                object["health"] = health
            }
            if let session { object["session"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) }
            object["tasks"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(allObservedTasks(now: uptime())))
            result = CLIResult(json: String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self), exitCode: 0)
        case .admitCommand:
            throw IPCError.invalidInput("admitIsAsync")   // handled by `handleControlAsync` → `admitCommandRun`
        case .sleep:
            guard options.positionals.isEmpty, Set(options.flags.keys).isSubset(of: ["json", "dry-run"]),
                  options.flags.values.allSatisfy({ $0 == "true" }) else { throw IPCError.invalidInput("invalidSleepOptions") }
            let display = LiveSensorProvider.displayObservation()
            let input = LiveSensorProvider.recentInputObservation()
            let health = currentHealth()
            let now = uptime()
            let tasks = sleepRelevantTasks(now: now)
            let lifetime = updateLifetimePolicy(now: now)
            let lifetimeContributes = session.map {
                $0.requestedMode == .auto && !$0.latchedSafetyStop
                    && [.ready, .protected, .completionGrace].contains($0.effectiveState)
            } ?? false
            let decision = GuardedSleepDecision.evaluate(now: now,
                observedAt: health.lid?.sampledAtMonotonic ?? .nan, lid: health.lidState,
                displaysObservedAt: display.sampledAtMonotonic, displays: display.state,
                inputObservedAt: input.sampledAtMonotonic, idleSeconds: input.idleSeconds,
                workActive: tasks.contains { [.working, .waiting].contains($0.state) }
                    || (lifetimeContributes && lifetime?.hasActiveRule == true),
                workUnknown: tasks.contains { $0.state == .unknown } || (lifetimeContributes
                    && (lifetime?.hasUnknownHold == true || lifetime?.suppressesAutoCompletion == true || lifetime == nil))
                    || now - lastProcessSuccess > 5 || agentCompletionUncertain(),
                restore: .verified, backendVerified: false)
            if options.flags["dry-run"] == nil, !decision.eligible {
                record(category: .stateTransition, newState: sessionStateForRecord(),
                    reasons: ["sleepBlocked"] + decision.blockers)
            }
            let data = try JSONEncoder().encode(decision)
            result = CLIResult(json: String(decoding: data, as: UTF8.self), exitCode: decision.eligible ? 0 : 3)
        case .configGet:
            result = Commands.dispatch("config get", options: options, context: &context)
        case .configSet:
            guard let patch = options.flags["patchJSON"] else { throw IPCError.invalidInput("missingPatch") }
            context.files["remote-patch"] = patch
            var sanitized = options; sanitized.flags["file"] = "remote-patch"
            result = Commands.dispatch("config set", options: sanitized, context: &context)
            if result.exitCode == 0, options.flags["dry-run"] == nil {
                guard persistConfig(context.config) else { throw IPCError.unavailable }
                record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configApplied"])
                refresh()
            }
        case .start:
            throw IPCError.invalidInput("startIsAsync")   // handled by `handleControlAsync` → `startFromControl`
        case .quit:
            // Closing the hold connection makes the helper restore the sleep setting.
            let cleanup = releaseHoldForQuit()
            record(category: .configuration, newState: .off, reasons: ["cliQuit", cleanup])
            // AppKit's terminateLater loop must not nest inside a main-dispatch
            // callback: that blocks the main-actor cleanup task from replying.
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0.2)
            result = CLIResult(json: "{\"schemaVersion\":1,\"accepted\":true,\"powerActuation\":false,\"cleanupOutcome\":\"\(cleanup)\"}", exitCode: 0)
        case .stop:
            let hadSession = session != nil
            let held = holdReconciler.status == .held
            menuBarStopProtection()
            // With a held lease the release is sent on the next tick; `status` shows `restoration` when it lands.
            let cleanup = held ? "releaseRequested" : "noPowerResourcesOwned"
            result = CLIResult(json: "{\"schemaVersion\":1,\"released\":\(hadSession),\"cleanupOutcome\":\"\(cleanup)\"}", exitCode: 0)
        default: throw IPCError.policyDenied("commandNotAvailable")
        }
        return try JSONEncoder().encode(result)
    }

    /// `camlid start [--mode auto|timed|manual] [--duration 30m]`: the same path as the Dashboard buttons, so every
    /// refusal (mode, battery entry, closed-lid permit) applies. Power is held only later, once the helper confirms.
    func startFromControl(_ payload: Data) async -> CLIResult {
        func reply(_ code: Int, _ object: [String: Any]) -> CLIResult {
            var merged = object; merged["schemaVersion"] = 1; merged["command"] = "start"
            let data = (try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])) ?? Data()
            return CLIResult(json: String(decoding: data, as: UTF8.self), exitCode: code)
        }
        let options = payload.isEmpty ? CLIOptions() : ((try? JSONDecoder().decode(CLIOptions.self, from: payload)) ?? CLIOptions())
        var mode: RequestedMode?
        if let raw = options.flags["mode"] {
            guard let parsed = RequestedMode(rawValue: raw), parsed != .off else {
                return reply(2, ["accepted": false, "reason": "invalidMode"])
            }
            mode = parsed
        }
        var minutes: Int?
        if let raw = options.flags["duration"] {
            let value = raw.hasSuffix("h") ? Double(raw.dropLast()).map { $0 * 60 }
                : raw.hasSuffix("m") ? Double(raw.dropLast()) : Double(raw)
            guard let value, value.isFinite, value >= 1, value <= 24 * 60 else { return reply(2, ["accepted": false, "reason": "invalidDuration"]) }
            minutes = Int(value)
        }
        guard session == nil else { return reply(3, ["accepted": false, "reason": "sessionAlreadyActive"]) }
        // The requested mode applies to this session only. The saved mode changes only through `config set`.
        await startPreviewSession(mode: mode)
        guard let active = session else {
            let reason: String = if authorityUnavailable { "appUnavailable" }
                else if terminationFlowActive { "applicationTerminating" }
                else if (mode ?? config.mode) == .off { "modeOff" }
                else if config.closedLidOptIn && !closedLidAllowed { "closedLidNotPermitted" }
                else { config.batteryEntryRefusal(health: currentHealth()) ?? "notStarted" }
            return reply(3, ["accepted": false, "reason": reason, "detail": refusalNotice ?? NSNull()])
        }
        if let minutes, active.requestedMode == .timed { _ = changeTimerDuration(minutes, expectedRevision: revision) }
        return reply(0, ["accepted": true, "mode": active.requestedMode.rawValue,
            "effectiveState": (session ?? active).effectiveState.rawValue,
            "closedLid": config.closedLidOptIn, "closedLidPermit": closedLidPermit().statusCode,
            "powerMode": config.powerMode.rawValue,
            "powerActuation": holdReconciler.leaseVerified(now: uptime()),
            "note": "Power is held once the helper confirms; check `camlid status` for leaseVerified."])
    }

    // MARK: - camlid run admissions (ADR 0006)

    /// Admits one `camlid run` command. An Auto session starts when none runs, and the admitted command then counts as
    /// work, so the session stays protected until the command finishes.
    private func admitCommandRun(_ payload: Data) async throws -> Data {
        let request = try JSONDecoder().decode(AdmitCommandRequest.self, from: payload)
        try request.validate()
        guard !authorityUnavailable, !terminationFlowActive else { throw IPCError.unavailable }
        if session == nil {
            await startPreviewSession(mode: .auto)
            guard session != nil else {
                return try JSONEncoder().encode(commandRefusal(config.batteryEntryRefusal(health: currentHealth()) ?? "sessionNotStarted"))
            }
        }
        // The backend is verified before admission: the lid-open assertion must be held and read back.
        keepAwake.reconcile(wanted: true, now: uptime())
        do {
            let receipt = try commandAdmissions.admit(
                label: request.label, session: session, uid: getuid(), bootID: instanceID,
                generation: instanceGeneration, backendVerified: commandBackendVerified(),
                safetyClear: commandSafetyClear(), now: uptime())
            record(category: .enrollment, newState: sessionStateForRecord(), reasons: ["commandStarted"])
            refresh()
            let json = String(decoding: try JSONEncoder().encode(receipt), as: UTF8.self)
            return try JSONEncoder().encode(CLIResult(json: json, exitCode: 0))
        } catch let error as IPCError {
            guard case .policyDenied(let reason) = error else { throw error }
            return try JSONEncoder().encode(commandRefusal(reason))
        }
    }

    /// Renews an admission. A receipt whose session has ended, or whose safety stop latched, is refused with its reason.
    private func renewCommandRun(_ payload: Data) throws -> CLIResult {
        let request = try JSONDecoder().decode(RenewCommandRequest.self, from: payload)
        do {
            let next = try commandAdmissions.renew(
                request.receipt, session: session, uid: getuid(), bootID: instanceID, generation: instanceGeneration,
                backendVerified: commandBackendVerified(), safetyClear: commandSafetyClear(), now: uptime())
            return CLIResult(json: String(decoding: try JSONEncoder().encode(next), as: UTF8.self), exitCode: 0)
        } catch let error as IPCError {
            guard case .policyDenied(let reason) = error else { throw error }
            return commandRefusal(reason)
        }
    }

    /// A refused admission call. The reason travels in the reply, as `camlid start` replies do, not as a thrown error,
    /// because the wire keeps only the denial class.
    private func commandRefusal(_ reason: String) -> CLIResult {
        CLIResult(json: "{\"schemaVersion\":1,\"accepted\":false,\"reason\":\"\(reason)\"}", exitCode: 3)
    }

    /// Finishes an admission and records how the command ended. The session then winds down through grace.
    private func finishCommandRun(_ payload: Data) throws -> CLIResult {
        let request = try JSONDecoder().decode(FinishCommandRequest.self, from: payload)
        try commandAdmissions.finish(
            request.receipt, uid: getuid(), bootID: instanceID, generation: instanceGeneration, now: uptime())
        var reasons = ["commandFinished"]
        if let exitStatus = request.exitStatus { reasons.append("exitStatus:\(exitStatus)") }
        if let seconds = request.durationSeconds { reasons.append("durationSeconds:\(Int(seconds.rounded()))") }
        record(category: .enrollment, newState: sessionStateForRecord(), reasons: reasons)
        refresh()
        return CLIResult(json: "{\"schemaVersion\":1,\"accepted\":true}", exitCode: 0)
    }

    /// The backend a command needs: the lid-open assertion held and read back, or a verified closed-lid lease.
    private func commandBackendVerified() -> Bool {
        keepAwake.verified || holdReconciler.leaseVerified(now: uptime())
    }

    private func commandSafetyClear() -> Bool {
        !(session?.latchedSafetyStop ?? true)
    }

    /// An admitted command counts as work for an Auto session (ADR 0006). Expired admissions are dropped here.
    private func commandHoldReason(now: Double) -> String? {
        commandAdmissions.expire(now: now)
        return commandAdmissions.count > 0 ? "commandRunning" : nil
    }

    // MARK: - Config persistence (validated; never silently arms)

    private func requireControlAdmission(_ command: AllowlistedCommand) throws {
        if terminationFlowActive && ![.status, .doctor, .agentsList, .configGet, .logsExport].contains(command) {
            throw IPCError.policyDenied("applicationTerminating")
        }
        guard ![.event, .agentDiagnostic, .run].contains(command) else {
            throw IPCError.policyDenied("externalObservationOnly")
        }
    }

    @discardableResult
    private func persistConfig(_ candidate: Configuration) -> Bool {
        guard !authorityUnavailable, !terminationFlowActive, !hasPendingSettingsInstallation, revision < Int.max else { return false }
        let nextRevision = revision + 1
        let snapshot = PersistedSettings(schemaVersion: PersistedSettings.currentSchemaVersion, revision: nextRevision, configuration: candidate)
        do {
            try candidate.validate()
            try settingsWriter(JSONEncoder().encode(snapshot), configURL)
        } catch {
            refusalNotice = "Settings could not be saved. Last applied values retained."
            record(category: .configuration, newState: sessionStateForRecord(), reasons: ["configWriteFailed"])
            return false
        }
        acceptPersistedConfig(candidate, nextRevision: nextRevision)
        return true
    }

    private func acceptPersistedConfig(_ candidate: Configuration, nextRevision: Int) {
        let changedLogin = config.launchAtLogin != candidate.launchAtLogin
        let sourceChanged = config.orcaMetadataAllowed != candidate.orcaMetadataAllowed
        config = candidate; revision = nextRevision
        if sourceChanged {
            orcaMetadataEpoch = UUID()
            invalidateOrcaMetadata(issue: candidate.orcaMetadataAllowed ? "orcaMetadataNotObserved" : "orcaObservationDisabled")
            lastOrcaMetadataPoll = -Double.infinity
        }
        outcomeNotifications.configure(categories: candidate.notificationCategories ?? [])
        if changedLogin { loginItem.apply(candidate.launchAtLogin) }
        if config.mode == .off, session != nil {
            record(category: .stateTransition, newState: .off, reasons: ["modeOff"]); session = nil
        } else if var active = session, active.requestedMode != config.mode {
            sessionTimerMinutes = config.timedDurationMinutes == 0
                ? 0 : min(config.timedDurationMinutes, timerMaximumMinutes(now: uptime()))
            sessionSleepDelayMinutes = config.completionDelayMinutes
            if config.sessionDurationMinutes(for: config.mode) == nil {
                active.capDeadlineMonotonic = nil
            } else if active.capDeadlineMonotonic == nil {
                active.capDeadlineMonotonic = config.sessionDurationMinutes(for: config.mode)
                    .map { active.startedAtMonotonic + Double($0) * 60 }
            } else if config.mode == .timed, active.requestedMode != .timed,
                      let minutes = config.sessionDurationMinutes(for: .timed),
                      let deadline = active.capDeadlineMonotonic {
                active.capDeadlineMonotonic = min(deadline, active.startedAtMonotonic + Double(minutes) * 60)
            }
            active.requestedMode = config.mode; session = active
        }
        // Selection affects sleep policy only; passive observations stay visible.
    }

    private static func readPrivatePreferences(_ url: URL) -> Data? {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
              (info.st_mode & S_IFMT) == S_IFREG, (info.st_mode & 0o077) == 0,
              info.st_size > 0, info.st_size <= 65_536 else { return nil }
        var data = Data(count: Int(info.st_size))
        let count = data.withUnsafeMutableBytes { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count)
        }
        guard count == data.count else { return nil }
        return data
    }

    private func loadPersistedConfig() {
        var metadata = stat()
        let hasEntry = lstat(configURL.path, &metadata) == 0
        let missingEntry = !hasEntry && errno == ENOENT
        if !hasEntry && !missingEntry {
            refusalNotice = "Saved settings could not be inspected. Using safe defaults."; return
        }
        // lstat sees dangling symlinks too: an unreadable authoritative entry
        // must never silently resurrect an older UserDefaults configuration.
        if hasEntry || preferences.data(forKey: "CamLidConfigurationV2") != nil {
            let data = hasEntry ? Self.readPrivatePreferences(configURL) : preferences.data(forKey: "CamLidConfigurationV2")
            guard let data else {
                refusalNotice = "Saved settings could not be read. Using safe defaults."; return
            }
            guard let saved = PersistedSettings.validated(data) else {
                refusalNotice = "Saved settings were invalid, so CamLid uses safe defaults."
                return
            }
            config = saved.configuration; revision = saved.revision
            return
        }
        guard let data = preferences.data(forKey: Self.configKey) else { return }
        guard let decoded = try? JSONDecoder().decode(Configuration.self, from: data),
            (try? decoded.validate()) != nil else {
            refusalNotice = "Saved settings were invalid, so CamLid uses safe defaults."
            return
        }
        config = decoded
        revision = max(1, preferences.integer(forKey: "CamLidConfigRevision"))
    }

    // MARK: - History

    private func record(category: ActivityCategory, newState: EffectiveState, reasons: [String]) {
        // A duplicate UI owns neither the control authority nor shared history.
        guard !authorityUnavailable, !terminationConfirmed else { return }
        guard let transition = try? StoredTransition(
            sessionID: session?.id,
            stateRevision: (session?.stateRevision ?? 0),
            category: category, previousState: lastReportedState, newState: newState,
            reasonCodes: reasons,
            healthSummary: latestHealth.map(HealthSummary.from) ?? .unknown)
        else { return }
        if terminationHistorySealed {
            // Preserve transitions on Keep Open. Normal quit never claims a
            // complete drain while any deferred transition remains.
            if terminationDeferredHistory.count < AsyncHistoryRecorder.maximumOutstandingOperations {
                terminationDeferredHistory.append(transition)
            } else if omittedHistoryRecords < Int.max { omittedHistoryRecords += 1 }
            return
        }
        if !history.record(transition), omittedHistoryRecords < Int.max { omittedHistoryRecords += 1 }
        let alertCategory: NotificationCategory? = category == .safetyStop ? .safety
            : newState == .recoveryRequired ? .restoration
            : newState == .ready && reasons.contains("graceExpired") ? .completion : nil
        if let alertCategory {
            outcomeNotifications.emit(category: alertCategory, session: session?.id ?? "app", event: transition.id.uuidString,
                reason: reasons.first ?? "stateChanged", now: uptime())
        }
    }
}

private func uncheckedDefaultConfig() -> Configuration {
    // try? Configuration() cannot fail (defaults are valid); this is unreachable.
    // swiftlint:disable:next force_try
    try! Configuration()
}

private final class ControlReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private let timeout: Double
    init(timeout: Double = 0.9) { self.timeout = timeout }
    private var result: Result<Data, any Error>?
    func finish(_ result: Result<Data, any Error>) {
        lock.lock(); self.result = result; lock.unlock(); ready.signal()
    }
    func wait() throws -> Data {
        guard ready.wait(timeout: .now() + timeout) == .success else { throw IPCError.unavailable }
        lock.lock(); defer { lock.unlock() }
        guard let result else { throw IPCError.unavailable }
        return try result.get()
    }
}

// Explicit session edits; routine policy evaluation never renews a deadline.
extension ProtectionSession {
    mutating func restartTimer(minutes: Int, maximumMinutes: Int, now: Double) -> Int? {
        guard requestedMode == .timed || requestedMode == .manual,
              !latchedSafetyStop, effectiveState != .expired,
              capDeadlineMonotonic.map({ now < $0 }) ?? true,
              minutes == 0 || (5...480).contains(minutes) else { return nil }
        let duration = minutes == 0 ? 0 : min(minutes, maximumMinutes)
        capDeadlineMonotonic = duration == 0 ? nil : now + Double(duration) * 60
        return duration
    }

    mutating func changeSleepDelay(minutes: Int, previousMinutes: Int) -> Bool {
        guard requestedMode == .auto, !latchedSafetyStop, effectiveState != .expired,
              (0...30).contains(minutes) else { return false }
        if let deadline = graceDeadlineMonotonic {
            // Keep measuring from completion when editing during grace.
            graceDeadlineMonotonic = deadline - Double(previousMinutes) * 60 + Double(minutes) * 60
        }
        return true
    }
}
