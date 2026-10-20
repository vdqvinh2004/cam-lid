import Darwin
import Foundation
import Testing

@testable import CamLidCore

@Suite("Bounded local-control transport", .serialized)
struct ControlFloodTests {
    @Test("an idle peer cannot starve a status request")
    func idlePeerDoesNotBlockStatus() throws {
        let directory = try makeControlDirectory()
        let server = LocalControlServer(directory: directory)
        try server.start { _, _ in Data("status-ok".utf8) }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }

        let idle = try connectRaw(to: directory.appendingPathComponent("control.sock").path)
        defer { Darwin.close(idle) }
        let startedAt = ContinuousTime.now
        let response = try LocalControlChannel(directory: directory)
            .send(command: .status, payload: Data())
        #expect(response == Data("status-ok".utf8))
        #expect(ContinuousTime.now - startedAt < 0.5)
    }

    @Test("eight incomplete peers cannot starve status or stop")
    func eightIncompletePeersDoNotBlockControls() throws {
        let directory = try makeControlDirectory()
        let server = LocalControlServer(directory: directory)
        try server.start { command, _ in Data(command.rawValue.utf8) }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        var peers: [Int32] = []
        defer { peers.forEach { Darwin.close($0) } }
        for _ in 0..<8 {
            let fd = try connectRaw(to: directory.appendingPathComponent("control.sock").path)
            try sendBytes([0, 0], to: fd)
            peers.append(fd)
        }
        Thread.sleep(forTimeInterval: 0.1)
        let started = ContinuousTime.now
        let channel = LocalControlChannel(directory: directory)
        #expect(try channel.send(command: .status, payload: Data()) == Data("status".utf8))
        #expect(try channel.send(command: .stop, payload: Data()) == Data("stop".utf8))
        #expect(ContinuousTime.now - started < 0.5)
    }

    @Test("incomplete frame capacity evicts the oldest reader and admits controls")
    func clientCapPreservesControlAdmission() throws {
        let directory = try makeControlDirectory()
        let server = LocalControlServer(directory: directory)
        try server.start { _, _ in Data("available".utf8) }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        var peers: [Int32] = []
        defer { peers.forEach { Darwin.close($0) } }
        for index in 0..<LocalControlServer.maxConnections {
            peers.append(try connectRaw(to: directory.appendingPathComponent("control.sock").path))
            let until = ContinuousTime.now + 1
            while server.resourceCounts.connections < index + 1 && ContinuousTime.now < until {
                Thread.sleep(forTimeInterval: 0.001)
            }
            #expect(server.resourceCounts.connections == index + 1)
        }
        let admissionDeadline = ContinuousTime.now + 1
        while server.resourceCounts.connections < LocalControlServer.maxConnections && ContinuousTime.now < admissionDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        #expect(server.resourceCounts.connections == LocalControlServer.maxConnections)
        let started = ContinuousTime.now
        #expect(try LocalControlChannel(directory: directory).send(command: .status, payload: Data()) == Data("available".utf8))
        #expect(readOneByte(peers[0]) == 0)
        #expect(ContinuousTime.now - started < 0.5)
        #expect(server.resourceCounts.connections <= LocalControlServer.maxConnections)
    }

    @Test("saturated event handlers leave status and stop capacity")
    func eventHandlersCannotConsumePrioritySlots() throws {
        let directory = try makeControlDirectory()
        let server = LocalControlServer(directory: directory)
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let finished = DispatchGroup(), failures = LockedCallCount()
        try server.start { command, _ in
            if command == .event {
                started.signal()
                _ = release.wait(timeout: .now() + 2)
            }
            return Data(command.rawValue.utf8)
        }
        defer {
            for _ in 0..<6 { release.signal() }
            _ = finished.wait(timeout: .now() + 3)
            server.stop(); try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<6 {
            finished.enter()
            DispatchQueue.global().async {
                defer { finished.leave() }
                if (try? LocalControlChannel(directory: directory).send(command: .event, payload: Data())) != Data("event".utf8) { failures.increment() }
            }
        }
        for _ in 0..<6 { #expect(started.wait(timeout: .now() + 1) == .success) }
        let channel = LocalControlChannel(directory: directory), began = ContinuousTime.now
        #expect(try channel.send(command: .status, payload: Data()) == Data("status".utf8))
        #expect(try channel.send(command: .stop, payload: Data()) == Data("stop".utf8))
        #expect(ContinuousTime.now - began < 0.5)
        for _ in 0..<6 { release.signal() }
        #expect(finished.wait(timeout: .now() + 1) == .success)
        #expect(failures.value() == 0)
    }

    @Test("slow large-export readers cannot occupy status or stop workers")
    func blockedResponsesLeaveControlCapacityAndBoundMemory() throws {
        let directory = try makeControlDirectory()
        let server = LocalControlServer(directory: directory)
        let exportCalls = LockedCallCount()
        try server.start { command, _ in
            if command == .logsExport {
                exportCalls.increment()
                // Slash-rich base64 stresses encoded-byte accounting.
                return Data(repeating: 0xff, count: 10 * 1_024 * 1_024)
            }
            return Data(command.rawValue.utf8)
        }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        var peers: [Int32] = []
        defer { peers.forEach { Darwin.close($0) } }
        for index in 0..<5 {
            let fd = try connectRaw(to: directory.appendingPathComponent("control.sock").path)
            peers.append(fd)
            let request = Data(#"{"command":"logsExport","payload":""}"#.utf8)
            var size = UInt32(request.count).bigEndian
            let frame = withUnsafeBytes(of: &size) { Data($0) } + request
            try sendBytes(Array(frame), to: fd)
            let waitUntil = ContinuousTime.now + 1
            while exportCalls.value() < index + 1 && ContinuousTime.now < waitUntil { Thread.sleep(forTimeInterval: 0.01) }
            // Let encoding finish before sending the next bulk handler.
            Thread.sleep(forTimeInterval: 0.08)
        }
        let channel = LocalControlChannel(directory: directory), began = ContinuousTime.now
        #expect(try channel.send(command: .status, payload: Data()) == Data("status".utf8))
        #expect(try channel.send(command: .stop, payload: Data()) == Data("stop".utf8))
        #expect(ContinuousTime.now - began < 0.5)
        #expect(server.resourceCounts.responseBytes <= LocalControlServer.maxResponseBytes)
        #expect(server.resourceCounts.responseBytes > 0)
    }

    @Test("an exactly saturated export-byte pool preserves priority reply headroom")
    func fullExportBudgetStillRepliesToControls() throws {
        let directory = try makeControlDirectory(), server = LocalControlServer(directory: directory)
        let produced = LockedCallCount()
        try server.start { command, _ in
            if command == .logsExport {
                let prior = produced.value(); produced.increment()
                let firstReservation = (20 * 1_024 * 1_024 + 2) / 3 * 4 + 1_024
                let finalBytes = (LocalControlServer.ordinaryResponseLimit - 2 * firstReservation - 1_024) / 4 * 3
                return Data(repeating: 0xff, count: prior < 2 ? 20 * 1_024 * 1_024 : finalBytes)
            }
            return Data(command.rawValue.utf8)
        }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        var peers: [Int32] = []
        defer { peers.forEach { Darwin.close($0) } }
        for index in 0..<3 {
            let fd = try connectRaw(to: directory.appendingPathComponent("control.sock").path)
            peers.append(fd)
            try sendRequest(.logsExport, to: fd)
            // A byte on the wire proves encoding and the serial export
            // handler have finished before the next export is admitted.
            // Leave the remainder unread to retain its entire reservation.
            #expect(readOneByte(fd) == 1)
            let target = index == 2 ? LocalControlServer.ordinaryResponseLimit - 4 : (index + 1) * ((20 * 1_024 * 1_024 + 2) / 3 * 4 + 1_024)
            let until = ContinuousTime.now + 1
            while server.resourceCounts.responseBytes < target && ContinuousTime.now < until { Thread.sleep(forTimeInterval: 0.01) }
            #expect(server.resourceCounts.responseBytes >= target)
        }
        let channel = LocalControlChannel(directory: directory), began = ContinuousTime.now
        #expect(try channel.send(command: .status, payload: Data()) == Data("status".utf8))
        #expect(try channel.send(command: .stop, payload: Data()) == Data("stop".utf8))
        #expect(ContinuousTime.now - began < 0.5)
        #expect(server.resourceCounts.responseBytes <= LocalControlServer.maxResponseBytes)
    }

    @Test("a table of blocked read-only replies yields connection admission to controls")
    func blockedReplyTableDoesNotRejectControls() throws {
        let directory = try makeControlDirectory(), server = LocalControlServer(directory: directory)
        try server.start { command, _ in
            command == .logsExport ? Data(repeating: 0xff, count: 512 * 1_024) : Data(command.rawValue.utf8)
        }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        var peers: [Int32] = []
        defer { peers.forEach { Darwin.close($0) } }
        for index in 0..<LocalControlServer.maxConnections {
            let fd = try connectRaw(to: directory.appendingPathComponent("control.sock").path)
            peers.append(fd)
            try sendRequest(.logsExport, to: fd)
            // A reservation precedes encoding; wait for wire output before sending another serial export.
            #expect(readOneByte(fd) == 1)
            let until = ContinuousTime.now + 0.25
            let target = (index + 1) * ((512 * 1_024 + 2) / 3 * 4 + 1_024)
            while server.resourceCounts.responseBytes < target && ContinuousTime.now < until { Thread.sleep(forTimeInterval: 0.005) }
            #expect(server.resourceCounts.responseBytes >= target)
        }
        #expect(server.resourceCounts.connections == LocalControlServer.maxConnections)
        let channel = LocalControlChannel(directory: directory), began = ContinuousTime.now
        #expect(try channel.send(command: .status, payload: Data()) == Data("status".utf8))
        #expect(try channel.send(command: .stop, payload: Data()) == Data("stop".utf8))
        #expect(ContinuousTime.now - began < 0.5)
    }

    @Test("stop shuts old clients and waits before same-instance restart")
    func restartCannotReuseOldAcceptLoop() throws {
        let directory = try makeControlDirectory()
        let server = LocalControlServer(directory: directory)
        let oldCalls = LockedCallCount()
        try server.start { _, _ in
            oldCalls.increment()
            return Data("old".utf8)
        }
        let oldIdle = try connectRaw(to: directory.appendingPathComponent("control.sock").path)
        Thread.sleep(forTimeInterval: 0.05)
        server.stop()
        #expect(readOneByte(oldIdle) == 0)
        Darwin.close(oldIdle)

        let newCalls = LockedCallCount()
        try server.start { _, _ in
            newCalls.increment()
            return Data("new".utf8)
        }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }
        let result = try LocalControlChannel(directory: directory)
            .send(command: .status, payload: Data())
        #expect(result == Data("new".utf8))
        #expect(oldCalls.value() == 0)
        #expect(newCalls.value() == 1)
    }

    @Test("stop closes old clients without claiming to cancel admitted handlers")
    func restartSuppressesLateReplyFromAdmittedHandler() throws {
        let directory = try makeControlDirectory(), server = LocalControlServer(directory: directory)
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0), effects = LockedCallCount()
        try server.start { _, _ in
            entered.signal()
            _ = release.wait(timeout: .now() + 2)
            effects.increment()
            finished.signal()
            return Data("old-reply".utf8)
        }
        let old = try connectRaw(to: directory.appendingPathComponent("control.sock").path)
        defer {
            release.signal()
            server.stop(); Darwin.close(old)
            try? FileManager.default.removeItem(at: directory)
        }
        try sendRequest(.event, to: old)
        #expect(entered.wait(timeout: .now() + 1) == .success)
        let began = ContinuousTime.now
        server.stop()
        #expect(ContinuousTime.now - began < 0.5)
        #expect(effects.value() == 0)
        #expect(readOneByte(old) == 0)
        try server.start { _, _ in Data("new-reply".utf8) }
        release.signal()
        #expect(finished.wait(timeout: .now() + 1) == .success)
        // Handler side effects remain the caller's responsibility; the old
        // response must never enter a reused fd or the new generation.
        #expect(effects.value() == 1)
        #expect(try LocalControlChannel(directory: directory).send(command: .status, payload: Data()) == Data("new-reply".utf8))
    }

    @Test("stop preserves a replacement control socket path")
    func stopUnlinksOnlyItsOwnSocket() throws {
        let directory = try makeControlDirectory()
        let server = LocalControlServer(directory: directory)
        try server.start { _, _ in Data() }
        let endpoint = directory.appendingPathComponent("control.sock")
        let movedSocket = directory.appendingPathComponent("original.sock")
        try FileManager.default.moveItem(at: endpoint, to: movedSocket)
        let replacement = Data("user replacement".utf8)
        try replacement.write(to: endpoint, options: .atomic)

        server.stop()
        #expect(FileManager.default.fileExists(atPath: endpoint.path))
        #expect(try Data(contentsOf: endpoint) == replacement)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("owner lock rejects symlinks and non-private regular files without changing them")
    func ownerLockMustBePrivateRegularFile() throws {
        let directory = try makeControlDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = directory.appendingPathComponent("owner.lock")
        let target = directory.appendingPathComponent("target")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(atPath: owner.path, withDestinationPath: target.path)
        let server = LocalControlServer(directory: directory)
        #expect(throws: (any Error).self) { try server.start { _, _ in Data() } }
        #expect(try Data(contentsOf: target) == Data("keep".utf8))

        try FileManager.default.removeItem(at: owner)
        try Data("private state".utf8).write(to: owner)
        #expect(chmod(owner.path, 0o644) == 0)
        #expect(throws: (any Error).self) { try server.start { _, _ in Data() } }
        var attributes = stat()
        #expect(lstat(owner.path, &attributes) == 0)
        #expect((attributes.st_mode & 0o777) == 0o644)
    }

    @Test("header and body share one absolute three-second frame deadline")
    func trickleCannotExtendFrameDeadline() throws {
        let directory = try makeControlDirectory()
        let server = LocalControlServer(directory: directory)
        try server.start { _, _ in Data("still-alive".utf8) }
        defer { server.stop(); try? FileManager.default.removeItem(at: directory) }

        let client = try connectRaw(
            to: directory.appendingPathComponent("control.sock").path,
            receiveTimeout: 6
        )
        defer { Darwin.close(client) }

        let startedAt = ContinuousTime.now
        let header: [UInt8] = [0, 0, 0, 8]
        for (index, byte) in header.enumerated() {
            try sendBytes([byte], to: client)
            if index < header.count - 1 { Thread.sleep(forTimeInterval: 0.55) }
        }
        try sendBytes([0x41], to: client)
        for _ in 0..<2 {
            Thread.sleep(forTimeInterval: 0.55)
            try sendBytes([0x41], to: client)
        }

        let response = try readToEOF(client)
        #expect(!response.isEmpty)
        #expect(response.contains(0x75)) // JSON error response: `u` in unavailable.
        #expect(ContinuousTime.now - startedAt < 4)
        #expect(try LocalControlChannel(directory: directory)
            .send(command: .status, payload: Data()) == Data("still-alive".utf8))
    }
}

