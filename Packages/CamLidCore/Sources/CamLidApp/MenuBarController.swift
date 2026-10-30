import AppKit
import CamLidCore

/// Actions the host app provides. The controller owns no engine state and
/// performs no policy evaluation: it routes clicks/keys and reflects the
/// status it is given via `update(status:)`.
@MainActor
public protocol MenuBarActions: AnyObject {
    func menuBarStartProtection()
    func menuBarStopProtection()
    func menuBarOpenSettings()
    func menuBarOpenSleepDiagnostics()
    func menuBarOpenActivityLog()
    func menuBarOpenUpdates()
    func menuBarShowWelcome()
    func menuBarQuit()
    /// Whether Start/Stop items are currently meaningful (drives item enablement).
    var menuBarCanStart: Bool { get }
/// Whether Auto start is meaningful (needs a selected agent). Defaults true.
var menuBarAutoAvailable: Bool { get }
    var menuBarCanStop: Bool { get }
    var menuBarActiveMode: RequestedMode? { get }
}

/// Render model for the menu-bar item. Fed by Core types (EffectiveState);
/// unknown/unavailable renders WITHOUT a healthy tint and WITH an explicit
/// "Unknown" label — never as fake-healthy.
public extension MenuBarActions {
    var menuBarAutoAvailable: Bool { true }
    var menuBarActiveMode: RequestedMode? { nil }
    func menuBarOpenSleepDiagnostics() {}
    func menuBarOpenUpdates() {}
    func menuBarShowWelcome() {}
}

public struct MenuBarStatus: Sendable, Equatable {
    public let state: EffectiveState
    public let reasonText: String?
    public let leaseVerified: Bool
    /// Auto mode: true while any enabled agent reports work.
    public let agentWorking: Bool
    /// Timed/manual mode: live remaining seconds, or nil for Infinite.
    public let timerRemainingSeconds: Double?

    public init(state: EffectiveState, reasonText: String? = nil, leaseVerified: Bool = false,
                agentWorking: Bool = false, timerRemainingSeconds: Double? = nil) {
        self.state = state
        self.reasonText = reasonText
        self.leaseVerified = leaseVerified
        self.agentWorking = agentWorking
        self.timerRemainingSeconds = timerRemainingSeconds
    }

    /// MASTER: do not claim protected until the backend lease is verified.
    /// Protected-but-unverified renders as attention, not ok.
    public var tone: CamLidAccessibility.StatusTone {
        switch state {
        case .protected:
            return leaseVerified ? .ok : .attention
        case .completionGrace:
            return .attention
        case .safetyStopped, .expired, .recoveryRequired:
            return .stopped
        case .off, .ready, .unavailable:
            return .neutral
        }
    }

    public var symbolName: String {
        switch state {
        case .protected: return leaseVerified ? "shield.fill" : "shield"
        case .completionGrace: return "timer"
        case .safetyStopped, .expired: return "xmark.shield.fill"
        case .recoveryRequired: return "exclamationmark.triangle.fill"
        case .off: return "shield.slash"
        case .ready: return "shield"
        case .unavailable: return "questionmark.circle"
        }
    }

    public var accessibilityLabel: String {
        let reason: String?
        if state == .protected, !leaseVerified {
            reason = "protection unverified"
        } else {
            reason = reasonText
        }
        return CamLidAccessibility.Labels.statusLabel(for: presentedState, reason: reason)
    }

    public var presentedState: EffectiveState { state == .protected && !leaseVerified ? .unavailable : state }

    /// Notify assistive clients for important transitions once. Changes to
    /// countdowns/reasons and repeated evaluations do not announce again.
    public func shouldNotifyAccessibility(after previous: MenuBarStatus) -> Bool {
        guard presentedState != previous.presentedState else { return false }
        return [.protected, .completionGrace, .safetyStopped, .expired, .recoveryRequired].contains(presentedState)
    }
}

