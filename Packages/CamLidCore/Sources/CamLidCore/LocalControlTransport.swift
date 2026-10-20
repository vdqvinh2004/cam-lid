import Foundation
import Darwin
import Dispatch

/// Preview app/CLI transport. Filesystem ownership plus kernel peer credentials
/// authenticate both ends. No TCP, privileges, shell commands, or power calls.
public struct LocalControlChannel: IPCChannel {
    public let directory: URL
    public static var defaultDirectory: URL { URL(fileURLWithPath: "/tmp/camlid-\(getuid())", isDirectory: true) }
    public init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    public func send(command: AllowlistedCommand, payload: Data) throws -> Data {
        _ = try BoundedPayload(payload)
        try LocalSocket.validateDirectory(directory, create: false)
        let fd = try LocalSocket.connect(directory.appendingPathComponent("control.sock").path)
        defer { Darwin.close(fd) }
        try LocalSocket.authenticate(fd)
        let request = try JSONEncoder().encode(ControlWireRequest(command: command, payload: payload))
        try LocalSocket.writeFrame(request, fd: fd)
        let response = try JSONDecoder().decode(ControlWireResponse.self,
            from: LocalSocket.readFrame(fd: fd, timeout: command == .diagnose ? 6 : 3,
                maximum: command == .diagnose ? PolicyLimits.maxEventBytes : (ActivityStore.defaultMaxBytes + 2) / 3 * 4 + 65_536))
        switch response.error {
        case "unauthorized": throw IPCError.unauthorized
        case "invalidInput": throw IPCError.invalidInput("invalidControlRequest")
        case "policyDenied": throw IPCError.policyDenied("controlDenied")
        case .some: throw IPCError.unavailable
        case .none: return response.payload ?? Data()
        }
    }
}

private struct ControlWireRequest: Codable, Sendable { let command: AllowlistedCommand; let payload: Data }
private struct ControlWireResponse: Codable, Sendable { let payload: Data?; let error: String? }

