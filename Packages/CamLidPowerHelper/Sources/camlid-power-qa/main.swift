import Foundation
import Darwin
import ServiceManagement
import CamLidPowerService

@MainActor
private enum QACommand: String {
    case version = "--version", inspect = "--inspect"
    case registrationStatus = "--registration-status", acquire = "--acquire-24s"
    case acquireBestEffort = "--acquire-best-effort-900s"
    static func parse(_ arguments: [String]) -> QACommand? {
        guard arguments.count == 1 else { return nil }
        return QACommand(rawValue: arguments[0])
    }

    /// One fixed finite run per command. No re-arm, no resume, no implicit retry.
    var runPlan: BoundedRunPlan? {
        switch self {
        case .acquire: return BoundedRunPlan(sessionSeconds: 24, stopAfterSeconds: 18,
                                            deadlineSeconds: 27)
        case .acquireBestEffort: return BoundedRunPlan(sessionSeconds: 900, stopAfterSeconds: 894,
                                                      deadlineSeconds: 903)
        case .version, .inspect, .registrationStatus: return nil
        }
    }
}

private struct BoundedRunPlan: Sendable, Equatable {
    let sessionSeconds: Int
    let stopAfterSeconds: Double
    let deadlineSeconds: Double
}

private func printReply(_ reply: PowerReply) {
    if let data = try? JSONEncoder().encode(reply), let text = String(data: data, encoding: .utf8) { print(text) }
}

@MainActor
private final class BoundedLeaseRun: @unchecked Sendable {
    let client: PowerHelperClient
    let plan: BoundedRunPlan
    var token: UUID?
    var sequence: UInt64 = 1
    var stopping = false
    var releaseSent = false
    var timer: DispatchSourceTimer?
    var signals: [DispatchSourceSignal] = []

    init(client: PowerHelperClient, plan: BoundedRunPlan) {
        self.client = client
        self.plan = plan
    }

    func start() {
        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [self] in Task { @MainActor in stop() } }
            source.resume()
            signals.append(source)
        }
        client.perform(PowerRequest(operation: .acquire, sequence: 1,
                                   sessionSeconds: plan.sessionSeconds)) { [self] result in
            Task { @MainActor [self] in
                guard case .success(let reply) = result, reply.accepted, let granted = reply.token else {
                    if case .success(let reply) = result { printReply(reply) }
                    client.invalidate()
                    exit(3)
                }
                printReply(reply)
                token = granted
                if stopping { stop(); return }
                let source = DispatchSource.makeTimerSource(queue: .main)
                source.schedule(deadline: .now() + 10, repeating: 10)
                source.setEventHandler { [self] in Task { @MainActor in renew() } }
                timer = source
                source.resume()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + plan.stopAfterSeconds) { [self] in Task { @MainActor in stop() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + plan.deadlineSeconds) { [self] in Task { @MainActor in
            client.invalidate()
            fputs("Unverified cleanup: QA response deadline exceeded. No restoration claim.\n", stderr)
            exit(4)
        } }
    }

    private func renew() {
        guard !stopping, let token else { return }
        sequence += 1
        client.perform(PowerRequest(operation: .renew, token: token, sequence: sequence)) { [self] result in
            Task { @MainActor [self] in
                if case .success(let reply) = result, reply.accepted { printReply(reply) }
                else { stop() }
            }
        }
    }

    private func stop() {
        stopping = true
        timer?.cancel()
        timer = nil
        guard !releaseSent else { return }
        guard let token else {
            // No granted token: this client cannot ask for cleanup. Say so and exit now
            // instead of parking until the hard deadline with an unverified outcome.
            client.invalidate()
            fputs("No granted lease token: nothing to release. Helper-side lease expiry is the only bound.\n", stderr)
            exit(4)
        }
        releaseSent = true
        client.perform(PowerRequest(operation: .release, token: token)) { [self] result in
            Task { @MainActor [self] in
                if case .success(let reply) = result {
                    printReply(reply)
                    client.invalidate()
                    exit(QAExit.forRelease(state: reply.state))
                }
                client.invalidate()
                fputs("Unverified cleanup: helper reply unavailable.\n", stderr)
                exit(4)
            }
        }
    }
}

/// Distinct exits so a caller cannot read acknowledgement as verified restoration.
/// 0 = verified readback; 5 = cleanup calls acknowledged, shared restoration NOT verified.
private enum QAExit {
    static func forRelease(state: String) -> Int32 {
        if state == "restored" { return 0 }
        if state == "cleanupAcknowledged" { return 5 }
        return 4
    }
}

