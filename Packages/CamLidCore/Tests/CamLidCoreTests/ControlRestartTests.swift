import Foundation
import Testing
@testable import CamLidCore

struct ControlRestartTests {
    @Test func restartReusesOwnedPrivateDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = LocalControlServer(directory: root)
        try server.start { _, _ in Data() }
        server.stop()
        try server.start { _, _ in Data() }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("control.sock").path))
        server.stop()
    }
}