public final class LocalControlServer: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var ownership: Int32 = -1
    private var socketIdentity: LocalSocket.FileIdentity?
    private var generation: UInt64 = 0
    private var stopping = false
    private var listenerSource: DispatchSourceRead?
    private var listenerStopped: DispatchSemaphore?
    private var clients: [UUID: ControlConnection] = [:]
    private var responseReservations: [UUID: (bytes: Int, priority: Bool)] = [:]
    private var priorityResponseBytes = 0
    private var responseBytes = 0
    static let maxConnections = 32
    static let maxResponseBytes = 64 * 1_024 * 1_024
    static let priorityResponseLimit = 1 * 1_024 * 1_024
    static let ordinaryResponseLimit = maxResponseBytes - priorityResponseLimit
    private let directory: URL
    private let acceptQueue = DispatchQueue(label: "camlid.local-control.accept")
    private let workerQueue = DispatchQueue(label: "camlid.local-control.workers", attributes: .concurrent)
    private let workerSlots = DispatchSemaphore(value: 6)
    private let controlSlots = DispatchSemaphore(value: 2)
    private let exportSlots = DispatchSemaphore(value: 1)
    // Handler capacity is separate from frame reception and response writes.
    private let controlQueue = DispatchQueue(label: "camlid.local-control.priority", attributes: .concurrent)
    private let exportQueue = DispatchQueue(label: "camlid.local-control.export")
    public init(directory: URL = LocalControlChannel.defaultDirectory) { self.directory = directory }
    deinit { stop() }

    public func start(handler: @escaping @Sendable (AllowlistedCommand, Data) throws -> Data) throws {
        lock.lock(); defer { lock.unlock() }
        guard descriptor == -1, !stopping else { throw IPCError.policyDenied("alreadyListening") }
        try LocalSocket.validateDirectory(directory, create: true)
        let ownerPath = directory.appendingPathComponent("owner.lock").path
        let owned = Darwin.open(ownerPath, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard owned >= 0 else { throw IPCError.policyDenied("ownerOpenErrno\(errno)") }
        var ownerInfo = stat()
        guard fstat(owned, &ownerInfo) == 0,
              ownerInfo.st_uid == getuid(),
              (ownerInfo.st_mode & S_IFMT) == S_IFREG,
              (ownerInfo.st_mode & 0o077) == 0 else {
            Darwin.close(owned)
            throw IPCError.unauthorized
        }
        guard flock(owned, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(owned); throw IPCError.policyDenied("appAlreadyRunning") }
        let path = directory.appendingPathComponent("control.sock").path
        var fd: Int32 = -1
        var boundIdentity: LocalSocket.FileIdentity?
        do {
            var attributes = stat()
            if lstat(path, &attributes) == 0 {
                guard attributes.st_uid == getuid(), (attributes.st_mode & S_IFMT) == S_IFSOCK else { throw IPCError.unauthorized }
                guard unlink(path) == 0 else { throw IPCError.unavailable }
            } else if errno != ENOENT {
                throw IPCError.unavailable
            }
            fd = try LocalSocket.listen(path)
            boundIdentity = try LocalSocket.fileIdentity(at: path)
        } catch {
            if fd >= 0 {
                _ = shutdown(fd, SHUT_RDWR)
                Darwin.close(fd)
                if let boundIdentity { LocalSocket.unlinkIfMatching(path, identity: boundIdentity) }
            }
            Darwin.close(owned)
            throw error
        }

        generation &+= 1
        let token = generation
        let stopped = DispatchSemaphore(value: 0)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptReady(fd: fd, generation: token, handler: handler)
        }
        source.setCancelHandler {
            Darwin.close(fd)
            stopped.signal()
        }
        descriptor = fd
        ownership = owned
        socketIdentity = boundIdentity
        listenerSource = source
        listenerStopped = stopped
        source.resume()
    }

    private func isListening(_ fd: Int32, generation token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return descriptor == fd && generation == token && !stopping
    }

    // Read-only bounded diagnostics for transport QA; no per-client identities.
    var resourceCounts: (connections: Int, responseBytes: Int) {
        lock.lock(); defer { lock.unlock() }
        return (clients.count, responseBytes)
    }

    private func removeConnection(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        clients.removeValue(forKey: id)
        if let reserved = responseReservations.removeValue(forKey: id) {
            responseBytes -= reserved.bytes
            if reserved.priority { priorityResponseBytes -= reserved.bytes }
        }
    }

    private func acceptReady(
        fd: Int32,
        generation token: UInt64,
        handler: @escaping @Sendable (AllowlistedCommand, Data) throws -> Data
    ) {
        // Yield to frame/read/timer callbacks even under a continuous accept flood.
        for _ in 0..<16 {
            guard isListening(fd, generation: token) else { return }
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            do {
                let flags = fcntl(client, F_GETFL)
                guard flags >= 0,
                      fcntl(client, F_SETFD, FD_CLOEXEC) == 0,
                      fcntl(client, F_SETFL, flags | O_NONBLOCK) == 0 else { throw IPCError.unavailable }
                LocalSocket.setTimeout(client)
                try LocalSocket.authenticate(client)
            } catch {
                Darwin.close(client)
                continue
            }
            // These stage reads occur only on acceptQueue. Never evict a
            // complete/admitted mutation. Incomplete readers and already-
            // computed read-only replies may yield to a newly accepted client.
            lock.lock()
            let oldestReader = clients.values.filter {
                $0.isPreemptible || ($0.isReadOnly && responseReservations[$0.id] != nil)
            }.min {
                if $0.isReading != $1.isReading { return $0.isReading }
                return $0.createdAt < $1.createdAt
            }
            let full = clients.count >= Self.maxConnections
            let current = descriptor == fd && generation == token && !stopping
            lock.unlock()
            if full { oldestReader?.finish() }
            lock.lock()
            guard current, descriptor == fd, generation == token, !stopping,
                  clients.count < Self.maxConnections else {
                lock.unlock(); Darwin.close(client); continue
            }
            let connection = ControlConnection(fd: client, queue: acceptQueue,
                onRequest: { [weak self] connection, request in
                    self?.dispatch(request, connection: connection, listener: fd, generation: token, handler: handler)
                }, onClose: { [weak self] id in self?.removeConnection(id) })
            clients[connection.id] = connection
            lock.unlock()
            connection.start()
        }
    }

    private func dispatch(
        _ request: ControlWireRequest,
        connection: ControlConnection,
        listener fd: Int32,
        generation token: UInt64,
        handler: @escaping @Sendable (AllowlistedCommand, Data) throws -> Data
    ) {
        guard isListening(fd, generation: token) else { connection.finish(); return }
        let priority = [.status, .stop, .quit, .doctor].contains(request.command)
        let bulk = request.command == .logsExport
        let slots = priority ? controlSlots : (bulk ? exportSlots : workerSlots)
        let queue = priority ? controlQueue : (bulk ? exportQueue : workerQueue)
        guard slots.wait(timeout: .now()) == .success else {
            respond(connection, payload: nil, error: "unavailable", priority: priority)
            return
        }
        queue.async { [weak self] in
            defer { slots.signal() }
            guard let self, self.isListening(fd, generation: token) else {
                connection.cancel(); return
            }
            do {
                let output = try handler(request.command, request.payload)
                guard self.isListening(fd, generation: token) else { connection.cancel(); return }
                // Diagnosis also fits the base64 wire envelope, not only its decoded payload.
                guard output.count <= (request.command == .diagnose ? (PolicyLimits.maxEventBytes - 1_024) / 4 * 3 : ActivityStore.defaultMaxBytes) else { throw IPCError.tooLarge(output.count) }
                self.respond(connection, payload: output, error: nil, priority: priority)
            } catch {
                guard self.isListening(fd, generation: token) else { connection.cancel(); return }
                let code: String
                switch error {
                case IPCError.unauthorized: code = "unauthorized"
                case IPCError.invalidInput, IPCError.tooLarge: code = "invalidInput"
                case IPCError.policyDenied: code = "policyDenied"
                default: code = "unavailable"
                }
                self.respond(connection, payload: nil, error: code, priority: priority)
            }
        }
    }

    private func respond(_ connection: ControlConnection, payload: Data?, error: String?, priority: Bool) {
        // Reserve encoded bytes before encoding large exports. Slow readers
        // have a finite aggregate memory allowance and occupy no handler slot.
        let reservation = ((payload?.count ?? 0) + 2) / 3 * 4 + 1_024
        lock.lock()
        let admitted = clients[connection.id] != nil && responseReservations[connection.id] == nil &&
            reservation <= (priority ? Self.priorityResponseLimit - priorityResponseBytes : Self.ordinaryResponseLimit - (responseBytes - priorityResponseBytes))
        if admitted {
            responseReservations[connection.id] = (reservation, priority)
            responseBytes += reservation
            if priority { priorityResponseBytes += reservation }
        }
        lock.unlock()
        guard admitted else { connection.cancel(); return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            let bytes = try encoder.encode(ControlWireResponse(payload: payload, error: error))
            guard bytes.count + 4 <= reservation else { connection.cancel(); return }
            connection.respond(bytes)
        } catch { connection.cancel() }
    }

    /// Closes this generation's listener and clients before releasing ownership.
    /// Already admitted handler closures are not cancelled or drained. Callers
    /// must close mutation admission and settle their writes before stopping.
    /// Generation checks prevent those handlers replying through a new server.
    public func stop() {
        lock.lock()
        guard descriptor >= 0 else { lock.unlock(); return }
        stopping = true
        let fd = descriptor
        descriptor = -1
        generation &+= 1
        let source = listenerSource
        listenerSource = nil
        let stopped = listenerStopped
        listenerStopped = nil
        let identity = socketIdentity
        socketIdentity = nil
        let owned = ownership
        ownership = -1
        _ = shutdown(fd, SHUT_RDWR)
        let connections = Array(clients.values)
        lock.unlock()

        source?.cancel()
        connections.forEach { $0.cancel() }
        stopped?.wait()
        connections.forEach { $0.closed.wait() }
        if let identity {
            LocalSocket.unlinkIfMatching(
                directory.appendingPathComponent("control.sock").path,
                identity: identity
            )
        }
        if owned >= 0 { Darwin.close(owned) }

        lock.lock(); stopping = false; lock.unlock()
    }
}