/// Compact live countdown rendered directly in the menu bar.
enum MenuBarCountdown {
    /// Finite remaining time as menu-bar text. Infinite sessions have no
    /// countdown and render the infinity glyph instead.
    static func text(remaining: Double?) -> String? {
        guard let remaining else { return nil }
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            // Above one hour, seconds are noise in the menu bar.
            return String(format: "%d:%02d", hours, minutes)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Left-click toggles the dashboard; right/Control-click closes it before
/// opening native options. Timer updates change labels without activation.
@MainActor
public final class MenuBarController: NSObject {
    /// Left-click target. The real app toggles the anchored NSPanel here.
    public var onToggleDashboard: (() -> Void)?
    public var onOpenOptions: (() -> Void)?

    public weak var actions: (any MenuBarActions)?

    private var statusItem: NSStatusItem?
    private var lastStatus = MenuBarStatus(state: .unavailable)
    private var renderedStatus: MenuBarStatus?
    private var renderedMode: RequestedMode?
    private var renderedTimerText: String?
    private var autoAnimationTimer: Timer?
    private var autoAnimationIndex = 0

    public override init() {
        super.init()
    }

    /// Creates the status item. Must be called on the main thread (enforced
    /// by @MainActor). Uses a template image so light/dark render natively.
    public func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        // System laptop template + accessible state
        // label; no permanent CPU/battery number clutter in the menu bar.
        button.image = CamLidStatusIcon.image(for: .neutral)
        button.target = self
        // Both buttons route through one selector; the NSEvent kind decides.
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityIdentifier(CamLidAccessibility.IDs.statusHeader)
        statusItem = item
        installApplicationMenu()
        update(status: lastStatus)
    }

    public func remove() {
        stopAutoAnimation()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        renderedStatus = nil
        renderedMode = nil
        renderedTimerText = nil
    }

    /// Reflects Core state in icon + label. Unknown stays untinted.
    public func update(status: MenuBarStatus) {
        let shouldNotify = status.shouldNotifyAccessibility(after: lastStatus)
        lastStatus = status
        guard let button = statusItem?.button else { return }
        if let menu = NSApp.mainMenu?.items.first?.submenu {
            menu.item(withTag: 1)?.isEnabled = (actions?.menuBarCanStart ?? false) && (actions?.menuBarAutoAvailable ?? false)
            menu.item(withTag: 1)?.state = actions?.menuBarActiveMode == .auto ? .on : .off
            menu.item(withTag: 2)?.isEnabled = actions?.menuBarCanStop ?? false
            menu.item(withTag: 2)?.isHidden = actions?.menuBarCanStop != true
        }
        let activeMode = actions?.menuBarActiveMode
        let isTimedSession = activeMode == .timed || activeMode == .manual
        let timerText = Self.timerText(for: activeMode, status: status)
        let showsInfinite = isTimedSession && status.tone != .stopped && status.timerRemainingSeconds == nil
        guard status != renderedStatus || activeMode != renderedMode || timerText != renderedTimerText else { return }
        renderedStatus = status
        renderedMode = activeMode
        renderedTimerText = timerText

        let autoWorking = activeMode == .auto && status.tone != .stopped && status.agentWorking
        if let timerText {
            // Timed/manual sessions replace the clock icon with the actual
            // remaining time, updating once per second.
            stopAutoAnimation()
            button.image = nil
            button.title = timerText
            button.imagePosition = .noImage
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.contentTintColor = nil
        } else if showsInfinite {
            // Infinite has no clock to show: use a native infinity glyph and
            // leave the title empty so no time counter appears.
            stopAutoAnimation()
            button.title = ""
            button.imagePosition = .imageOnly
            button.font = nil
            button.image = CamLidStatusIcon.infinityImage()
            button.contentTintColor = nil
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            button.font = nil
            if autoWorking {
                button.contentTintColor = .white
                startAutoAnimation()
            } else {
                stopAutoAnimation()
                let iconMode: RequestedMode? = activeMode == .auto ? .auto : nil
                button.image = CamLidStatusIcon.image(for: status.tone, activeMode: iconMode,
                                                      agentWorking: false)
                // Active marks stay white; the glyph and accessible label convey state.
                button.contentTintColor = iconMode == nil ? nil : .white
            }
        }

        let modeText = activeMode.map { " · " + ($0 == .manual ? "Timed" : $0.rawValue.capitalized) + " session" } ?? ""
        let countdownText: String
        if showsInfinite {
            countdownText = ", no time limit"
        } else if let timerText {
            countdownText = ", \(timerText) remaining"
        } else {
            countdownText = ""
        }
        let workingText = activeMode == .auto
            ? (status.agentWorking ? ", agent working" : ", no agent working") : ""
        let label = status.accessibilityLabel + modeText + countdownText + workingText
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(label)
        button.toolTip = label
        if shouldNotify { NSAccessibility.post(element: button, notification: .valueChanged) }
    }

    private static func timerText(for activeMode: RequestedMode?, status: MenuBarStatus) -> String? {
        guard activeMode == .timed || activeMode == .manual, status.tone != .stopped else { return nil }
        return MenuBarCountdown.text(remaining: status.timerRemainingSeconds)
    }

    private func startAutoAnimation() {
        guard autoAnimationTimer == nil else { return }
        guard let button = statusItem?.button else { return }
        let frames = CamLidStatusIcon.autoSpinnerFrames
        autoAnimationIndex = 0
        button.image = frames.first
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceAutoAnimation() }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoAnimationTimer = timer
    }

    private func advanceAutoAnimation() {
        guard let button = statusItem?.button else {
            stopAutoAnimation()
            return
        }
        let frames = CamLidStatusIcon.autoSpinnerFrames
        guard !frames.isEmpty else { return }
        autoAnimationIndex = (autoAnimationIndex + 1) % frames.count
        button.image = frames[autoAnimationIndex]
    }

