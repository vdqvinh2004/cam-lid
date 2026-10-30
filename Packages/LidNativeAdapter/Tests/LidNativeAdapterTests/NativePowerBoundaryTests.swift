import Foundation
import IOKit
import IOKit.pwr_mgt
import Testing
@_spi(TestInputs) import LidNativeAdapter

@Suite("Native power bindings — fake OS calls only", .serialized)
struct NativePowerBoundaryTests {
    private final class Recorder {
        var properties: NSDictionary?
        var released: [IOPMAssertionID] = []
        var pid: Int32 = 100
        var creation = NativeAssertionCreation(code: kIOReturnSuccess, id: 47)
        var releaseCode: IOReturn = kIOReturnSuccess

        var calls: NativePowerSystemCalls {
            NativePowerSystemCalls(createAssertion: { properties in
                self.properties = properties as NSDictionary
                return self.creation
            }, releaseAssertion: { id in
                self.released.append(id)
                return self.releaseCode
            }, currentPID: { self.pid })
        }
    }

    @Test func finiteIdleAssertionExplicitlyRequestsOSRelease() throws {
        let recorder = Recorder()
        _ = try NativeOwnedIdleAssertion(remainingNanos: 5_000_000_000,
            episodeID: UUID(), systemCalls: recorder.calls)
        let properties = try #require(recorder.properties)
        #expect(properties["AssertType"] as? String == "PreventUserIdleSystemSleep")
        #expect(properties["AssertLevel"] as? Int == 255)
        #expect(properties["TimeoutSeconds"] as? Double == 5)
        #expect(properties["TimeoutAction"] as? String == "TimeoutActionRelease")
        #expect(recorder.released.isEmpty)
    }

