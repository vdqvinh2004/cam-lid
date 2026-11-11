import AppKit
import CamLidCore

/// Native menu-bar marks, one laptop family shared with the Dashboard: the laptop alone while idle, with a small
/// badge for the session (Auto arrows, a rotating arc while activity keeps the Mac awake, a moon while waiting to sleep) and the
/// warning variant when stopped. Timed shows its countdown as text. Every mark is a template image, so it follows
/// light and dark menu bars (a white mark disappeared on a light menu bar).
public enum CamLidStatusIcon {
    private static let statusSize = NSSize(width: 18, height: 16)
    private static let spinnerFrameCount = 12

    /// Infinite Timed sessions have no countdown to show.
    public static func infinityImage() -> NSImage? {
        symbolImage("infinity")
    }

    public static func image(for tone: CamLidAccessibility.StatusTone, activeMode: RequestedMode? = nil,
                             activityHolding: Bool = false) -> NSImage? {
        if tone == .stopped { return symbolImage("laptopcomputer.trianglebadge.exclamationmark") }
        if activeMode == .auto {
            return activityHolding ? autoSpinnerFrames.first : badged(symbol: "arrow.triangle.2.circlepath")
        }
        // Timed sessions show the real remaining time as menu-bar text.
        if activeMode == .timed || activeMode == .manual { return nil }
        if tone == .attention { return badged(symbol: "moon.zzz.fill") }
        return symbolImage("laptopcomputer")
    }

    /// Rotating frames for an Auto session that activity keeps awake: a working agent, or music.
    public static var autoSpinnerFrames: [NSImage] { spinnerFrames }

    private static func symbolImage(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: "CamLid")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)) else { return nil }
        image.size = statusSize
        image.isTemplate = true
        return image
    }

    /// The laptop with a badge in its lower right corner, cut out of the laptop so both stay legible.
    private static func badged(symbol: String? = nil, arcPhase: CGFloat? = nil) -> NSImage? {
        guard let laptop = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "CamLid")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)) else { return nil }
        let badgeSymbol = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)) }
        let image = NSImage(size: statusSize, flipped: false) { rect in
            laptop.draw(in: NSRect(x: 0, y: 2, width: 15, height: 12))
            let badge = NSRect(x: rect.maxX - 9, y: 0, width: 9, height: 9)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: badge.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.set()
            if let phase = arcPhase {
                let path = NSBezierPath()
                let start = 90 - phase * 360
                path.appendArc(withCenter: NSPoint(x: badge.midX, y: badge.midY), radius: 3.4,
                               startAngle: start, endAngle: start - 270, clockwise: true)
                path.lineWidth = 1.6
                path.lineCapStyle = .round
                path.stroke()
            } else if let badgeSymbol {
                let size = badgeSymbol.size
                badgeSymbol.draw(in: NSRect(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2,
                                            width: size.width, height: size.height))
            }
            return true
        }
        image.accessibilityDescription = "CamLid"
        image.isTemplate = true
        return image
    }

    private static let spinnerFrames: [NSImage] = (0..<spinnerFrameCount).compactMap { frame in
        badged(arcPhase: CGFloat(frame) / CGFloat(spinnerFrameCount))
    }
}
