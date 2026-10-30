import AppKit
import CamLidCore

/// Native menu-bar marks. Off/attention use template laptop symbols, Auto uses
/// an empty ring while waiting and an animated spinner while an agent works,
/// and Timed sessions render a finite countdown as text or an infinity glyph.
public enum CamLidStatusIcon {
    private static let statusSize = NSSize(width: 18, height: 16)
    private static let spinnerFrameCount = 12

    /// Infinite Timed sessions have no countdown to show. This template glyph
    /// adapts to the menu-bar appearance like the other idle marks.
    public static func infinityImage() -> NSImage? {
        symbolImage("infinity", active: false)
    }

    public static func image(for tone: CamLidAccessibility.StatusTone, activeMode: RequestedMode? = nil,
                             agentWorking: Bool = false) -> NSImage? {
        if tone == .stopped {
            return symbolImage("laptopcomputer.trianglebadge.exclamationmark", active: activeMode != nil)
        }
        if activeMode == .auto {
            return agentWorking ? autoSpinnerFrames.first : symbolImage("circle.dashed", active: true)
        }
        if activeMode == .timed || activeMode == .manual {
            // Timed sessions show the real remaining time as menu-bar text.
            return nil
        }
        let symbol = tone == .attention ? "laptopcomputer.trianglebadge.exclamationmark" : "laptopcomputer"
        return symbolImage(symbol, active: false)
    }

    /// Rotating frames for an Auto session with at least one working agent.
    /// The ring is white and non-template because NSStatusBarButton can
    /// override template tint.
    public static var autoSpinnerFrames: [NSImage] {
        spinnerFrames
    }

    private static func symbolImage(_ name: String, active: Bool) -> NSImage? {
        guard let image = (NSImage(systemSymbolName: name, accessibilityDescription: "CamLid")
            ?? NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "CamLid"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)) else { return nil }
        image.size = statusSize
        guard active else {
            image.isTemplate = true
            return image
        }
        let white = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.white.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        white.accessibilityDescription = image.accessibilityDescription
        white.isTemplate = false
        return white
    }

    private static let spinnerFrames: [NSImage] = (0..<spinnerFrameCount).map { frame in
        let phase = CGFloat(frame) / CGFloat(spinnerFrameCount)
        let image = NSImage(size: statusSize, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = max(1, min(rect.width, rect.height) / 2 - 2)
            let start = -90 + phase * 360
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius,
                           startAngle: start, endAngle: start + 290)
            path.lineWidth = 2
            path.lineCapStyle = .round
            NSColor.white.setStroke()
            path.stroke()
            return true
        }
        image.accessibilityDescription = "CamLid"
        image.isTemplate = false
        return image
    }
}
