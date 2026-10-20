import Foundation
import Testing
@testable import CamLidCLI

@Suite("Atomic export commit")
struct ExportCommitTests {
    @Test func refusalAtCommitPreservesExistingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("camlid-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("events.json")
        let writer = DiskAtomicWriter()
        #expect(!writer.fileExists(atPath: output.path))
        try Data("preserve".utf8).write(to: output)
        #expect(throws: (any Error).self) { try writer.writeAtomically(Data("replace".utf8), toPath: output.path, overwrite: false) }
        #expect(try String(contentsOf: output, encoding: .utf8) == "preserve")
        try writer.writeAtomically(Data("replace".utf8), toPath: output.path, overwrite: true)
        #expect(try String(contentsOf: output, encoding: .utf8) == "replace")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["events.json"])
    }
}
