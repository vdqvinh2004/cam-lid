import Foundation
import Testing
@testable import CamLidApp

@Suite("Utility UI process transport")
struct UtilityUIPipeTests {
    @Test @MainActor func fragmentedAndCoalescedFramesPreserveOrder() async throws {
        let incoming = Pipe(), outgoing = Pipe()
        var frames: [String] = []
        var closes = 0
        let channel = UtilityUIPipe(input: incoming.fileHandleForReading, output: outgoing.fileHandleForWriting,
            receive: { frames.append(String(decoding: $0, as: UTF8.self)) }, closed: { closes += 1 })
        try incoming.fileHandleForWriting.write(contentsOf: Data("first".utf8))
        try incoming.fileHandleForWriting.write(contentsOf: Data("\nsecond\nthi".utf8))
        try incoming.fileHandleForWriting.write(contentsOf: Data("rd\n".utf8))
        let deadline = ContinuousClock.now + .seconds(2)
        while frames.count < 3, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        #expect(frames == ["first", "second", "third"])
        channel.end(); channel.end()
        #expect(closes == 1)
        try incoming.fileHandleForWriting.close(); try outgoing.fileHandleForReading.close()
    }
    @Test @MainActor func blockedPeerCannotBlockPolicyActor() throws {
        let incoming = Pipe(), outgoing = Pipe()
        var closes = 0
        let channel = UtilityUIPipe(input: incoming.fileHandleForReading, output: outgoing.fileHandleForWriting,
            receive: { _ in }, closed: { closes += 1 })
        // Far larger than the pipe buffer; the peer deliberately never reads.
        let payload = Data(repeating: 1, count: 2 * 1024 * 1024)
        let start = ContinuousClock.now
        #expect(channel.send(payload))
        channel.end()
        #expect(ContinuousClock.now - start < .milliseconds(100))
        #expect(closes == 1)
        // Broken-pipe handling must neither signal the parent nor stall cleanup.
        try outgoing.fileHandleForReading.close(); try incoming.fileHandleForWriting.close()
    }
    @Test @MainActor func oversizedFrameEndsPeerDeliveringNothing() async throws {
        let incoming = Pipe(), outgoing = Pipe()
        var frames = 0
        var closes = 0
        let channel = UtilityUIPipe(input: incoming.fileHandleForReading, output: outgoing.fileHandleForWriting,
            receive: { _ in frames += 1 }, closed: { closes += 1 })
        // One newline-free blob past the 64 MiB frame bound (written in chunks).
        let chunk = Data(repeating: 0x41, count: 4 * 1024 * 1024)
        let writer = Task.detached {
            // The reader delivers on MainActor; a synchronous write here
            // deadlocks once the pipe fills. Closure at the frame limit is expected.
            for _ in 0..<17 {
                do { try incoming.fileHandleForWriting.write(contentsOf: chunk) }
                catch { break }
            }
        }
        let deadline = ContinuousClock.now + .seconds(5)
        while closes == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(closes == 1)
        #expect(frames == 0)
        await writer.value
        _ = channel
        try incoming.fileHandleForWriting.close(); try outgoing.fileHandleForReading.close()
    }
    @Test @MainActor func malformedCommandFrameDecodesToNil() {
        // Both coordinators use `try?` decode-and-ignore; garbage must never crash or dispatch.
        #expect((try? JSONDecoder().decode(UtilityUICommand.self, from: Data("{\"this is not valid IPC\"".utf8))) == nil)
        #expect((try? JSONDecoder().decode(UtilityUIEvent.self, from: Data("@@@".utf8))) == nil)
    }
}
