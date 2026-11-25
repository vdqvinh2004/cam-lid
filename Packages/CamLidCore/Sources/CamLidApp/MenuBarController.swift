import AppKit
import CamLidCore

/// Actions the host app provides. The controller owns no engine state and
/// performs no policy evaluation: it routes clicks/keys and reflects the
/// status it is given via `update(status:)`.
@MainActor
public protocol MenuBarActions: AnyObject {
    func menuBarStartProtection()
    func menuBarStartTimedProtection()
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
    func menuBarStartTimedProtection() {}
}

public struct MenuBarStatus: Sendable, Equatable {
    public let state: EffectiveState
    public let reasonText: String?
    public let leaseVerified: Bool
    /// Auto mode: true while activity keeps the Mac awake: an enabled agent reports work, or music plays (spec 025).
    public let activityHolding: Bool
    /// Timed/manual mode: live remaining seconds, or nil for Infinite.
    public let timerRemainingSeconds: Double?
    /// Lid open, keep-awake verified and the closed-lid lease unverified: the label says so instead of Unknown.
    public let keepingAwakeWithLidOpen: Bool

    public init(state: EffectiveState, reasonText: String? = nil, leaseVerified: Bool = false,
                activityHolding: Bool = false, timerRemainingSeconds: Double? = nil,
                keepingAwakeWithLidOpen: Bool = false) {
        self.keepingAwakeWithLidOpen = keepingAwakeWithLidOpen
        self.state = state
        self.reasonText = reasonText
        self.leaseVerified = leaseVerified
        self.activityHolding = activityHolding
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
        case .protected: return leaseVerified ? "laptopcomputer.badge.checkmark" : "laptopcomputer"
        case .completionGrace: return "moon.zzz"
        case .safetyStopped, .expired, .recoveryRequired: return "laptopcomputer.trianglebadge.exclamationmark"
        case .off: return "laptopcomputer.slash"
        case .ready: return "laptopcomputer"
        case .unavailable: return "questionmark.circle"
        }
    }

    public var accessibilityLabel: String {
        if keepingAwakeWithLidOpen && state == .protected && !leaseVerified {
            return trf("CamLid: %@", CamLidAccessibility.StatusStyle.keepingAwakeWithLidOpen.text)
        }
        let reason: String?
        if state == .protected, !leaseVerified {
            reason = tr("protection unverified")
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
    /// The arc that turns while activity keeps an Auto session awake: a subview of the status button, so the laptop stays still.
    private var autoSpinner: PassThroughImageView?
    private static let autoSpinKey = "camlid.autoSpin"

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
        autoSpinner?.removeFromSuperview()
        autoSpinner = nil
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
            menu.item(withTag: 3)?.isEnabled = actions?.menuBarCanStart ?? false
            menu.item(withTag: 3)?.state = Self.isTimedActive(actions?.menuBarActiveMode) ? .on : .off
        }
        let activeMode = actions?.menuBarActiveMode
        let isTimedSession = activeMode == .timed || activeMode == .manual
        let timerText = Self.timerText(for: activeMode, status: status)
        let showsInfinite = isTimedSession && status.tone != .stopped && status.timerRemainingSeconds == nil
        guard status != renderedStatus || activeMode != renderedMode || timerText != renderedTimerText else { return }
        renderedStatus = status
        renderedMode = activeMode
        renderedTimerText = timerText

        let autoWorking = activeMode == .auto && status.tone != .stopped && status.activityHolding
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
            button.contentTintColor = nil   // template marks follow the menu bar's appearance
            if autoWorking {
                startAutoAnimation()
            } else {
                stopAutoAnimation()
                let iconMode: RequestedMode? = activeMode == .auto ? .auto : nil
                button.image = CamLidStatusIcon.image(for: status.tone, activeMode: iconMode,
                                                      activityHolding: false)
            }
        }

        let modeText = activeMode.map { trf(" · %@ session", $0 == .manual ? tr("Timed") : tr($0.rawValue.capitalized)) } ?? ""
        let countdownText: String
        if showsInfinite {
            countdownText = tr(", no time limit")
        } else if let timerText {
            countdownText = trf(", %@ remaining", timerText)
        } else {
            countdownText = ""
        }
        let workingText = activeMode == .auto
            ? (status.activityHolding ? tr(", working") : tr(", not working")) : ""
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
        guard let button = statusItem?.button, let still = CamLidStatusIcon.autoSpinnerStill,
              let base = CamLidStatusIcon.autoSpinnerBase, let arc = CamLidStatusIcon.autoSpinnerArc else { return }
        // Reduce Motion: a still mark; the accessible label already says an agent is working.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopAutoAnimation()
            button.image = still
            return
        }
        // The laptop stays where it is; only the arc, a layer of its own, turns about its centre.
        button.image = base
        let spinner = autoSpinner ?? makeAutoSpinner(in: button)
        spinner.image = arc
        spinner.frame = Self.arcFrame(in: button)
        spinner.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        spinner.layer?.position = CGPoint(x: spinner.frame.midX, y: spinner.frame.midY)
        spinner.isHidden = false
        guard spinner.layer?.animation(forKey: Self.autoSpinKey) == nil else { return }
        spinner.layer?.add(Self.spinAnimation(), forKey: Self.autoSpinKey)
    }

    private func stopAutoAnimation() {
        autoSpinner?.layer?.removeAnimation(forKey: Self.autoSpinKey)
        autoSpinner?.isHidden = true
    }

    private func makeAutoSpinner(in button: NSStatusBarButton) -> PassThroughImageView {
        button.wantsLayer = true
        let spinner = PassThroughImageView()
        spinner.imageScaling = .scaleNone
        spinner.wantsLayer = true
        spinner.isHidden = true
        spinner.setAccessibilityElement(false)
        button.addSubview(spinner)
        autoSpinner = spinner
        return spinner
    }

    /// The square of the arc in the button's coordinates: the badge in the mark's lower right corner, where the arc is drawn.
    private static func arcFrame(in button: NSStatusBarButton) -> NSRect {
        let arc = CamLidStatusIcon.autoSpinnerArc?.size ?? .zero
        let markSize = CamLidStatusIcon.autoSpinnerStill?.size ?? .zero
        let mark = (button.cell as? NSButtonCell)?.imageRect(forBounds: button.bounds)
            ?? NSRect(x: button.bounds.midX - markSize.width / 2, y: button.bounds.midY - markSize.height / 2,
                      width: markSize.width, height: markSize.height)
        // The status button is flipped: its bottom is the larger y, which is where the badge is drawn.
        let bottom = button.isFlipped ? mark.maxY - arc.height : mark.minY
        return NSRect(x: mark.maxX - arc.width, y: bottom, width: arc.width, height: arc.height)
    }

    /// One clockwise turn per `autoSpinnerTurnSeconds`, repeated for as long as the session runs. Core Animation draws each
    /// step, so the app does no work per frame.
    static func spinAnimation() -> CABasicAnimation {
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0.0
        spin.toValue = -2 * Double.pi
        spin.duration = CamLidStatusIcon.autoSpinnerTurnSeconds
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        return spin
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
    /// Timed and Manual sessions both run a timer, so both show the Timed item as on.
    static func isTimedActive(_ mode: RequestedMode?) -> Bool { mode == .timed || mode == .manual }

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

    func installApplicationMenu() {
        let root = NSMenu()
        let application = NSMenuItem(title: tr("CamLid"), action: nil, keyEquivalent: "")
        let appMenu = buildMenu()
        // The icon's menu has no Dashboard item. The app's own menu keeps it, with its ⌘D shortcut.
        let dashboard = NSMenuItem(title: tr("Show Dashboard"), action: #selector(didSelectDashboard), keyEquivalent: "d")
        dashboard.target = self
        appMenu.insertItem(dashboard, at: 0)
        appMenu.insertItem(.separator(), at: 1)
        application.submenu = appMenu
        root.addItem(application)
        let window = NSMenuItem(title: tr("Window"), action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: tr("Window"))
        windowMenu.addItem(NSMenuItem(title: tr("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        window.submenu = windowMenu
        root.addItem(window)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = root
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let start = NSMenuItem(
            title: tr("Auto"), action: #selector(didSelectStart),
            keyEquivalent: ""
        )
        start.tag = 1
        start.target = self
        start.isEnabled = (actions?.menuBarCanStart ?? false) && (actions?.menuBarAutoAvailable ?? false)
        start.state = actions?.menuBarActiveMode == .auto ? .on : .off
        start.setAccessibilityIdentifier(CamLidAccessibility.IDs.startMenuItem)
        menu.addItem(start)

        // Timed runs for the Default Timed duration in Settings, as the Dashboard's Timed button does.
        let timed = NSMenuItem(title: tr("Timed"), action: #selector(didSelectStartTimed), keyEquivalent: "")
        timed.tag = 3
        timed.target = self
        timed.isEnabled = actions?.menuBarCanStart ?? false
        timed.state = Self.isTimedActive(actions?.menuBarActiveMode) ? .on : .off
        menu.addItem(timed)

        let stop = NSMenuItem(
            title: tr("Stop"), action: #selector(didSelectStop),
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
        let settings = NSMenuItem(
            title: tr("Settings…"), action: #selector(didSelectSettings),
            keyEquivalent: ","
        )
        settings.target = self
        settings.setAccessibilityIdentifier(CamLidAccessibility.IDs.settingsMenuItem)
        menu.addItem(settings)

        let log = NSMenuItem(
            title: tr("Activity Log…"), action: #selector(didSelectActivityLog),
            keyEquivalent: "l"
        )
        log.target = self
        menu.addItem(log)

        let diagnostics = NSMenuItem(title: tr("Why is my Mac awake?…"), action: #selector(didSelectSleepDiagnostics), keyEquivalent: "")
        diagnostics.target = self; menu.addItem(diagnostics)

        let welcome = NSMenuItem(title: tr("Welcome & Safety…"), action: #selector(didSelectWelcome), keyEquivalent: "")
        welcome.target = self; menu.addItem(welcome)
        let updates = NSMenuItem(title: tr("Check for Updates…"), action: #selector(didSelectUpdates), keyEquivalent: "")
        updates.target = self
        updates.setAccessibilityIdentifier("camlid.menu.updates")
        menu.addItem(updates)
        let about = NSMenuItem(title: tr("About CamLid"), action: #selector(didSelectAbout), keyEquivalent: "")
        about.target = self
        about.setAccessibilityIdentifier("camlid.menu.about")
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: tr("Quit CamLid"), action: #selector(didSelectQuit),
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
    @objc private func didSelectAbout() { AboutPanel.show() }
    @objc private func didSelectWelcome() { actions?.menuBarShowWelcome() }
    @objc private func didSelectStart() { actions?.menuBarStartProtection() }
    @objc private func didSelectStartTimed() { actions?.menuBarStartTimedProtection() }
    @objc private func didSelectStop() { actions?.menuBarStopProtection() }
    @objc private func didSelectSettings() { actions?.menuBarOpenSettings() }
    @objc private func didSelectActivityLog() { actions?.menuBarOpenActivityLog() }
    @objc private func didSelectQuit() { actions?.menuBarQuit() }
}

/// The spinning arc. It takes no clicks, so the status button still receives them.
private final class PassThroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
