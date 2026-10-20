import Foundation
import Darwin
import CamLidPowerService

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--version"] {
    print("CamLid power helper candidate 1; closed-lid qualification: false")
    exit(0)
}

let lidSpecificMode = arguments == ["--lid-specific-v1"]
let bestEffortLidMode = arguments == ["--lid-specific-best-effort-v1"]
guard (arguments.isEmpty || lidSpecificMode || bestEffortLidMode), geteuid() == 0 else {
    fputs("Refused: root launchd service required; no power action performed.\n", stderr)
    exit(77)
}

do {
    // Team-validated production identity or explicit root-installed exact local CDHash pins.
    // Never unsigned, debugger-entitled, UID-only or client-configured trust.
    let requirement = try PowerHelperIdentity.peerRequirement(forHelper: false)
    let usesLidSpecific = lidSpecificMode || bestEffortLidMode
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
            safety: NativeHelperEnvironment.safety)
    }
    let runtime = PowerHelperRuntime(service: controller)
    let sleepObserver = bestEffortLidMode ? try RootDomainGeneralInterestObserver { reason in
        runtime.observeSystemEvent(reason: reason)
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
            runtime.shutdown { exit(0) }
        }
        source.resume()
        return source
    }
    withExtendedLifetime((storage, sleepObserver, delegate, signals)) { dispatchMain() }
} catch {
    fputs("Refused: signing, protected journal or startup prerequisite failed.\n", stderr)
    exit(78)
}
