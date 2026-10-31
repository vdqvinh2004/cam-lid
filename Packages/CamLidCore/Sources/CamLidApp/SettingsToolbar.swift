import AppKit

/// Native preference navigation. Pane selection preserves the user's window geometry.
@MainActor
final class SettingsToolbar: NSObject, NSToolbarDelegate {
    private weak var editor: SettingsEditor?
    private weak var window: NSWindow?
    private let toolbar = NSToolbar(identifier: "CamLid.Settings")

    init(editor: SettingsEditor, window: NSWindow) {
        self.editor = editor; self.window = window
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        select(editor.section)
    }

    func select(_ section: SettingsSection) {
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(section.rawValue)
        guard let window else { return }
        window.title = section.title   // macOS settings windows are titled with the pane name
        let content = window.contentRect(forFrameRect: window.frame)
        let delta = section.preferredHeight - content.height
        guard abs(delta) > 1 else { return }
        var frame = window.frame
        frame.origin.y -= delta; frame.size.height += delta   // keep the top edge in place
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsSection.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let section = SettingsSection(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = section.title
        item.toolTip = section.title + " settings"
        item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
        item.target = self; item.action = #selector(selectPane(_:))
        return item
    }
    @objc private func selectPane(_ sender: NSToolbarItem) {
        guard let section = SettingsSection(rawValue: sender.itemIdentifier.rawValue) else { return }
        editor?.section = section
        select(section)
    }
}
