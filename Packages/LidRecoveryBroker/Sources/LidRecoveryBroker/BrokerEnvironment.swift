import Foundation
import Darwin

@_spi(TestInputs)
public struct BrokerClockSnapshot: Sendable {
    public let bootID: String
    public let nowNanos: UInt64
    public init(bootID: String, nowNanos: UInt64) { self.bootID = bootID; self.nowNanos = nowNanos }
}

@_spi(TestInputs)
public protocol BrokerEnvironment {
    func sample() throws -> BrokerClockSnapshot
}

@_spi(TestInputs)
public struct SystemBrokerEnvironment: BrokerEnvironment {
    public init() {}
    public func sample() throws -> BrokerClockSnapshot {
        var count = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &count, nil, 0) == 0,
              count > 1, count <= 128 else { throw BrokerFailure.environmentUnavailable }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &count, nil, 0) == 0,
              bytes.last == 0 else { throw BrokerFailure.environmentUnavailable }
        let boot = String(decoding: bytes.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard UUID(uuidString: boot) != nil else { throw BrokerFailure.environmentUnavailable }
        var scale = mach_timebase_info_data_t()
        guard mach_timebase_info(&scale) == KERN_SUCCESS, scale.denom > 0 else {
            throw BrokerFailure.environmentUnavailable
        }
        let nanos = mach_continuous_time().multipliedReportingOverflow(by: UInt64(scale.numer))
        guard !nanos.overflow else { throw BrokerFailure.environmentUnavailable }
        return BrokerClockSnapshot(bootID: boot, nowNanos: nanos.partialValue / UInt64(scale.denom))
    }
}
