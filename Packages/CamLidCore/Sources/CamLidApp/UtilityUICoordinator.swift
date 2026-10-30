import AppKit
import SwiftUI
import Combine
import CamLidCore

/// Displays projections supplied by the persistent coordinator. This process
/// owns no policy timers, history storage, control listener or power resource.
@MainActor
public final class UtilityUICoordinator: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var pipe: UtilityUIPipe?
    private var state: UtilityUIState?
    private var diagnosticReads: [UUID: CheckedContinuation<DiagnosticSnapshot, Never>] = [:]
    private var commits: [UUID: CheckedContinuation<SettingsCommitResult, Never>] = [:]
    private var popover: NSPopover?
    private var dashboardHost: NSHostingController<DashboardView>?
    private var dismissal: DashboardDismissal?
    private var anchorWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var settingsEditor: SettingsEditor?
    private var editorObservation: AnyCancellable?
    private var closeGuard: SettingsCloseGuard?
    private var toolbar: SettingsToolbar?
    private var activityWindow: NSWindow?
    private var activity = ActivitySnapshot()
    private var historyInitiallySized = false
    private var onboardingWindow: NSWindow?
    private var updatesWindow: NSWindow?
    private var sleepDiagnosticsWindow: NSWindow?
    private var onboardingRequest: (id: UUID, continuation: CheckedContinuation<Bool, Never>)?
    private var acceptingQuit = false
    private var quitAfterSettingsClose = false
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMenu()
        pipe = UtilityUIPipe(input: .standardInput, output: .standardOutput, receive: { [weak self] data in
            guard let self, let command = try? JSONDecoder().decode(UtilityUICommand.self, from: data) else { return }
            self.receive(command)
        }, closed: { [weak self] in
            guard let self else { return }
            for continuation in self.commits.values { continuation.resume(returning: .failed("App unavailable. Input preserved.")) }
            self.commits.removeAll()
            for continuation in self.diagnosticReads.values { continuation.resume(returning: DiagnosticSnapshot(errors: ["appUnavailable"])) }
            self.diagnosticReads.removeAll()
            if let request = self.onboardingRequest { self.resolveOnboarding(request.id, completed: false) }
            self.acceptingQuit = true; NSApp.terminate(nil)
        })
    }
    public func applicationDidBecomeActive(_ notification: Notification) {
        if settingsWindow?.isVisible == true { visibilityChanged() }
    }
    private func receive(_ command: UtilityUICommand) {
        switch command {
        case .show(let surface, let state):
            update(state)
            switch surface {
            case .dashboard: dashboard(show: true)
            case .settings: showSettings()
            case .sleepDiagnostics: showSleepDiagnostics(); popover?.performClose(nil)
            case .activity: showHistory(show: true)
            case .onboarding: showOnboarding()
            case .updates:
                showUpdates(); popover?.performClose(nil)
            }
        case .diagnostics(let id, let snapshot): diagnosticReads.removeValue(forKey: id)?.resume(returning: snapshot)
        case .update(let state): update(state)
        case .closeDashboard: popover?.performClose(nil)
        case .commitResult(let id, let result): commits.removeValue(forKey: id)?.resume(returning: result)
        case .prepareToQuit: NSApp.terminate(nil)
        case .exportData(let data): exportHistory(data)
        case .historyLoading(let id):
            guard activityWindow != nil else { return }
            activity.beginRead(id); showHistory(show: false)
        case .history(let id, let records, let error, let outcome):
            if activityWindow != nil, activity.completeRead(id, records: records, error: error, outcome: outcome) {
                showHistory(show: false)
            }
        case .onboardingResult(let id, let completed): resolveOnboarding(id, completed: completed)
        }
    }
    func update(_ state: UtilityUIState) {
        self.state = state
        settingsEditor?.receive(configuration: state.configuration, revision: state.revision)
        settingsEditor?.installationPending = state.installationPending
        settingsEditor?.badges = state.dashboard.agents
        settingsEditor?.protection = state.protection
        settingsEditor?.loginState = state.loginState; settingsEditor?.loginMessage = state.loginMessage
        settingsEditor?.helperState = state.helperState; settingsEditor?.helperMessage = state.helperMessage
        settingsEditor?.helperBusy = state.helperBusy
        settingsEditor?.notificationPermission = state.notificationPermission
        settingsEditor?.accessibilityPermission = state.accessibilityPermission
        settingsEditor?.permissionSettingsError = state.permissionSettingsError
        if popover?.isShown == true { dashboard(show: false) }
        if onboardingWindow?.isVisible == true { showOnboarding(show: false) }
        if updatesWindow?.isVisible == true { showUpdates(show: false) }
        if let menu = NSApp.mainMenu?.items.first?.submenu {
            menu.item(withTag: 1)?.state = state.dashboard.stopEnabled && state.dashboard.mode == .auto ? .on : .off
            menu.item(withTag: 2)?.isHidden = !state.dashboard.stopEnabled
        }
        NSApp.mainMenu?.update()
    }
    private func send(_ event: UtilityUIEvent) { _ = pipe?.send(event) }
    private func activateMode(_ mode: RequestedMode) {
        guard let state else { return }
        send(.activateMode(mode, state.revision))
    }
    private func commit(_ patch: ConfigPatch, revision: Int) async -> SettingsCommitResult {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            commits[id] = continuation
            if pipe?.send(UtilityUIEvent.commit(id, patch, revision)) != true {
                commits.removeValue(forKey: id)?.resume(returning: .failed("App unavailable. Input preserved."))
            }
        }
    }
    private func dashboard(show: Bool) {
        guard let state else { return }
        let view = DashboardView(data: state.dashboard,
            onOpenLog: { [weak self] in self?.send(.activity) },
            onClose: { [weak self] in self?.send(.restoreStatusFocus); self?.popover?.performClose(nil) },
            onModeChange: { [weak self] mode in
                self?.activateMode(mode)
            },
            durationMinutes: state.dashboard.timerMinutes ?? state.configuration.timedDurationMinutes,
            onDurationChange: { [weak self] minutes in
                guard let self, let state = self.state else { return }
                self.send(.timerDuration(minutes, state.revision))
            }, maximumDurationMinutes: state.dashboard.timerMaximumMinutes ?? state.configuration.runCapMinutes,
            sleepDelayMinutes: state.dashboard.sleepDelayMinutes ?? state.configuration.completionDelayMinutes,
            onSleepDelayChange: { [weak self] minutes in
                guard let self, let state = self.state else { return }
                self.send(.sleepDelay(minutes, state.revision))
            },
            onOpenAgents: { [weak self] in self?.send(.settings(.agents)) })
        if let host = dashboardHost { host.rootView = view }
        else { dashboardHost = NSHostingController(rootView: view) }
        dashboardHost?.sizingOptions = []
        dashboardHost?.safeAreaRegions = []
        if popover == nil {
            // A transparent anchor maps the persistent process's status button
            // frame into this process. It has no input or visible surface.
            let anchor = NSWindow(contentRect: state.anchorFrame, styleMask: .borderless, backing: .buffered, defer: false)
            anchor.isReleasedWhenClosed = false; anchor.alphaValue = 0
            anchor.ignoresMouseEvents = true; anchor.level = .statusBar
            anchor.contentView = NSView(frame: NSRect(origin: .zero, size: state.anchorFrame.size))
            anchor.orderFront(nil); anchorWindow = anchor
            let popup = NSPopover(); popup.animates = false; popover = popup
            dismissal = DashboardDismissal(popover: popup, anchor: nil, externalAnchorFrame: state.anchorFrame) { [weak self] in
                guard let self else { return }
                self.dashboardHost = nil; self.popover = nil; self.dismissal = nil
                self.anchorWindow?.close(); self.anchorWindow = nil
                self.send(.restoreStatusFocus)
                self.visibilityChanged()
            }
        }
        if popover?.contentViewController !== dashboardHost { popover?.contentViewController = dashboardHost }
        resizeDashboard()
        if show, let anchor = anchorWindow?.contentView {
            NSApp.activate(ignoringOtherApps: true)
            popover?.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            // The transparent, non-key anchor cannot transfer keyboard focus.
            // Explicitly focus the presented surface, never a timer refresh.
            if let window = dashboardHost?.view.window {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(dashboardHost?.view)
            }
            dismissal?.start(); visibilityChanged()
        }
    }
    private func resizeDashboard() {
        guard let dashboardHost else { return }
        let area = anchorWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        popover?.contentSize = dashboardHost.dashboardContentSize(
            width: min(390, max(260, area.width - 24)), maximumHeight: max(140, area.height - 48))
    }
    private func showSettings() {
        guard let state else { return }
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil); visibilityChanged(); return
        }
        let editor = SettingsEditor(configuration: state.configuration, revision: state.revision, section: state.settingsSection)
        settingsEditor = editor; editor.installationPending = state.installationPending
        editorObservation = editor.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.send(.editorState(dirty: self.settingsEditor?.isDirty == true))
            }
        }
        editor.badges = state.dashboard.agents; editor.protection = state.protection
        editor.loginState = state.loginState; editor.loginMessage = state.loginMessage
        editor.helperState = state.helperState; editor.helperMessage = state.helperMessage; editor.helperBusy = state.helperBusy
        editor.onInstallHelper = { [weak self] in self?.send(.installHelper) }
        editor.onUninstallHelper = { [weak self] in self?.send(.uninstallHelper) }
        editor.notificationPermission = state.notificationPermission
        editor.accessibilityPermission = state.accessibilityPermission
        editor.permissionSettingsError = state.permissionSettingsError
        editor.onAuthorizeAccessibility = { [weak self] in self?.send(.authorizeAccessibility) }
        editor.onOpenAccessibilitySettings = { [weak self] in self?.send(.openPermissionSettings(.accessibility)) }
        editor.onOpenNotificationSettings = { [weak self] in self?.send(.openPermissionSettings(.notifications)) }
        editor.onRefreshPermissions = { [weak self] in self?.send(.refreshPermissions) }
        editor.onAuthorizeNotifications = { [weak self] in self?.send(.authorizeNotifications) }
        editor.onApplyLogin = { [weak self] in self?.send(.applyLoginPreference) }
        editor.configureAsyncAutosave { [weak self] patch, revision in
            await self?.commit(patch, revision: revision) ?? .failed("App unavailable. Input preserved.")
        }
        let view = SettingsView(editor: editor, statusSummary: "Power protection unavailable",
            onCommit: { _, _ in .failed("App unavailable. Draft preserved.") },
            onClose: { [weak self] in self?.settingsWindow?.performClose(nil) },
            onOpenActivityLog: { [weak self] in self?.send(.activity) },
            onSectionChange: { [weak self] section in self?.send(.section(section)); self?.toolbar?.select(section) }, showsPanePicker: false,
            onOpenSleepDiagnostics: { [weak self] in self?.send(.sleepDiagnostics) })
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false; window.title = "CamLid Settings"
        window.setContentSize(NSSize(width: 580, height: 540)); window.center()
        settingsWindow = window
        closeGuard = SettingsCloseGuard(editor: editor,
            installationPending: { [weak self] in self?.state?.installationPending ?? true },
            settleInstallation: { [weak self] in
                let end = ProcessInfo.processInfo.systemUptime + 2
                while self?.state?.installationPending == true, ProcessInfo.processInfo.systemUptime < end {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                return self?.state?.installationPending == false
            }, onClose: { [weak self] in
                guard let self else { return }
                self.settingsWindow = nil; self.closeGuard = nil; self.toolbar = nil; self.settingsEditor = nil
                self.editorObservation = nil; self.send(.editorState(dirty: false))
                if self.quitAfterSettingsClose {
                    self.send(.quitDecision(true)); self.acceptingQuit = true; NSApp.terminate(nil)
                } else { self.visibilityChanged() }
            }, onKeepOpen: { [weak self] in
                self?.quitAfterSettingsClose = false; self?.send(.quitDecision(false))
            })
        window.delegate = closeGuard; toolbar = SettingsToolbar(editor: editor, window: window)
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        visibilityChanged()
    }
    private func showHistory(show: Bool) {
        let view = ActivityLogView(transitions: activity.records, storageError: activity.error, outcome: activity.outcome,
            isLoading: activity.isLoading, onRefresh: { [weak self] in self?.send(.reloadHistory) },
            onExportRedacted: { [weak self] in self?.send(.exportHistory) },
            onDeleteSession: { [weak self] id in self?.send(.deleteHistory(id)) },
            onDeleteAll: { [weak self] in self?.send(.deleteHistory(nil)) }, onDeleteResult: { _ in })
        let height = ActivityLogView.preferredHeight(recordCount: activity.records.count, hasError: activity.error != nil)
        let needsInitialSize = activityWindow == nil || !historyInitiallySized
        present(view, title: "CamLid Activity", window: &activityWindow, width: 640, height: height, show: show)
        if needsInitialSize, !activity.isLoading, let activityWindow {
            activityWindow.setContentSize(NSSize(width: 640, height: height))
            historyInitiallySized = true
        }
    }
    private func exportHistory(_ data: Data) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "camlid-events.redacted.json"
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { self.send(.activityOutcome("Export canceled. No file was written.")); return }
            Task { @MainActor in
                let written = await Task.detached(priority: .utility) {
                    do { try data.write(to: url, options: .atomic); return true } catch { return false }
                }.value
                self.send(.activityOutcome(written ? "Redacted export saved to \(url.lastPathComponent)." : "Export failed. Choose a writable location and retry."))
            }
        }
    }
    private func showOnboarding(show: Bool = true) {
        guard let state else { return }
        let view = OnboardingView(agents: state.dashboard.agents, isObserving: !state.observationReady,
        onFinish: { [weak self] in
            guard let self else { return false }
            let completed = await self.completeOnboarding()
            if completed { self.onboardingWindow?.close() }
            return completed
        }, onCancel: { [weak self] in self?.send(.cancelOnboarding); self?.onboardingWindow?.close() })
        present(view, title: "Welcome to CamLid", window: &onboardingWindow, width: 520, height: OnboardingPage.welcome.preferredHeight, show: show)
    }
    private func completeOnboarding() async -> Bool {
        guard onboardingRequest == nil else { return false }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            onboardingRequest = (id, continuation)
            guard pipe?.send(UtilityUIEvent.finishOnboarding(id)) == true else {
                resolveOnboarding(id, completed: false); return
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.resolveOnboarding(id, completed: false)
            }
        }
    }
    private func resolveOnboarding(_ id: UUID, completed: Bool) {
        guard let request = onboardingRequest, request.id == id else { return }
        onboardingRequest = nil; request.continuation.resume(returning: completed)
    }
    private func readDiagnostics() async -> DiagnosticSnapshot {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            diagnosticReads[id] = continuation
            if pipe?.send(UtilityUIEvent.readDiagnostics(id)) != true {
                diagnosticReads.removeValue(forKey: id)?.resume(returning: DiagnosticSnapshot(errors: ["appUnavailable"]))
            }
        }
    }
    private func showSleepDiagnostics() {
        present(SleepDiagnosticsView(read: { [weak self] in await self?.readDiagnostics() ?? DiagnosticSnapshot(errors: ["appUnavailable"]) }), title: "Why is my Mac awake? · CamLid", window: &sleepDiagnosticsWindow, width: 600, height: 480)
    }
    private func showUpdates(show: Bool = true) {
        guard let state else { return }
        let view = UpdatesView(snapshot: state.updates, canCheck: state.canCheckUpdates,
                              onCheck: { [weak self] in self?.send(.checkUpdates) })
        present(view, title: "CamLid Updates", window: &updatesWindow, width: 460, height: view.preferredHeight, show: show)
    }
    private func present<Content: View>(_ view: Content, title: String, window: inout NSWindow?, width: CGFloat, height: CGFloat, show: Bool = true) {
        if let existing = window {
            if let host = existing.contentViewController as? NSHostingController<Content> { host.rootView = view }
            if show { existing.makeKeyAndOrderFront(nil) }; return
        }
        guard show else { return }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        let created = NSWindow(contentViewController: host)
        created.isReleasedWhenClosed = false; created.title = title; created.delegate = self
        created.setContentSize(NSSize(width: width, height: height)); created.center(); window = created
        NSApp.activate(ignoringOtherApps: true); created.makeKeyAndOrderFront(nil)
    }
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.contentView = nil
        if window === activityWindow { activityWindow = nil; activity = ActivitySnapshot(); historyInitiallySized = false }
        if window === onboardingWindow { onboardingWindow = nil }
        if window === updatesWindow { updatesWindow = nil }
        if window === sleepDiagnosticsWindow { sleepDiagnosticsWindow = nil }
        visibilityChanged()
    }
    private func visibilityChanged() {
        send(.visibility(dashboard: popover?.isShown == true, settings: settingsWindow?.isVisible == true))
        guard popover == nil, settingsWindow == nil, activityWindow == nil, onboardingWindow == nil, updatesWindow == nil, sleepDiagnosticsWindow == nil else { return }
        // End the helper immediately; no settling timer substitutes for release.
        acceptingQuit = true; NSApp.terminate(nil)
    }
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !acceptingQuit else { return .terminateNow }
        if let window = settingsWindow, window.attachedSheet != nil { send(.quitDecision(false)); return .terminateCancel }
        if settingsEditor?.isDirty == true || state?.installationPending == true {
            guard let window = settingsWindow else { send(.quitDecision(false)); return .terminateCancel }
            quitAfterSettingsClose = true
            // The same guard handles settling, unconfirmed installs, retry,
            // discard and cancellation for Cmd-W and whole-app termination.
            window.performClose(nil)
            return .terminateCancel
        }
        send(.quitDecision(true)); return .terminateNow
    }
    func installMenu() {
        let main = NSMenu(); let root = NSMenuItem(); main.addItem(root)
        let app = NSMenu(); root.submenu = app
        let dashboard = NSMenuItem(title: "Show Dashboard", action: #selector(openDashboard), keyEquivalent: "d"); dashboard.target = self; app.addItem(dashboard)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","); settings.target = self; app.addItem(settings)
        let start = NSMenuItem(title: "Auto", action: #selector(startPreview), keyEquivalent: ""); start.tag = 1; start.target = self; app.addItem(start)
        let stop = NSMenuItem(title: "Stop", action: #selector(stopPreview), keyEquivalent: "."); stop.tag = 2; stop.target = self; stop.isHidden = true; app.addItem(stop)
        let activity = NSMenuItem(title: "Activity Log…", action: #selector(openActivity), keyEquivalent: "l"); activity.target = self; app.addItem(activity)
        let diagnostics = NSMenuItem(title: "Why is my Mac awake?…", action: #selector(openSleepDiagnostics), keyEquivalent: ""); diagnostics.target = self; app.addItem(diagnostics)
        let welcome = NSMenuItem(title: "Welcome & Safety…", action: #selector(openWelcome), keyEquivalent: ""); welcome.target = self; app.addItem(welcome)
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(openUpdates), keyEquivalent: ""); updates.target = self; app.addItem(updates)
        let quit = NSMenuItem(title: "Quit CamLid", action: #selector(quitMain), keyEquivalent: "q"); quit.target = self; app.addItem(quit)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit; main.addItem(editItem)
        edit.addItem(withTitle: "Undo", action: Selector("undo:"), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        // Nil targets let the focused native editor handle and validate commands.
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"),
                                   ("Copy", #selector(NSText.copy(_:)), "c"),
                                   ("Paste", #selector(NSText.paste(_:)), "v"),
                                   ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: ""); let windows = NSMenu(title: "Window"); windowItem.submenu = windows; main.addItem(windowItem)
        windows.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = main; NSApp.windowsMenu = windows
    }
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.tag {
        case 1: state?.dashboard.startEnabled == true
        case 2: state?.dashboard.stopEnabled == true
        default: true
        }
    }
    @objc private func openSettings() { showSettings() }
    @objc private func openDashboard() { dashboard(show: true) }
    @objc private func startPreview() { activateMode(.auto) }
    @objc private func stopPreview() { send(.stop) }
    @objc private func openSleepDiagnostics() { send(.sleepDiagnostics) }
    @objc private func openActivity() { send(.activity) }
    @objc private func openWelcome() { send(.onboarding) }
    @objc private func openUpdates() { send(.updates) }
    @objc private func quitMain() { send(.quit) }
}
