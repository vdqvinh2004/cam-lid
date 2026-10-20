import AppKit
import Testing
@testable import CamLidApp

@Suite("Native utility editing menu", .serialized)
struct UtilityEditingMenuTests {
    @Test @MainActor func standardEditingCommandsUseTheResponderChain() {
        let app = NSApplication.shared
        let previous = app.mainMenu, previousWindows = app.windowsMenu
        defer { app.mainMenu = previous; app.windowsMenu = previousWindows }
        let controller = UtilityUICoordinator()
        controller.installMenu()
        guard let edit = app.mainMenu?.item(withTitle: "Edit")?.submenu else {
            Issue.record("Editable utility windows need the standard Edit menu")
            return
        }
        let commands: [(String, Selector, String)] = [
            ("Undo", Selector("undo:"), "z"), ("Redo", Selector("redo:"), "z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ]
        #expect(edit.autoenablesItems)
        for (title, action, key) in commands {
            let item = edit.item(withTitle: title)
            #expect(item != nil && item?.action == action && item?.keyEquivalent == key)
            #expect(item?.target == nil)
            #expect(item?.keyEquivalentModifierMask == (title == "Redo" ? [.command, .shift] : .command))
        }
        #expect(app.mainMenu?.items.map(\.title).suffix(2) == ["Edit", "Window"])
        #expect(app.mainMenu?.item(withTitle: "Window")?.submenu === app.windowsMenu)
    }
}