private func makeControlDirectory() throws -> URL {
    let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("camctl-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    return directory
}

private func connectRaw(to path: String, receiveTimeout: Int = 1) throws -> Int32 {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw IPCError.unavailable }
    var noSignal: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: receiveTimeout, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var address = sockaddr_un()
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        Darwin.close(fd)
        throw IPCError.invalidInput("socketPathTooLong")
    }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        Darwin.close(fd)
        throw IPCError.unavailable
    }
    return fd
}

private func readOneByte(_ fd: Int32) -> Int {
    var byte: UInt8 = 0
    return Darwin.read(fd, &byte, 1)
}

private func readToEOF(_ fd: Int32) throws -> Data {
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 256)
    while true {
        let count = buffer.withUnsafeMutableBytes { bytes in
            Darwin.read(fd, bytes.baseAddress!, bytes.count)
        }
        if count == 0 { return result }
        guard count > 0 else { throw IPCError.unavailable }
        result.append(contentsOf: buffer.prefix(count))
    }
}

private func sendRequest(_ command: AllowlistedCommand, to fd: Int32) throws {
    let request = try JSONSerialization.data(withJSONObject: ["command": command.rawValue, "payload": ""])
    var size = UInt32(request.count).bigEndian
    let frame = withUnsafeBytes(of: &size) { Data($0) } + request
    try sendBytes(Array(frame), to: fd)
}

private func sendBytes(_ bytes: [UInt8], to fd: Int32) throws {
    for byte in bytes {
        var value = byte
        let count = Darwin.write(fd, &value, 1)
        guard count == 1 else { throw IPCError.unavailable }
    }
}

private final class LockedCallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }

    func value() -> Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}
