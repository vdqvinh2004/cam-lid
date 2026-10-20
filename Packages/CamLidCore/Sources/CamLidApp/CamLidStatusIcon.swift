import AppKit
import CamLidCore

/// Distinct native marks identify idle, Auto and Timed sessions without color.
public enum CamLidStatusIcon {
    public static func image(for tone: CamLidAccessibility.StatusTone, activeMode: RequestedMode? = nil) -> NSImage? {
        let symbol: String
        if tone == .stopped { symbol = "laptopcomputer.trianglebadge.exclamationmark" }
        else if activeMode == .auto { symbol = "arrow.triangle.2.circlepath" }
        else if activeMode == .timed || activeMode == .manual { symbol = "timer" }
        else { symbol = tone == .attention ? "laptopcomputer.trianglebadge.exclamationmark" : "laptopcomputer" }
        guard let image = (NSImage(systemSymbolName: symbol, accessibilityDescription: "CamLid")
            ?? NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "CamLid"))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)) else { return nil }
        image.size = NSSize(width: 18, height: 16)
        if activeMode != nil {
            // NSStatusBarButton can override template tint. Preserve the symbol's
            // alpha and draw white explicitly for active sessions.
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
        image.isTemplate = true
        return image
    }
}