    private func stopAutoAnimation() {
        autoAnimationTimer?.invalidate()
        autoAnimationTimer = nil
        autoAnimationIndex = 0
    }

    /// Call from the dashboard panel dismissal path (including Esc) so
    /// keyboard focus returns to the status item per MASTER.
    public func restoreFocusToStatusItem() {
        statusItem?.button?.window?.makeFirstResponder(statusItem?.button)
    }

    // MARK: - Click routing

    @objc private func handleClick(_ sender: Any?) {
        if Self.opensContextMenu(eventType: NSApp.currentEvent?.type, control: NSApp.currentEvent?.modifierFlags.contains(.control) == true) {
            showMenu()
        } else {
            onToggleDashboard?()
        }
    }
    /// Right-click and Control-click open the menu; any other click toggles the dashboard.
    static func opensContextMenu(eventType: NSEvent.EventType?, control: Bool) -> Bool {
        eventType == .rightMouseUp || control
    }

    public var anchorButton: NSStatusBarButton? { statusItem?.button }

    public func showMenu() {
        onOpenOptions?()
        guard let button = statusItem?.button else { return }
        let menu = buildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    private func installApplicationMenu() {
        let root = NSMenu()
        let application = NSMenuItem(title: "CamLid", action: nil, keyEquivalent: "")
        application.submenu = buildMenu()
        root.addItem(application)
        let window = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        window.submenu = windowMenu
        root.addItem(window)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = root
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let dashboard = NSMenuItem(title: "Show Dashboard", action: #selector(didSelectDashboard), keyEquivalent: "d")
        dashboard.target = self
        menu.addItem(dashboard)
        let start = NSMenuItem(
            title: "Auto", action: #selector(didSelectStart),
            keyEquivalent: ""
        )
        start.tag = 1
        start.target = self
        start.isEnabled = (actions?.menuBarCanStart ?? false) && (actions?.menuBarAutoAvailable ?? false)
        start.state = actions?.menuBarActiveMode == .auto ? .on : .off
        start.setAccessibilityIdentifier(CamLidAccessibility.IDs.startMenuItem)
        menu.addItem(start)

        let stop = NSMenuItem(
            title: "Stop", action: #selector(didSelectStop),
            keyEquivalent: "."
        )
        stop.tag = 2
        stop.target = self
        stop.isEnabled = actions?.menuBarCanStop ?? false
        stop.isHidden = actions?.menuBarCanStop != true
        stop.setAccessibilityIdentifier(CamLidAccessibility.IDs.stopMenuItem)
        menu.addItem(stop)

        menu.addItem(.separator())

        // MASTER Quick Options: Settings…; Activity Log…; separator; Quit.
        // (Check for Updates… / About CamLid arrive with the real app shell.)
        let settings = NSMenuItem(
            title: "Settings…", action: #selector(didSelectSettings),
            keyEquivalent: ","
        )
        settings.target = self
        settings.setAccessibilityIdentifier(CamLidAccessibility.IDs.settingsMenuItem)
        menu.addItem(settings)

        let log = NSMenuItem(
            title: "Activity Log…", action: #selector(didSelectActivityLog),
            keyEquivalent: "l"
        )
        log.target = self
        menu.addItem(log)

        let diagnostics = NSMenuItem(title: "Why is my Mac awake?…", action: #selector(didSelectSleepDiagnostics), keyEquivalent: "")
        diagnostics.target = self; menu.addItem(diagnostics)

        let welcome = NSMenuItem(title: "Welcome & Safety…", action: #selector(didSelectWelcome), keyEquivalent: "")
        welcome.target = self; menu.addItem(welcome)
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(didSelectUpdates), keyEquivalent: "")
        updates.target = self
        updates.setAccessibilityIdentifier("camlid.menu.updates")
        menu.addItem(updates)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit CamLid", action: #selector(didSelectQuit),
            keyEquivalent: "q"
        )
        quit.target = self
        quit.setAccessibilityIdentifier(CamLidAccessibility.IDs.quitMenuItem)
        menu.addItem(quit)
        return menu
    }

    @objc private func didSelectDashboard() { onToggleDashboard?() }
    @objc private func didSelectSleepDiagnostics() { actions?.menuBarOpenSleepDiagnostics() }
    @objc private func didSelectUpdates() { actions?.menuBarOpenUpdates() }
    @objc private func didSelectWelcome() { actions?.menuBarShowWelcome() }
    @objc private func didSelectStart() { actions?.menuBarStartProtection() }
    @objc private func didSelectStop() { actions?.menuBarStopProtection() }
    @objc private func didSelectSettings() { actions?.menuBarOpenSettings() }
    @objc private func didSelectActivityLog() { actions?.menuBarOpenActivityLog() }
    @objc private func didSelectQuit() { actions?.menuBarQuit() }
}
