import AppKit
import CamLidCore

/// Native menu-bar marks, one laptop family shared with the Dashboard: the laptop alone while idle, with a small
/// badge for the session (Auto arrows, a rotating arc while activity keeps the Mac awake, a moon while waiting to sleep) and the
/// warning variant when stopped. Timed shows its countdown as text. Every mark is a template image, so it follows
/// light and dark menu bars (a white mark disappeared on a light menu bar).
public enum CamLidStatusIcon {
    private static let statusSize = NSSize(width: 18, height: 16)
    private static let spinnerFrameCount = 12
    /// The badge's square in the lower right corner of the mark.
    private static let badgeSize: CGFloat = 9

    /// Infinite Timed sessions have no countdown to show.
    public static func infinityImage() -> NSImage? {
        symbolImage("infinity")
    }

    public static func image(for tone: CamLidAccessibility.StatusTone, activeMode: RequestedMode? = nil,
                             activityHolding: Bool = false) -> NSImage? {
        if tone == .stopped { return symbolImage("laptopcomputer.trianglebadge.exclamationmark") }
        if activeMode == .auto {
            return activityHolding ? autoSpinnerStill : badged(symbol: "arrow.triangle.2.circlepath")
        }
        // Timed sessions show the real remaining time as menu-bar text.
        if activeMode == .timed || activeMode == .manual { return nil }
        if tone == .attention { return badged(symbol: "moon.zzz.fill") }
        return symbolImage("laptopcomputer")
    }

    /// The Auto mark at rest, with its arc. Reduce Motion keeps this still mark while activity keeps the Mac awake.
    public static var autoSpinnerStill: NSImage? { spinnerStill }
    /// The laptop with its badge cut out and no arc: the part that stays still while the arc turns.
    public static var autoSpinnerBase: NSImage? { spinnerBase }
    /// The arc alone, the size of the badge: a layer turns it about its centre while activity keeps the Mac awake.
    public static var autoSpinnerArc: NSImage? { spinnerArc }
    /// One turn of the arc: the speed of the twelve frames the spinner used to swap, 0.1 s each.
    public static var autoSpinnerTurnSeconds: Double { Double(spinnerFrameCount) / 10 }

    private static func symbolImage(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: tr("CamLid"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)) else { return nil }
        image.size = statusSize
        image.isTemplate = true
        return image
    }

    /// The laptop with a clear ring where the badge sits; `drawBadge` draws the badge in black on top of the ring.
    private static func mark(drawBadge: @escaping (NSRect) -> Void) -> NSImage? {
        guard let laptop = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: tr("CamLid"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)) else { return nil }
        let image = NSImage(size: statusSize, flipped: false) { rect in
            laptop.draw(in: NSRect(x: 0, y: 2, width: 15, height: 12))
            let badge = NSRect(x: rect.maxX - badgeSize, y: 0, width: badgeSize, height: badgeSize)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: badge.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.set()
            drawBadge(badge)
            return true
        }
        image.accessibilityDescription = tr("CamLid")
        image.isTemplate = true
        return image
    }

    /// The laptop with a badge in its lower right corner, cut out of the laptop so both stay legible.
    private static func badged(symbol: String? = nil, arcPhase: CGFloat? = nil) -> NSImage? {
        let badgeSymbol = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)) }
        return mark { badge in
            if let phase = arcPhase {
                drawArc(phase: phase, around: NSPoint(x: badge.midX, y: badge.midY))
            } else if let badgeSymbol {
                let size = badgeSymbol.size
                badgeSymbol.draw(in: NSRect(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2,
                                            width: size.width, height: size.height))
            }
        }
    }

    /// One arc of the spinner: a 270-degree stroke whose start moves clockwise as the phase goes from 0 to 1 of a turn.
    private static func drawArc(phase: CGFloat, around center: NSPoint) {
        let path = NSBezierPath()
        let start = 90 - phase * 360
        path.appendArc(withCenter: center, radius: 3.4, startAngle: start, endAngle: start - 270, clockwise: true)
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.stroke()
    }

    /// The arc alone, in a square the size of the badge, so a layer can turn it about the square's centre.
    private static func arcImage() -> NSImage? {
        let image = NSImage(size: NSSize(width: badgeSize, height: badgeSize), flipped: false) { rect in
            NSColor.black.set()
            drawArc(phase: 0, around: NSPoint(x: rect.midX, y: rect.midY))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static let spinnerStill = badged(arcPhase: 0)
    private static let spinnerBase = mark { _ in }
    private static let spinnerArc = arcImage()
}
