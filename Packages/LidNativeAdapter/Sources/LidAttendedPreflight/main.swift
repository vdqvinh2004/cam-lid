import Foundation
import Darwin
@_spi(TestInputs) import LidNativeAdapter
@_spi(TestInputs) import LidRecoveryBroker

// Hard-disabled action entry point: no power bindings/factory referenced, no external opt-in.
struct Report: Encodable {
    let decision: String
    let nativeExecutionEnabled = false
    let nativePowerCallsAttempted = false
    let protectionAvailable = false
    let physicalRestorationVerified = false
    let assessment: NativeSafetyAssessment?
}

func publish(_ report: Report) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var data = try encoder.encode(report)
    data.append(10)
    FileHandle.standardOutput.write(data)
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.isEmpty || args == ["--readiness"] else {
        try publish(Report(decision: "nativeExecutionDisabled", assessment: nil))
        exit(3)
    }
    let environment = SystemBrokerEnvironment()
    let sampler = NativeSafetySampler(systemCalls: .readOnlySDK, clock: { try SystemBrokerEnvironment().sample() })
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    var assessment: NativeSafetyAssessment?
    repeat {
        assessment = sampler.assessment(at: try environment.sample(), stage: .beforeEnable)
        if assessment?.allowed == true { break }
        Thread.sleep(forTimeInterval: 0.02)
    } while ContinuousClock.now < deadline
    try publish(Report(decision: assessment?.allowed == true ? "readOnlySafetyReady" : "readOnlySafetyRefused",
        assessment: assessment))
    exit(assessment?.allowed == true ? 0 : 3)
} catch {
    try? publish(Report(decision: "readOnlyObservationUnavailable", assessment: nil))
    exit(3)
}
