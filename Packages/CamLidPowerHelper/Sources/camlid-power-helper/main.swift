import Foundation
import Darwin
import CamLidPowerService

// Exit callbacks are plain functions, not closure literals: closures written in top-level code are inferred to be
// main-actor isolated, and these run on the runtime's queue (that mismatch was logged as a data race at shutdown).
func exitAfterShutdown() { exit(0) }
func exitAfterFailedStart() {
    logLine("exiting after a failed start so launchd restarts the helper with a fresh pmset runner")
    exit(75)
}

/// One line per state transition, timestamped, to stdout (launchd writes it to the daemon's log file).
func logLine(_ text: String) {
    print("\(Date().formatted(.iso8601)) pid=\(getpid()) \(text)")
    fflush(stdout)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--version"] {
    print("CamLid power helper candidate 1; closed-lid qualification: false")
    exit(0)
}

guard let launchMode = HelperLaunchMode(arguments: arguments), geteuid() == 0 else {
    fputs("Refused: root launchd service with an explicit mode argument required; no power action performed.\n", stderr)
    exit(77)
}
let bestEffortLidMode = launchMode == .bestEffortLid

if launchMode == .recovery || launchMode == .release {
    // Separate short-lived process (own launchd job): works even when the main helper is hung.
    do {
        let storage = try HelperStorage(name: "CamLidPowerHelper", holdsHelperLock: false)
        let runner = NativePMSetRunner()
        let service = PowerLeaseService(backend: PMSetBackend(execute: runner.execute), store: storage.journal,
            bootID: try NativeHelperEnvironment.bootID(), clock: { NativeHelperEnvironment.now },
            safety: NativeHelperEnvironment.safety, strict: ClamshellBitMechanism())
        service.log = logLine
        if launchMode == .recovery { service.sleepSystem = NativeHelperEnvironment.sleepNow }   // never while uninstalling
        let outcome = service.recoverOrphanedPolicy(graceSeconds: launchMode == .release ? -.infinity : 10)
        if outcome != .nothingToRecover { logLine("recovery outcome=\(outcome)") }
        print("recovery: \(outcome)")
        if case .failed = outcome { exit(1) }
        exit(0)
    } catch {
        fputs("Refused: protected journal unavailable; no power action performed.\n", stderr)
        exit(78)
    }
}

do {
    // Team-validated production identity or explicit root-installed exact local CDHash pins.
    // Never unsigned, debugger-entitled, UID-only or client-configured trust.
    let requirement = try PowerHelperIdentity.peerRequirement(forHelper: false)
    let usesLidSpecific = launchMode != .standard
    let storage = try HelperStorage(name: usesLidSpecific ? "CamLidPowerHelperLidSpecific" : "CamLidPowerHelper")
    let controller: PowerLeaseService
    if usesLidSpecific {
        let cap = bestEffortLidMode ? LidOnlyLeaseMechanism.bestEffortMaximumSessionSeconds : 24
        controller = PowerLeaseService(mechanism: LidOnlyLeaseMechanism.nativeCandidate(maximumSessionSeconds: cap),
            store: storage.journal, bootID: try NativeHelperEnvironment.bootID(),
            clock: { NativeHelperEnvironment.now }, safety: NativeHelperEnvironment.safety)
    } else {
        let runner = NativePMSetRunner()
        let backend = PMSetBackend(execute: runner.execute)
        controller = PowerLeaseService(backend: backend, store: storage.journal,
            bootID: try NativeHelperEnvironment.bootID(), clock: { NativeHelperEnvironment.now },
            safety: NativeHelperEnvironment.safety, strict: ClamshellBitMechanism())
    }
    controller.log = logLine
    controller.sleepSystem = NativeHelperEnvironment.sleepNow
    // Explicit @Sendable closures: references formed in top-level (main-actor) code are main-actor isolated, and the
    // runtime calls these from its own queue ("data race detected" at every helper stop).
    let runtime = PowerHelperRuntime(service: controller, onStartupFailure: { @Sendable in exitAfterFailedStart() })
    // Best-effort lid mode ends its single episode on any sleep or wake; Standard's daemon ends only a Strict lease,
    // and only when the system sleeps (ADR 0003).
    let sleepObserver = bestEffortLidMode ? try RootDomainGeneralInterestObserver { reason in
        runtime.observeSystemEvent(reason: reason)
    } : launchMode == .standard ? try RootDomainGeneralInterestObserver { reason in
        if reason == "sleepObserved" { runtime.observeSystemSleep() }
    } : nil
    let delegate = PowerHelperListenerDelegate(runtime: runtime, peerRequirement: requirement)
    let listener = NSXPCListener(machServiceName: PowerHelperIdentity.serviceName)
    listener.setConnectionCodeSigningRequirement(requirement)
    listener.delegate = delegate
    runtime.start()
    listener.activate()

    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let signals = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler {
            sleepObserver?.invalidate()
            listener.invalidate()
            runtime.shutdown(completion: { @Sendable in exitAfterShutdown() })
        }
        source.resume()
        return source
    }
    withExtendedLifetime((storage, sleepObserver, delegate, signals)) { dispatchMain() }
} catch {
    fputs("Refused: signing, protected journal or startup prerequisite failed.\n", stderr)
    exit(78)
}