/// All frame state lives on the server's serial I/O queue. The read source
/// owns the fd until its cancellation handler, preventing fd reuse races.
private final class ControlConnection: @unchecked Sendable {
    let id = UUID()
    let createdAt = ContinuousTime.now
    let closed = DispatchSemaphore(value: 0)
    private let fd: Int32
    private let queue: DispatchQueue
    private let onRequest: @Sendable (ControlConnection, ControlWireRequest) -> Void
    private let onClose: @Sendable (UUID) -> Void
    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var timer: DispatchSourceTimer?
    private var readSuspended = false
    private var finished = false
    private(set) var isReading = true
    private var command: AllowlistedCommand?
    var isReadOnly: Bool {
        command.map { [.status, .doctor, .agentsList, .configGet, .configValidate, .simulate, .logsExport].contains($0) } == true
    }
    var isPreemptible: Bool {
        isReading || (writeSource != nil && isReadOnly)
    }
    private var deadline = ContinuousTime.now + 3
    private var incoming = Data()
    private var expected: Int?
    private var outgoing = Data()
    private var written = 0

    init(fd: Int32, queue: DispatchQueue,
         onRequest: @escaping @Sendable (ControlConnection, ControlWireRequest) -> Void,
         onClose: @escaping @Sendable (UUID) -> Void) {
        self.fd = fd; self.queue = queue; self.onRequest = onRequest; self.onClose = onClose
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readReady() }
        let fd = fd, closed = closed
        source.setCancelHandler { Darwin.close(fd); closed.signal() }
        readSource = source
        let clock = DispatchSource.makeTimerSource(queue: queue)
        clock.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        clock.setEventHandler { [weak self] in
            guard let self, !self.finished, ContinuousTime.now >= self.deadline else { return }
            if self.isReading { self.replyError("unavailable") } else { self.finish() }
        }
        timer = clock
        source.resume(); clock.resume()
    }

    private func readReady() {
        guard !finished, isReading else { return }
        guard ContinuousTime.now < deadline else { replyError("unavailable"); return }
        while true {
            let remaining = (expected ?? 4) - incoming.count
            if remaining == 0 {
                if expected == nil {
                    let size = incoming.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    guard size <= 90_000 else { replyError("invalidInput"); return }
                    expected = Int(size); incoming.removeAll(keepingCapacity: true)
                    continue
                }
                guard ContinuousTime.now < deadline else { replyError("unavailable"); return }
                do {
                    let request = try JSONDecoder().decode(ControlWireRequest.self, from: incoming)
                    _ = try BoundedPayload(request.payload)
                    command = request.command
                    incoming = Data()
                    stopReading()
                    deadline = ContinuousTime.now + (request.command == .diagnose ? 6 : 3)
                    onRequest(self, request)
                } catch { replyError("invalidInput") }
                return
            }
            var buffer = [UInt8](repeating: 0, count: min(8_192, remaining))
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
            guard count > 0 else { finish(); return }
            incoming.append(contentsOf: buffer.prefix(count))
        }
    }

    private func stopReading() {
        isReading = false
        if !readSuspended { readSource?.suspend(); readSuspended = true }
    }

    private func replyError(_ code: String) {
        guard !finished else { return }
        guard let bytes = try? JSONEncoder().encode(ControlWireResponse(payload: nil, error: code)) else { finish(); return }
        beginResponse(bytes)
    }

    func respond(_ bytes: Data) {
        queue.async { [self] in
            guard !finished, !isReading, ContinuousTime.now < deadline else { finish(); return }
            beginResponse(bytes)
        }
    }

    private func beginResponse(_ bytes: Data) {
        guard !finished, writeSource == nil else { return }
        stopReading()
        incoming = Data()
        deadline = ContinuousTime.now + 3
        var size = UInt32(bytes.count).bigEndian
        outgoing = withUnsafeBytes(of: &size) { Data($0) }
        outgoing.append(bytes)
        let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.writeReady() }
        writeSource = source
        source.resume()
    }

    private func writeReady() {
        guard !finished else { return }
        guard ContinuousTime.now < deadline else { finish(); return }
        // Bound each callback so large exports cannot monopolize the I/O queue.
        var budget = 65_536
        while written < outgoing.count && budget > 0 {
            let count = outgoing.withUnsafeBytes { buffer in
                Darwin.write(fd, buffer.baseAddress!.advanced(by: written), min(budget, buffer.count - written))
            }
            if count < 0 && errno == EINTR { continue }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
            guard count > 0 else { finish(); return }
            written += count; budget -= count
        }
        if written == outgoing.count { finish() }
    }

    func cancel() { queue.async { [self] in finish() } }

    func finish() {
        guard !finished else { return }
        finished = true
        onClose(id)
        _ = shutdown(fd, SHUT_RDWR)
        timer?.cancel(); timer = nil
        writeSource?.cancel(); writeSource = nil
        if readSuspended { readSource?.resume(); readSuspended = false }
        readSource?.cancel(); readSource = nil
        incoming = Data(); outgoing = Data()
    }
}

