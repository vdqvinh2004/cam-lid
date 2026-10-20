import Foundation
import IOKit
import CamLidCore

public enum LidStateReader {
    public static func read() -> LidObservation {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return LidObservation(availability: "error", reasonCode: "rootDomainUnavailable") }
        defer { IOObjectRelease(service) }
        let property = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return decode(property, at: ContinuousTime.now)
    }
    static func decode(_ property: CFTypeRef?, at now: Double) -> LidObservation {
        guard let property else { return LidObservation(availability: "error", reasonCode: "lidPropertyMissing") }
        guard CFGetTypeID(property) == CFBooleanGetTypeID() else {
            return LidObservation(availability: "error", reasonCode: "invalidLidType")
        }
        let closed = CFBooleanGetValue(unsafeDowncast(property, to: CFBoolean.self))
        return LidObservation(state: closed ? .closed : .open, sampledAtMonotonic: now)
    }
}
