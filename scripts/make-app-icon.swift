// Draws the CamLid app icon (a closed laptop whose seam still glows: closed, but awake) and writes the macOS
// AppIcon set. Usage: swift scripts/make-app-icon.swift <AppIcon.appiconset directory> [preview.png]
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(_ size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: size / 1024, y: size / 1024)
        // macOS icon grid: an 824 pt rounded square centred in 1024, with a soft drop shadow.
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.35).cgColor)
        color(0x0E1433).setFill(); tile.fill()
        ctx.restoreGState()
        tile.addClip()
        NSGradient(colors: [color(0x2D3D80), color(0x161E4A), color(0x0B1029)])!.draw(in: tile, angle: -90)
        // A few stars: it is night, the lid is closed.
        for (x, y, r, a) in [(250.0, 790.0, 5.0, 0.55), (340, 840, 3.5, 0.4), (700, 820, 4.5, 0.5), (790, 740, 3, 0.35),
                             (560, 870, 3, 0.3), (200, 680, 3, 0.3), (840, 860, 3.5, 0.4)] {
            color(0xFFFFFF, CGFloat(a)).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
        }
        // The closed laptop in perspective: lid surface, then the front edge of lid and base.
        let lid = NSBezierPath()
        lid.move(to: NSPoint(x: 226, y: 420)); lid.line(to: NSPoint(x: 798, y: 420))
        lid.line(to: NSPoint(x: 718, y: 640)); lid.line(to: NSPoint(x: 306, y: 640)); lid.close()
        NSGradient(colors: [color(0xF3F5FA), color(0xC9D0DD), color(0x9EA8BC)])!.draw(in: lid, angle: 90)
        color(0xFFFFFF, 0.5).setStroke(); lid.lineWidth = 3; lid.stroke()
        let lidEdge = NSBezierPath(roundedRect: NSRect(x: 222, y: 400, width: 580, height: 22), xRadius: 8, yRadius: 8)
        NSGradient(colors: [color(0xB8C0CF), color(0x8D97AB)])!.draw(in: lidEdge, angle: -90)
        let base = NSBezierPath(roundedRect: NSRect(x: 214, y: 360, width: 596, height: 32), xRadius: 12, yRadius: 12)
        NSGradient(colors: [color(0x9AA3B6), color(0x5E6780)])!.draw(in: base, angle: -90)
        // The thumb notch at the front of the base.
        color(0x3E4560, 0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 462, y: 372, width: 100, height: 14), xRadius: 7, yRadius: 7).fill()
        // The seam between lid and base glows: closed, but still working. A wide bloom first, then the line.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 80, color: color(0x4FF5C8, 1).cgColor)
        color(0x4FF5C8).setFill()
        for _ in 0..<3 {   // stacked shadows build a bright bloom that spills onto the desk
            NSBezierPath(roundedRect: NSRect(x: 250, y: 388, width: 524, height: 15), xRadius: 7, yRadius: 7).fill()
        }
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 26, color: color(0x4FF5C8, 1).cgColor)
        color(0x7DFFD9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 236, y: 391, width: 552, height: 9), xRadius: 4.5, yRadius: 4.5).fill()
        ctx.restoreGState()
        return true
    }
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(drawIcon(CGFloat(pixels)), pixels: pixels).write(to: output.appendingPathComponent(name))
        entries.append("""
            {"idiom":"mac","size":"\(points)x\(points)","scale":"\(scale)x","filename":"\(name)"}
        """)
    }
}
try ("{\"images\":[\n" + entries.joined(separator: ",\n") + "\n],\"info\":{\"version\":1,\"author\":\"xcode\"}}\n")
    .write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
if CommandLine.arguments.count > 2 {
    try png(drawIcon(1024), pixels: 1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
