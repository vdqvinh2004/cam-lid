import Foundation
import CamLidCore
import Darwin

/// A worker writes only a private staging file. The authority alone installs it
/// after checking revision, cancellation and deadline. Late preparation cannot
/// install preferences. A final syscall already started may finish after its
/// deadline, so it reports uncertainty and holds serialization until completion.
final class PreferenceWritePreparer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.camlid.preference-preparation", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    private let writer: @Sendable (Data, URL) throws -> Void
    private let installer: @Sendable (URL, URL) throws -> Void
    init(writer: @escaping @Sendable (Data, URL) throws -> Void,
         installer: @escaping @Sendable (URL, URL) throws -> Void = { source, destination in
             guard Darwin.rename(source.path, destination.path) == 0 else {
                 throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
             }
         }) { self.writer = writer; self.installer = installer }

    enum InstallationOutcome: Sendable { case installed, failed, unconfirmed }

    /// A syscall already in progress cannot be cancelled. Report uncertainty
    /// on deadline, retain serialization until completion, and reconcile once.
    func install(_ source: URL, at destination: URL, deadline: Double,
                 completion: @escaping @Sendable (Bool) -> Void) async -> InstallationOutcome {
        guard reserve() else { discard(source); return .failed }
        let cancellation = InstallationCancellationGate()
        return await withTaskCancellationHandler { await withCheckedContinuation { continuation in
            let reply = InstallationReply(continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, deadline - ContinuousTime.now)) {
                reply.expire()
            }
            queue.async { [self] in
                guard reply.begin(deadline: deadline, cancellation: cancellation) else {
                    try? FileManager.default.removeItem(at: source)
                    release(); completion(false); reply.finish(.failed); return
                }
                let success: Bool
                do { try installer(source, destination); success = true } catch { success = false }
                try? FileManager.default.removeItem(at: source)
                release()
                completion(success)
                reply.finish(success ? .installed : .failed)
            }
        } } onCancel: { cancellation.cancel() }
    }

    func discard(_ source: URL) {
        queue.async { try? FileManager.default.removeItem(at: source) }
    }

    func prepare(_ data: Data, beside destination: URL, deadline: Double) async -> URL? {
        guard reserve() else { return nil }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".candidate-" + UUID().uuidString)
        return await withCheckedContinuation { continuation in
            let reply = PreparationReply(continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, deadline - ContinuousTime.now)) {
                reply.finish(nil)
            }
            queue.async { [self] in
                do {
                    try writer(data, temporary)
                    // Release before resuming the authority: its next serialized
                    // edit must not see a worker that has already finished as busy.
                    release()
                    guard ContinuousTime.now < deadline, reply.finish(temporary) else {
                        try? FileManager.default.removeItem(at: temporary); return
                    }
                } catch {
                    try? FileManager.default.removeItem(at: temporary)
                    release()
                    reply.finish(nil)
                }
            }
        }
    }
    private func reserve() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !busy else { return false }; busy = true; return true
    }
    private func release() { lock.lock(); busy = false; lock.unlock() }
}

private final class InstallationReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PreferenceWritePreparer.InstallationOutcome, Never>?
    private var started = false
    init(_ continuation: CheckedContinuation<PreferenceWritePreparer.InstallationOutcome, Never>) { self.continuation = continuation }
    func begin(deadline: Double, cancellation: InstallationCancellationGate) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard continuation != nil, ContinuousTime.now < deadline, cancellation.begin() else { return false }
        started = true; return true
    }
    func expire() {
        lock.lock(); let pending = continuation; continuation = nil
        let outcome: PreferenceWritePreparer.InstallationOutcome = started ? .unconfirmed : .failed
        lock.unlock(); pending?.resume(returning: outcome)
    }
    func finish(_ outcome: PreferenceWritePreparer.InstallationOutcome) {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(returning: outcome)
    }
}

private final class InstallationCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func begin() -> Bool {
        lock.lock(); defer { lock.unlock() }
        // This lock linearizes cancellation against admission to the syscall.
        return !cancelled
    }
}

private final class PreparationReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL?, Never>?
    init(_ continuation: CheckedContinuation<URL?, Never>) { self.continuation = continuation }
    @discardableResult func finish(_ url: URL?) -> Bool {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        guard let pending else { return false }; pending.resume(returning: url); return true
    }
}