/// Runs the main dispatch queue on the process main thread until the process exits.
///
/// `dispatchMain()` is deliberately not used: on the current OS/toolchain it can
/// service the main queue off the process main thread after a `Task { @MainActor }`
/// hop from a non-main completion (an XPC reply), which is the condition the
/// concurrency runtime reports as "data race detected: @MainActor function ... was
/// not called on the main thread". The main run loop services the main queue on the
/// main thread; the measured comparison lives in
/// `docs/qa/preview-evidence/power-helper-best-effort-2026-10-19/race-probe-2026-10-19/`.
private func runMainForever() -> Never {
    while true { RunLoop.main.run(until: .distantFuture) }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--self-test"] {
    guard QACommand.parse(["--inspect"]) == .inspect,
          QACommand.parse(["--acquire-24s"]) == .acquire,
          QACommand.parse(["--acquire-best-effort-900s"]) == .acquireBestEffort,
          QACommand.parse([]) == nil,
          QACommand.parse(["--acquire-24s", "extra"]) == nil,
          QACommand.parse(["--shell"]) == nil,
          QACommand.parse(["--register"]) == nil else { fatalError("argument boundary failed") }
    // Read-only plans: no client, service, journal, assertion or selector call happens here.
    guard QACommand.acquire.runPlan == BoundedRunPlan(sessionSeconds: 24, stopAfterSeconds: 18,
                                                      deadlineSeconds: 27),
          QACommand.acquireBestEffort.runPlan == BoundedRunPlan(sessionSeconds: 900, stopAfterSeconds: 894,
                                                                deadlineSeconds: 903),
          QACommand.inspect.runPlan == nil, QACommand.version.runPlan == nil,
          QACommand.registrationStatus.runPlan == nil else { fatalError("run plan boundary failed") }
    guard QAExit.forRelease(state: "restored") == 0,
          QAExit.forRelease(state: "cleanupAcknowledged") == 5,
          QAExit.forRelease(state: "recoveryRequired") == 4,
          QAExit.forRelease(state: "starting") == 4 else { fatalError("exit contract failed") }
    print("PASS: fixed QA commands and bounded run plans; no service/auth/power operations invoked")
    exit(0)
}
guard let command = QACommand.parse(arguments) else {
    print("CamLid power candidate QA: --version | --registration-status | --inspect")
    print("--acquire-24s requires separate exact approval. --acquire-best-effort-900s is a single finite")
    print("900s candidate session, not a product mode. Local daemon installation is external to this client.")
    print("No command executed.")
    exit(64)
}
if command == .version {
    print("CamLid power QA 1; qualification false; no power action")
    exit(0)
}

do {
    guard geteuid() > 0, Bundle.main.bundleURL.pathExtension == "app" else { throw PowerServiceFailure.invalidRequest }
    if command == .registrationStatus {
        let status = SMAppService.statusForLegacyPlist(at: URL(fileURLWithPath: "/Library/LaunchDaemons/com.camlid.power-helper.plist"))
        print("registrationStatus=\(status.rawValue); no registration or power action")
        exit(0)
    }
    let client = try PowerHelperClient()
    if command == .inspect {
        client.perform(PowerRequest(operation: .inspect)) { result in
            Task { @MainActor in
                if case .success(let reply) = result {
                    printReply(reply)
                    client.invalidate()
                    exit(reply.accepted ? 0 : 3)
                }
                client.invalidate()
                fputs("Helper unavailable or authentication refused; no lease requested.\n", stderr)
                exit(3)
            }
        }
        withExtendedLifetime(client) { runMainForever() }
    }
    guard let plan = command.runPlan else {
    fputs("Refused: no bounded run plan for this command.\n", stderr)
    exit(64)
}
fputs("WARNING: this exact command requests a privileged power-policy lease for at most \(plan.sessionSeconds) seconds. Helper/OS failure can leave policy cleanup unverified; this is not a physical qualification.\n", stderr)
if plan.sessionSeconds > 24 {
    fputs("WARNING: cleanup acknowledgement is not verified shared-bit restoration. One attempt per separately approved recovery boundary; a prior journal can refuse this run.\n", stderr)
}
let run = BoundedLeaseRun(client: client, plan: plan)
Task { @MainActor in run.start() }
withExtendedLifetime(run) { runMainForever() }
} catch {
    fputs("Refused: signed app bundle, protected identity or registration prerequisite missing.\n", stderr)
    exit(78)
}