    @Test func subsecondBudgetCannotCreateAnAssertion() {
        let recorder = Recorder()
        #expect(throws: NativePowerBoundaryFailure.invalidDuration) {
            _ = try NativeOwnedIdleAssertion(remainingNanos: 999_999_999,
                episodeID: UUID(), systemCalls: recorder.calls)
        }
        #expect(recorder.properties == nil)
    }

    @Test(arguments: [UInt64(0), 30_000_000_001, UInt64.max])
    func invalidBudgetsRefuseBeforeOSCreate(_ remaining: UInt64) {
        let recorder = Recorder()
        #expect(throws: NativePowerBoundaryFailure.invalidDuration) {
            _ = try NativeOwnedIdleAssertion(remainingNanos: remaining,
                episodeID: UUID(), systemCalls: recorder.calls)
        }
        #expect(recorder.properties == nil && recorder.released.isEmpty)
    }

    @Test func fractionalBudgetRoundsDownNeverBeyondBudget() throws {
        let recorder = Recorder()
        _ = try NativeOwnedIdleAssertion(remainingNanos: 5_900_000_000,
            episodeID: UUID(), systemCalls: recorder.calls)
        #expect(recorder.properties?["TimeoutSeconds"] as? Double == 5)
    }

    @Test func creatorReleasesOnlyItsIDOnceAndKeepsErrorReturn() throws {
        let recorder = Recorder()
        let assertion = try NativeOwnedIdleAssertion(remainingNanos: 5_000_000_000,
            episodeID: UUID(), systemCalls: recorder.calls)
        #expect(assertion.releaseState == .notAttempted)
        recorder.pid = 101
        #expect(throws: NativePowerBoundaryFailure.wrongProcess) { try assertion.release() }
        #expect(recorder.released.isEmpty && assertion.releaseState == .notAttempted)
        recorder.pid = 100
        recorder.releaseCode = kIOReturnError
        #expect(try assertion.release() == kIOReturnError)
        #expect(assertion.releaseState == .returned(kIOReturnError))
        #expect(throws: NativePowerBoundaryFailure.releaseAlreadyAttempted) { try assertion.release() }
        #expect(recorder.released == [47])
    }

    @Test func failedOrNullCreationCannotReleaseUnidentifiedID() {
        let recorder = Recorder()
        recorder.creation = NativeAssertionCreation(code: kIOReturnError, id: 47)
        #expect(throws: NativePowerBoundaryFailure.createFailed(code: kIOReturnError, outputID: 47)) {
            _ = try NativeOwnedIdleAssertion(remainingNanos: 5_000_000_000,
                episodeID: UUID(), systemCalls: recorder.calls)
        }
        recorder.creation = NativeAssertionCreation(code: kIOReturnSuccess, id: 0)
        #expect(throws: NativePowerBoundaryFailure.nullAssertionID) {
            _ = try NativeOwnedIdleAssertion(remainingNanos: 5_000_000_000,
                episodeID: UUID(), systemCalls: recorder.calls)
        }
        #expect(recorder.released.isEmpty)
    }

    private final class RootRecorder {
        var service: io_service_t = 7
        var openCode: IOReturn = kIOReturnSuccess
        var connection: io_connect_t = 17
        var serviceReleaseCode: IOReturn = kIOReturnSuccess
        var selectorCode: IOReturn = kIOReturnSuccess
        var closeCode: IOReturn = kIOReturnSuccess
        var events: [String] = []

        var calls: NativeRootDomainSystemCalls {
            NativeRootDomainSystemCalls(matchingService: {
                self.events.append("match"); return self.service
            }, open: { service in
                self.events.append("open:\(service)"); return (self.openCode, self.connection)
            }, releaseService: { service in
                self.events.append("serviceRelease:\(service)"); return self.serviceReleaseCode
            }, scalarCall: { connection, selector, input in
                self.events.append("scalar:\(connection):\(selector):\(input)"); return self.selectorCode
            }, close: { connection in
                self.events.append("close:\(connection)"); return self.closeCode
            })
        }
    }

    @Test func sharedSelectorConstructionAndPortCleanupAreExact() {
        let recorder = RootRecorder()
        let boundary = NativeSharedLidBoundary(systemCalls: recorder.calls)
        #expect(boundary.callUnsupportedSharedSelector(enabled: true) == .returned(
            selectorCode: kIOReturnSuccess, serviceReleaseCode: kIOReturnSuccess, connectionCloseCode: kIOReturnSuccess))
        #expect(recorder.events == ["match", "open:7", "serviceRelease:7", "scalar:17:12:1", "close:17"])
        recorder.events = []
        _ = boundary.callUnsupportedSharedSelector(enabled: false)
        #expect(recorder.events == ["match", "open:7", "serviceRelease:7", "scalar:17:12:0", "close:17"])
    }

    @Test(arguments: ["missing", "openFailed", "nullConnection", "secondaryFailures"])
    func nativeFaultReturnsNeverImplyPhysicalCleanup(_ fault: String) {
        let recorder = RootRecorder()
        if fault == "missing" { recorder.service = 0 }
        if fault == "openFailed" { recorder.openCode = kIOReturnNotPermitted }
        if fault == "nullConnection" { recorder.connection = 0 }
        if fault == "secondaryFailures" {
            recorder.serviceReleaseCode = kIOReturnError
            recorder.selectorCode = kIOReturnError
            recorder.closeCode = kIOReturnError
        }
        let result = NativeSharedLidBoundary(systemCalls: recorder.calls).callUnsupportedSharedSelector(enabled: true)
        switch fault {
        case "missing":
            #expect(result == .notDispatched(stage: "matching", code: nil, serviceReleaseCode: nil))
            #expect(recorder.events == ["match"])
        case "openFailed":
            #expect(result == .notDispatched(stage: "open", code: kIOReturnNotPermitted, serviceReleaseCode: kIOReturnSuccess))
            #expect(recorder.events == ["match", "open:7", "serviceRelease:7"])
        case "nullConnection":
            #expect(result == .notDispatched(stage: "nullConnection", code: kIOReturnSuccess, serviceReleaseCode: kIOReturnSuccess))
            #expect(recorder.events == ["match", "open:7", "serviceRelease:7"])
        default:
            #expect(result == .returned(selectorCode: kIOReturnError, serviceReleaseCode: kIOReturnError, connectionCloseCode: kIOReturnError))
            #expect(recorder.events.last == "close:17")
        }
    }
}
