import Foundation
import Darwin
import IOKit
import IOKit.pwr_mgt

@_spi(TestInputs)
public struct NativeAssertionCreation {
    public let code: IOReturn
    public let id: IOPMAssertionID
    public init(code: IOReturn, id: IOPMAssertionID) { self.code = code; self.id = id }
}

@_spi(TestInputs)
public enum NativeLidCallResult: Equatable {
    case notDispatched(stage: String, code: IOReturn?, serviceReleaseCode: IOReturn?)
    case returned(selectorCode: IOReturn, serviceReleaseCode: IOReturn, connectionCloseCode: IOReturn)
}

@_spi(TestInputs)
public struct NativePowerSystemCalls {
    let createAssertion: (CFDictionary) -> NativeAssertionCreation
    let releaseAssertion: (IOPMAssertionID) -> IOReturn
    let currentPID: () -> pid_t

    public init(createAssertion: @escaping (CFDictionary) -> NativeAssertionCreation,
                releaseAssertion: @escaping (IOPMAssertionID) -> IOReturn,
                currentPID: @escaping () -> pid_t) {
        self.createAssertion = createAssertion
        self.releaseAssertion = releaseAssertion
        self.currentPID = currentPID
    }

    // Explicit opt-in binding, never an initializer default or a runnable command.
    public static var sdkBindings: NativePowerSystemCalls {
        NativePowerSystemCalls(createAssertion: { properties in
            var id: IOPMAssertionID = 0
            let code = IOPMAssertionCreateWithProperties(properties, &id)
            return NativeAssertionCreation(code: code, id: id)
        }, releaseAssertion: { IOPMAssertionRelease($0) }, currentPID: { getpid() })
    }
}

@_spi(TestInputs)
public enum NativePowerBoundaryFailure: Error, Equatable {
    case invalidDuration
    case createFailed(code: IOReturn, outputID: IOPMAssertionID)
    case nullAssertionID
    case wrongProcess
    case releaseAlreadyAttempted
}

@_spi(TestInputs)
public enum NativeReleaseState: Equatable {
    case notAttempted
    case inFlight
    case returned(IOReturn)
}

@_spi(TestInputs)
public final class NativeOwnedIdleAssertion {
    private let id: IOPMAssertionID
    private let creatorPID: pid_t
    private let calls: NativePowerSystemCalls
    private let control = NSLock()
    private var state: NativeReleaseState = .notAttempted

    public init(remainingNanos: UInt64, episodeID: UUID, systemCalls: NativePowerSystemCalls) throws {
        guard remainingNanos >= 1_000_000_000, remainingNanos <= 30_000_000_000 else {
            throw NativePowerBoundaryFailure.invalidDuration
        }
        creatorPID = systemCalls.currentPID()
        calls = systemCalls
        let properties: [String: Any] = [
            kIOPMAssertionTypeKey: kIOPMAssertionTypePreventUserIdleSystemSleep,
            kIOPMAssertionLevelKey: NSNumber(value: kIOPMAssertionLevelOn),
            kIOPMAssertionNameKey: "CamLid lab \(episodeID.uuidString)",
            // Pinned powerd truncates fractional seconds; never round beyond remaining budget.
            kIOPMAssertionTimeoutKey: NSNumber(value: Double(remainingNanos / 1_000_000_000)),
            kIOPMAssertionTimeoutActionKey: kIOPMAssertionTimeoutActionRelease,
        ]
        let created = systemCalls.createAssertion(properties as CFDictionary)
        guard created.code == kIOReturnSuccess else {
            throw NativePowerBoundaryFailure.createFailed(code: created.code, outputID: created.id)
        }
        guard created.id != 0 else { throw NativePowerBoundaryFailure.nullAssertionID }
        id = created.id
    }

    public var releaseState: NativeReleaseState {
        control.lock()
        defer { control.unlock() }
        return state
    }

    // PID is a fork guard, not IPC authentication. No raw ID import or cross-process release API.
    public func release() throws -> IOReturn {
        guard calls.currentPID() == creatorPID else { throw NativePowerBoundaryFailure.wrongProcess }
        control.lock()
        guard state == .notAttempted else {
            control.unlock()
            throw NativePowerBoundaryFailure.releaseAlreadyAttempted
        }
        state = .inFlight
        control.unlock()
        let result = calls.releaseAssertion(id)
        control.lock()
        state = .returned(result)
        control.unlock()
        return result
    }
}

@_spi(TestInputs)
public struct NativeRootDomainSystemCalls {
    let matchingService: () -> io_service_t
    let open: (io_service_t) -> (code: IOReturn, connection: io_connect_t)
    let releaseService: (io_service_t) -> IOReturn
    let scalarCall: (io_connect_t, UInt32, UInt64) -> IOReturn
    let close: (io_connect_t) -> IOReturn

    public init(matchingService: @escaping () -> io_service_t,
                open: @escaping (io_service_t) -> (code: IOReturn, connection: io_connect_t),
                releaseService: @escaping (io_service_t) -> IOReturn,
                scalarCall: @escaping (io_connect_t, UInt32, UInt64) -> IOReturn,
                close: @escaping (io_connect_t) -> IOReturn) {
        self.matchingService = matchingService
        self.open = open
        self.releaseService = releaseService
        self.scalarCall = scalarCall
        self.close = close
    }

    public static var sdkBindings: NativeRootDomainSystemCalls {
        NativeRootDomainSystemCalls(matchingService: {
            IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        }, open: { service in
            var connection: io_connect_t = 0
            let code = IOServiceOpen(service, mach_task_self_, 0, &connection)
            return (code, connection)
        }, releaseService: { IOObjectRelease($0) }, scalarCall: { connection, selector, input in
            var scalar = input
            return withUnsafePointer(to: &scalar) {
                IOConnectCallScalarMethod(connection, selector, $0, 1, nil, nil)
            }
        }, close: { IOServiceClose($0) })
    }
}

@_spi(TestInputs)
public struct NativeSharedLidBoundary {
    private let calls: NativeRootDomainSystemCalls
    public init(systemCalls: NativeRootDomainSystemCalls) { calls = systemCalls }

    // Caller must supply reviewed episode arbitration, independent completion and durable cleanup intent.
    public func callUnsupportedSharedSelector(enabled: Bool) -> NativeLidCallResult {
        let service = calls.matchingService()
        guard service != 0 else {
            return .notDispatched(stage: "matching", code: nil, serviceReleaseCode: nil)
        }
        let opened = calls.open(service)
        let released = calls.releaseService(service)
        guard opened.code == kIOReturnSuccess else {
            return .notDispatched(stage: "open", code: opened.code, serviceReleaseCode: released)
        }
        guard opened.connection != 0 else {
            return .notDispatched(stage: "nullConnection", code: opened.code, serviceReleaseCode: released)
        }
        // Unsupported shared selector, pinned XNU f6217f891ac0bb64f3d375211650a4c1ff8ca1ea.
        let code = calls.scalarCall(opened.connection, 12, enabled ? 1 : 0)
        let closed = calls.close(opened.connection)
        return .returned(selectorCode: code, serviceReleaseCode: released, connectionCloseCode: closed)
    }
}
