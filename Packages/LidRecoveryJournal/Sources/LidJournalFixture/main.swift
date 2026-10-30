import Foundation
import Darwin
@_spi(FaultInjection) import LidRecoveryJournal

// Test fixture only. No power calls, assertion creation, or process supervision.
private struct PausedPublisher: JournalSystemCalls {
    let signals: URL
    private let real = DarwinJournalSystemCalls()

    func write(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {
        real.write(fd, bytes, count)
    }
    func synchronize(_ fd: Int32) -> Int32 { real.synchronize(fd) }
    func publish(directoryFD: Int32, temporaryName: String, finalName: String) -> Int32 {
        do {
            try Data().write(to: signals.appendingPathComponent("paused"))
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !FileManager.default.fileExists(atPath: signals.appendingPathComponent("resume").path) {
                guard ContinuousClock.now < deadline else { errno = ETIMEDOUT; return -1 }
                Thread.sleep(forTimeInterval: 0.01)
            }
            return real.publish(directoryFD: directoryFD, temporaryName: temporaryName, finalName: finalName)
        } catch {
            errno = EIO
            return -1
        }
    }
}

let args = CommandLine.arguments
// load <journal> | update <journal> | pause <journal> <private signals>
guard args.count >= 3 else { exit(64) }
do {
    let directory = URL(fileURLWithPath: args[2], isDirectory: true)
    let journal: DurableRecoveryJournal
    if args[1] == "pause", args.count == 4 {
        journal = try DurableRecoveryJournal(directory: directory,
            systemCalls: PausedPublisher(signals: URL(fileURLWithPath: args[3], isDirectory: true)))
    } else {
        journal = try DurableRecoveryJournal(directory: directory)
    }
    if args[1] == "load" {
        guard let entry = try journal.load() else { exit(2) }
        print(String(decoding: try JSONEncoder().encode(entry), as: UTF8.self))
    } else if args[1] == "update" || args[1] == "pause" {
        guard let previous = try journal.load() else { exit(2) }
        let next = JournalEntry(revision: 2, sessionID: previous.sessionID,
            ownerIdentity: previous.ownerIdentity, bootID: previous.bootID,
            generation: previous.generation, operationID: args[1], intent: .restoreLidPolicy,
            disposition: .unresolved, continuousDeadlineNanos: previous.continuousDeadlineNanos)
        try journal.commit(next, replacing: 1)
    } else { exit(64) }
} catch JournalFailure.revisionConflict { exit(3) }
catch JournalFailure.busy { exit(4) }
catch { print("fixture failure: \(error)"); exit(1) }
