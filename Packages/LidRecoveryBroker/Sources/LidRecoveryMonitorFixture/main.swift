import Foundation
import Darwin
import LidRecoveryBroker

// Separately pinned, owned test process. Records intent only, never physical restoration.
do {
    let args = CommandLine.arguments
    guard args.count == 6 || args.count == 7 else { exit(64) }
    let pause = args.count == 7 ? args[6] : nil
    guard pause == nil || pause == "outsideJournal" || pause == "withJournal" else { exit(64) }
    var paused = false
    let executor = try InertRecoveryExecutor(directory: URL(fileURLWithPath: args[1]))
    let pin = try CodeIdentityPin(cdhash: args[3])
    let output = URL(fileURLWithPath: args[4])
    try Data("ready".utf8).write(to: URL(fileURLWithPath: args[5]), options: .atomic)
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while ContinuousClock.now < deadline {
        do {
            let result = try executor.reconcile(brokerPath: args[2], serverPin: pin)
            try JSONEncoder().encode(result).write(to: output, options: .atomic)
            if !paused, result.reason == "waiting", let pause {
                var lockFD: Int32 = -1
                defer { if lockFD >= 0 { flock(lockFD, LOCK_UN); Darwin.close(lockFD) } }
                if pause == "withJournal" {
                    lockFD = Darwin.open(URL(fileURLWithPath: args[1]).appendingPathComponent(".journal.lock").path,
                        O_RDWR | O_NOFOLLOW | O_CLOEXEC)
                    guard lockFD >= 0 else { throw BrokerFailure.transport(errno) }
                    let limit = ContinuousClock.now.advanced(by: .seconds(1))
                    var locked = false
                    while ContinuousClock.now < limit {
                        if flock(lockFD, LOCK_EX | LOCK_NB) == 0 { locked = true; break }
                        guard errno == EWOULDBLOCK || errno == EAGAIN else { throw BrokerFailure.transport(errno) }
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                    guard locked else { throw BrokerFailure.timeout }
                }
                // Pause location is explicit; an arbitrary SIGSTOP can retain the cooperative journal lock.
                guard raise(SIGSTOP) == 0 else { throw BrokerFailure.transport(errno) }
                paused = true
            }
            if !["waiting", "noRecord", "journalBusyUnresolved", "journalConflictUnresolved"].contains(result.reason) {
                exit(0)
            }
        } catch {
            let diagnostic: [String: Any] = ["reason": "executorFaultUnresolved", "revision": NSNull(),
                "powerActuation": false, "protectionAvailable": false, "error": String(describing: error)]
            try JSONSerialization.data(withJSONObject: diagnostic).write(to: output, options: .atomic)
            throw error
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    exit(4)
} catch {
    fputs("owned monitor fixture: \(error)\n", stderr)
    exit(3)
}
