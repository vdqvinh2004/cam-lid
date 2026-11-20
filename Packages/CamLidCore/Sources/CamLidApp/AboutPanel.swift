import AppKit

/// The standard macOS About window. Icon, name, version and copyright come from the app bundle.
@MainActor
enum AboutPanel {
    static let repositoryURL = URL(string: "https://github.com/vdqvinh2004/cam-lid")!

    static func show() {
        // The menu bar app is not active by itself, so the panel would open behind other windows.
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    static var credits: NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let credits = NSMutableAttributedString(
            string: tr("Keeps a Mac awake with the lid closed while AI coding agents work, then lets it sleep.") + "\n",
            attributes: text
        )
        credits.append(NSAttributedString(
            string: "github.com/vdqvinh2004/cam-lid",
            attributes: text.merging([.link: repositoryURL]) { _, link in link }
        ))
        return credits
    }
}
