import AppKit
import Testing
@testable import CamLidApp

@Suite("About panel", .serialized)
struct AboutPanelTests {
    @Test @MainActor func creditsSayWhatCamLidDoesAndLinkTheRepository() {
        let credits = AboutPanel.credits
        #expect(credits.string.contains("Keeps a Mac awake with the lid closed"))
        var links: [URL] = []
        credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
            if let url = value as? URL { links.append(url) }
        }
        #expect(links == [AboutPanel.repositoryURL])
        #expect(AboutPanel.repositoryURL.absoluteString == "https://github.com/vdqvinh2004/cam-lid")
    }

    @Test @MainActor func statusMenuOffersAboutCamLid() {
        let item = MenuBarController().buildMenu().item(withTitle: "About CamLid")
        #expect(item?.accessibilityIdentifier() == "camlid.menu.about")
    }

    @Test @MainActor func menuBarApplicationMenuOffersAboutCamLid() {
        let app = NSApplication.shared
        let previous = app.mainMenu, previousWindows = app.windowsMenu
        defer { app.mainMenu = previous; app.windowsMenu = previousWindows }
        UtilityUICoordinator().installMenu()
        #expect(app.mainMenu?.items.first?.submenu?.item(withTitle: "About CamLid") != nil)
    }
}
