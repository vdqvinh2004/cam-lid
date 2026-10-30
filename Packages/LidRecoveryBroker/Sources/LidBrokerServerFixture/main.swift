import Foundation
import Darwin
import LidRecoveryJournal
@_spi(TestInputs) import LidRecoveryBroker

// Owned test server only. No registration, power calls or foreign-process control.
do {
    let args = CommandLine.arguments
    guard args.count == 6 else { exit(64) }
    let broker = try RecoveryBroker(directory: URL(fileURLWithPath: args[1]),
        trustedClients: [CodeIdentityPin(cdhash: args[3])], trustedMonitors: [CodeIdentityPin(cdhash: args[4])])
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw BrokerFailure.transport(errno) }
    defer { Darwin.close(fd); unlink(args[2]) }
    var address = try socketAddress(args[2])
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bound == 0, chmod(args[2], 0o600) == 0, listen(fd, 8) == 0 else {
        throw BrokerFailure.transport(errno)
    }
    try Data("ready".utf8).write(to: URL(fileURLWithPath: args[5]), options: .atomic)
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    let root = URL(fileURLWithPath: args[1]).deletingLastPathComponent()
    var pausedWithLock = false
    while ContinuousClock.now < deadline {
        if !pausedWithLock, FileManager.default.fileExists(atPath: root.appendingPathComponent("lock.trigger").path) {
            let lockFD = Darwin.open(URL(fileURLWithPath: args[1]).appendingPathComponent(".journal.lock").path,
                O_RDWR | O_CLOEXEC)
            guard lockFD >= 0 else { throw BrokerFailure.transport(errno) }
            defer { Darwin.close(lockFD) }
            let limit = ContinuousClock.now.advanced(by: .seconds(1))
            var locked = false
            while ContinuousClock.now < limit {
                if flock(lockFD, LOCK_EX | LOCK_NB) == 0 { locked = true; break }
                guard errno == EWOULDBLOCK || errno == EAGAIN else { throw BrokerFailure.transport(errno) }
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard locked else { throw BrokerFailure.timeout }
            defer { flock(lockFD, LOCK_UN) }
            try Data("locked".utf8).write(to: root.appendingPathComponent("lock.ready"), options: .atomic)
            guard raise(SIGSTOP) == 0 else { throw BrokerFailure.transport(errno) }
            pausedWithLock = true
        }
        do { try broker.poll() }
        catch JournalFailure.busy {
            // poll already revoked the lease; contention defers observation, never re-admission.
            fputs("owned broker poll deferred: busy\n", stderr)
        }
        var item = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let result = poll(&item, 1, 50)
        if result < 0, errno == EINTR { continue }
        guard result >= 0 else { throw BrokerFailure.transport(errno) }
        if result == 0 { continue }
        let accepted = accept(fd, nil, nil)
        guard accepted >= 0 else { throw BrokerFailure.transport(errno) }
        do { try broker.serveConnection(accepted) }
        catch { fputs("owned broker request refused: \(error)\n", stderr) }
        Darwin.close(accepted)
    }
} catch {
    fputs("owned broker fixture: \(error)\n", stderr)
    exit(3)
}
