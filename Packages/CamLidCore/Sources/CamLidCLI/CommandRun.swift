import CamLidCore
import Dispatch
import Foundation

/// `camlid run -- <command> [arguments]` (ADR 0006, spec 018 US2). The app admits the command, and the admission keeps
/// the Mac awake while it runs; an Auto session starts when none runs. The command inherits this process's standard
/// streams. This process renews the admission every `CommandAdmissions.renewalInterval` seconds and finishes it when
/// the command exits. When the hold ends early, the command still runs and this process says so on stderr.
enum CommandRun {
    static func execute(arguments: [String], channel: (any IPCChannel)?) -> CLIResult {
        guard arguments.first == "--" else { return refusal(2, "missingSeparator") }
        guard arguments.count >= 2 else { return refusal(2, "missingCommand") }
        guard let channel else { return refusal(4, "appUnavailable") }
        let command = arguments[1]
        let commandArguments = Array(arguments.dropFirst(2))
        let receipt: CommandReceipt
        do {
            let admitted = try channel.send(
                command: .admitCommand, payload: JSONEncoder().encode(AdmitCommandRequest(label: "camlid run")))
            let result = try JSONDecoder().decode(CLIResult.self, from: admitted)
            // A refusal arrives as a reply with its reason, as `camlid start` replies do.
            guard result.exitCode == 0 else { return CLIResult(json: result.json, exitCode: result.exitCode) }
            receipt = try JSONDecoder().decode(CommandReceipt.self, from: Data(result.json.utf8))
        } catch IPCError.policyDenied(let reason) {
            return refusal(3, reason)
        } catch {
            return refusal(4, "appUnavailable")
        }
        let launch = RunCommand.resolvedLaunch(executable: command, args: commandArguments)
        let child = Process()
        child.executableURL = launch.url
        child.arguments = launch.arguments
        let started = Date()
        do {
            try child.run()
        } catch {
            // Same mapping as RunCommand: 126 for a file that exists but cannot be launched, 127 otherwise.
            let status: Int32 = command.contains("/") && FileManager.default.fileExists(atPath: command) ? 126 : 127
            finish(receipt, exitStatus: status, seconds: 0, channel: channel)
            writeNotice("\(command) could not be launched: \(error).")
            return CLIResult(json: "", exitCode: Int(status))
        }
        let session = RunSession(child: child, receipt: receipt, channel: channel)
        session.start(renewEvery: CommandAdmissions.renewalInterval)
        child.waitUntilExit()
        let status = RunCommand.shellExitStatus(
            terminationStatus: child.terminationStatus, reason: child.terminationReason)
        session.finish(exitStatus: status, seconds: Date().timeIntervalSince(started))
        return CLIResult(json: "", exitCode: Int(status))
    }

    /// A refused renewal is thrown with its reason, so the hold-ended notice can say why.
    static func renew(_ receipt: CommandReceipt, channel: any IPCChannel) throws -> CommandReceipt {
        let reply = try channel.send(
            command: .renewCommand, payload: JSONEncoder().encode(RenewCommandRequest(receipt: receipt)))
        let result = try JSONDecoder().decode(CLIResult.self, from: reply)
        guard result.exitCode == 0 else { throw IPCError.policyDenied(refusedReason(result.json)) }
        return try JSONDecoder().decode(CommandReceipt.self, from: Data(result.json.utf8))
    }

    static func refusedReason(_ json: String) -> String {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["reason"] as? String ?? "refused"
    }

    static func finish(_ receipt: CommandReceipt, exitStatus: Int32, seconds: Double, channel: any IPCChannel) {
        let payload = FinishCommandRequest(receipt: receipt, exitStatus: exitStatus, durationSeconds: seconds)
        _ = try? channel.send(command: .finishCommand, payload: JSONEncoder().encode(payload))
    }

    static func refusal(_ code: Int, _ reason: String) -> CLIResult {
        CLIResult(json: "{\"schemaVersion\":1,\"command\":\"run\",\"accepted\":false,\"reason\":\"\(reason)\"}",
                  exitCode: code)
    }

    static func writeNotice(_ message: String) {
        FileHandle.standardError.write(Data("camlid: \(message)\n".utf8))
    }
}

/// Renews one admission while its command runs and forwards interrupts to the command. Shared state is guarded by
/// `lock`. The timers run on their own queues, so waiting for the command never blocks them.
private final class RunSession: @unchecked Sendable {
    private let lock = NSLock()
    private let child: Process
    private let channel: any IPCChannel
    private var receipt: CommandReceipt
    private var holdEnded = false
    private var finished = false
    private var timer: DispatchSourceTimer?
    private var signalSources: [DispatchSourceSignal] = []
    private let renewQueue = DispatchQueue(label: "camlid.run.renew")
    private let signalQueue = DispatchQueue(label: "camlid.run.signals")

    init(child: Process, receipt: CommandReceipt, channel: any IPCChannel) {
        self.child = child
        self.receipt = receipt
        self.channel = channel
    }

    func start(renewEvery interval: Double) {
        // Ignored only after the child has started, so the child keeps the default handlers. CamLid waits for it.
        _ = signal(SIGINT, SIG_IGN)
        _ = signal(SIGTERM, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
        interrupt.setEventHandler { [weak self] in self?.forward { $0.interrupt() } }
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
        terminate.setEventHandler { [weak self] in self?.forward { $0.terminate() } }
        let renewals = DispatchSource.makeTimerSource(queue: renewQueue)
        renewals.schedule(deadline: .now() + interval, repeating: interval)
        renewals.setEventHandler { [weak self] in self?.renew() }
        lock.lock()
        signalSources = [interrupt, terminate]
        timer = renewals
        lock.unlock()
        interrupt.resume()
        terminate.resume()
        renewals.resume()
    }

    func finish(exitStatus: Int32, seconds: Double) {
        lock.lock()
        finished = true
        let current = receipt
        let renewals = timer
        let sources = signalSources
        lock.unlock()
        renewals?.cancel()
        sources.forEach { $0.cancel() }
        _ = signal(SIGINT, SIG_DFL)
        _ = signal(SIGTERM, SIG_DFL)
        CommandRun.finish(current, exitStatus: exitStatus, seconds: seconds, channel: channel)
    }

    private func forward(_ action: (Process) -> Void) {
        if child.isRunning { action(child) }
    }

    private func renew() {
        lock.lock()
        let current = receipt
        let stop = finished || holdEnded
        lock.unlock()
        guard !stop else { return }
        do {
            let next = try CommandRun.renew(current, channel: channel)
            lock.lock()
            receipt = next
            lock.unlock()
        } catch {
            lock.lock()
            holdEnded = true
            let renewals = timer
            lock.unlock()
            renewals?.cancel()
            var reason = "appUnavailable"
            if let ipc = error as? IPCError, case .policyDenied(let denied) = ipc { reason = denied }
            CommandRun.writeNotice("CamLid ended the hold (\(reason)). The command keeps running.")
        }
    }
}
