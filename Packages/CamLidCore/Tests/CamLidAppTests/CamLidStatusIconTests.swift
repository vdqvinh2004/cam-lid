import AppKit
import Testing
import CamLidCore
@testable import CamLidApp

/// Idle marks adapt to appearance; active marks retain a visible white symbol.
struct CamLidStatusIconTests {
    @Test @MainActor func activeModesHaveDistinctIcons() throws {
        let images = try [CamLidStatusIcon.image(for: .neutral), CamLidStatusIcon.image(for: .neutral, activeMode: .auto), CamLidStatusIcon.image(for: .neutral, activeMode: .timed)].map { try #require($0?.tiffRepresentation) }
        #expect(Set(images).count == 3)
    }
    @Test @MainActor func activeSymbolsAreWhiteWithoutTemplateRecoloring() throws {
        for mode in [CamLidCore.RequestedMode.auto, .timed] {
            let image = try #require(CamLidStatusIcon.image(for: .neutral, activeMode: mode))
            #expect(!image.isTemplate)
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            var opaquePixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.5 else { continue }
                    opaquePixels += 1
                    #expect(color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95)
                }
            }
            #expect(opaquePixels > 0)
        }
    }
    @Test @MainActor func markRendersForEveryTone() {
        for tone: CamLidAccessibility.StatusTone in [.ok, .attention, .stopped, .neutral] {
            let image = CamLidStatusIcon.image(for: tone)
            #expect(image != nil)
            #expect(image?.size == NSSize(width: 18, height: 16))
            #expect(image?.isTemplate == true)
        }
    }
}