private enum LocalSocket {
    fileprivate struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    static func validateDirectory(_ directory: URL, create: Bool) throws {
        var info = stat()
        if create, lstat(directory.path, &info) != 0 {
            guard errno == ENOENT else { throw IPCError.unavailable }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        guard lstat(directory.path, &info) == 0 else { throw IPCError.unavailable }
        guard info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFDIR,
            (info.st_mode & 0o077) == 0 else { throw IPCError.unauthorized }
    }
    static func fileIdentity(at path: String) throws -> FileIdentity {
        var info = stat()
        guard lstat(path, &info) == 0,
              info.st_uid == getuid(),
              (info.st_mode & S_IFMT) == S_IFSOCK,
              (info.st_mode & 0o077) == 0 else { throw IPCError.unauthorized }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }
    static func unlinkIfMatching(_ path: String, identity: FileIdentity) {
        var info = stat()
        guard lstat(path, &info) == 0,
              info.st_uid == getuid(),
              (info.st_mode & S_IFMT) == S_IFSOCK,
              FileIdentity(device: info.st_dev, inode: info.st_ino) == identity else { return }
        _ = unlink(path)
    }
    static func authenticate(_ fd: Int32) throws {
        var uid: uid_t = 0; var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw IPCError.unauthorized }
    }
    static func address(_ path: String) throws -> sockaddr_un {
        var result = sockaddr_un()
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: result.sun_path) else { throw IPCError.invalidInput("socketPathTooLong") }
        result.sun_family = sa_family_t(AF_UNIX)
        result.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &result.sun_path) { buffer in buffer.copyBytes(from: bytes) }
        return result
    }
    static func socketFD() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.unavailable }
        var enabled: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        return fd
    }
    static func setTimeout(_ fd: Int32) {
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }
    static func connect(_ path: String) throws -> Int32 {
        var addr = try address(path)
        let fd = try socketFD()
        setTimeout(fd)
        let originalFlags = fcntl(fd, F_GETFL)
        guard originalFlags >= 0, fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK) == 0 else { Darwin.close(fd); throw IPCError.unavailable }
        let connected = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if connected != 0 {
            guard errno == EINPROGRESS else { Darwin.close(fd); throw IPCError.unavailable }
            var pollState = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&pollState, 1, 1_000) > 0 else { Darwin.close(fd); throw IPCError.unavailable }
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0, socketError == 0 else { Darwin.close(fd); throw IPCError.unavailable }
        }
        // Keep the connected socket nonblocking so framed I/O can enforce one
        // absolute deadline instead of extending a request per partial read.
        return fd
    }
    static func listen(_ path: String) throws -> Int32 {
        var addr = try address(path)
        let fd = try socketFD()
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { let code = errno; Darwin.close(fd); throw IPCError.policyDenied("socketBindErrno\(code)") }
        guard chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else { let code = errno; Darwin.close(fd); throw IPCError.policyDenied("socketListenErrno\(code)") }
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw IPCError.policyDenied("socketNonblockingErrno\(code)")
        }
        return fd
    }
    static func writeFrame(_ data: Data, fd: Int32) throws {
        let deadline = ContinuousTime.now + 3
        var size = UInt32(data.count).bigEndian
        let header = withUnsafeBytes(of: &size) { Data($0) }
        try write(header, fd: fd, deadline: deadline)
        try write(data, fd: fd, deadline: deadline)
    }
    static func write(_ data: Data, fd: Int32, deadline: Double) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                guard ContinuousTime.now < deadline else { throw IPCError.unavailable }
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    try wait(fd: fd, events: Int16(POLLOUT), until: deadline)
                    continue
                }
                guard count > 0 else { throw IPCError.unavailable }
                offset += count
            }
        }
    }
    static func readFrame(fd: Int32, timeout: Double = 3, maximum: Int) throws -> Data {
        let deadline = ContinuousTime.now + timeout
        let header = try read(count: 4, fd: fd, deadline: deadline)
        let count = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard count <= maximum else { throw IPCError.tooLarge(Int(count)) }
        let body = try read(count: Int(count), fd: fd, deadline: deadline)
        guard ContinuousTime.now < deadline else { throw IPCError.unavailable }
        return body
    }
    static func read(count: Int, fd: Int32, deadline: Double) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                guard ContinuousTime.now < deadline else { throw IPCError.unavailable }
                let read = Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
                if read < 0 && errno == EINTR { continue }
                if read < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    try wait(fd: fd, events: Int16(POLLIN), until: deadline)
                    continue
                }
                guard read > 0 else { throw IPCError.unavailable }
                offset += read
            }
        }
        return data
    }

    private static func wait(fd: Int32, events: Int16, until deadline: Double) throws {
        while true {
            let remaining = deadline - ContinuousTime.now
            guard remaining > 0 else { throw IPCError.unavailable }
            let milliseconds = Int32(max(1, min(100, ceil(remaining * 1_000))))
            var state = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&state, 1, milliseconds)
            if result < 0 && errno == EINTR { continue }
            if result < 0 { throw IPCError.unavailable }
            if result == 0 { continue }
            if state.revents & Int16(POLLNVAL) != 0 { throw IPCError.unavailable }
            if state.revents & (events | Int16(POLLERR) | Int16(POLLHUP)) != 0 { return }
        }
    }
}
