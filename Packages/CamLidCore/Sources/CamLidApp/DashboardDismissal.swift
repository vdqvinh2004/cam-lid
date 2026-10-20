import AppKit

/// Monitors exist only for a visible dashboard. They never consume an outside
/// click or activate another window; the status button owns its own toggle.
@MainActor
final class DashboardDismissal: NSObject, NSPopoverDelegate {
    private weak var popover: NSPopover?
    private weak var anchor: NSStatusBarButton?
    private let externalAnchorFrame: NSRect?
    private var local: Any?
    private var global: Any?
    private var deactivation: NSObjectProtocol?
    private let onClose: () -> Void
    var monitoring: Bool { local != nil }

    init(popover: NSPopover, anchor: NSStatusBarButton?, externalAnchorFrame: NSRect? = nil, onClose: @escaping () -> Void = {}) {
        self.popover = popover; self.anchor = anchor; self.externalAnchorFrame = externalAnchorFrame; self.onClose = onClose
        super.init()
        // One owner closes the dashboard; transient mouse-down dismissal
        // otherwise races the status button's mouse-up toggle.
        popover.behavior = .applicationDefined
        popover.delegate = self
    }
    func start() {
        guard !monitoring, popover?.isShown == true else { return }
        local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, let popover = self.popover else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 {
                        popover.performClose(nil)
                        // Closing changes the key window. Do not also deliver
                        // Escape to a Cancel/Skip action in the window behind it.
                        return true
                    }
                    return false
                }
                let window = event.window
                let point = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
                let anchorRect = self.externalAnchorFrame ?? self.anchor.flatMap { anchor in
                    anchor.window?.convertToScreen(anchor.convert(anchor.bounds, to: nil))
                }
                if Self.shouldDismiss(clickWindow: window,
                    popoverWindow: popover.contentViewController?.view.window, anchorWindow: self.anchor?.window,
                    clickScreenPoint: point, anchorScreenRect: anchorRect) {
                    popover.performClose(nil)
                }
                return false
            }
            return consumed ? nil : event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let location = event.locationInWindow
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.externalAnchorFrame?.contains(location) == true { return }
                // Status-bar events may arrive through SystemUIServer, so the
                // global monitor must exclude the anchor just like the local one.
                if let anchor = self.anchor, let window = anchor.window,
                   window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).contains(location) { return }
                self.popover?.performClose(nil)
            }
        }
        deactivation = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: NSApp, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let rect = self.externalAnchorFrame ?? self.anchor.flatMap { button in
                        button.window?.convertToScreen(button.convert(button.bounds, to: nil))
                    }
                    if Self.shouldDismissOnDeactivation(mouseButtons: NSEvent.pressedMouseButtons,
                        mouseScreenPoint: NSEvent.mouseLocation, anchorScreenRect: rect) {
                        self.popover?.performClose(nil)
                    }
                }
            }
    }
    static func shouldDismiss(clickWindow: NSWindow?, popoverWindow: NSWindow?, anchorWindow: NSWindow?,
                              clickScreenPoint: NSPoint? = nil, anchorScreenRect: NSRect? = nil) -> Bool {
        if let clickScreenPoint, let anchorScreenRect, anchorScreenRect.contains(clickScreenPoint) { return false }
        guard let clickWindow else { return true }
        return clickWindow !== popoverWindow && clickWindow !== anchorWindow && clickWindow.level < .popUpMenu
    }
    static func shouldDismissOnDeactivation(mouseButtons: Int, mouseScreenPoint: NSPoint,
                                           anchorScreenRect: NSRect?) -> Bool {
        // Status tracking deactivates the app before the button's mouse-up
        // toggle. That press owns dismissal; keyboard app switches still close.
        !(mouseButtons & 1 != 0 && anchorScreenRect?.contains(mouseScreenPoint) == true)
    }
    func stop() {
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        if let deactivation { NotificationCenter.default.removeObserver(deactivation) }
        local = nil; global = nil; deactivation = nil
    }
    func popoverDidClose(_ notification: Notification) {
        stop()
        popover?.contentViewController = nil
        onClose()
    }
}
