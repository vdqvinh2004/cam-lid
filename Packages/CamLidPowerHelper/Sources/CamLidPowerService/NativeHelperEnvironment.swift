import Foundation
import Darwin
import IOKit
import IOKit.ps
import CoreGraphics
import SystemConfiguration
import LidRecoveryJournal

public enum NativeHelperEnvironment {
    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    public static var now: Double { Double(mach_continuous_time()) * secondsPerTick }

    public static func bootID() throws -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, (2...128).contains(size) else {
            throw PowerServiceFailure.clock
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else {
            throw PowerServiceFailure.clock
        }
        return String(decoding: bytes.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Read-only global policy observation. This is not ownership of the shared lid bit and
    /// never authorizes a write.
    public static func globalSleepDisabled() throws -> Bool {
        let root = try rootDomain()
        defer { IOObjectRelease(root) }
        return try booleanProperty("SleepDisabled", root: root)
    }

    /// Conservative effective-policy admission only, not a getter for an owned shared bit.
    public static func lidOnlyBaselineAllowsAdmission() throws -> Bool {
        let before = now
        let root = try rootDomain()
        defer { IOObjectRelease(root) }
        let globalDisabled = try booleanProperty("SleepDisabled", root: root)
        let lidCausesSleep = try booleanProperty("AppleClamshellCausesSleep", root: root)
        return !globalDisabled && lidCausesSleep && now - before <= 1
    }

    private static func rootDomain() throws -> io_service_t {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { throw PowerServiceFailure.unsafe }
        return root
    }

    private static func booleanProperty(_ name: String, root: io_service_t) throws -> Bool {
        guard let value = IORegistryEntryCreateCFProperty(root, name as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue(),
            CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw PowerServiceFailure.unsafe
        }
        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
    }

    public static func safety() throws -> HelperSafety {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            throw PowerServiceFailure.unsafe
        }
        let batteries = sources.compactMap { source -> [String: Any]? in
            guard let value = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  value[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { return nil }
            return value
        }
        guard batteries.count == 1, let battery = batteries.first,
              let current = battery[kIOPSCurrentCapacityKey] as? NSNumber,
              let maximum = battery[kIOPSMaxCapacityKey] as? NSNumber,
              CFGetTypeID(current) != CFBooleanGetTypeID(), CFGetTypeID(maximum) != CFBooleanGetTypeID(),
              maximum.doubleValue > 0, current.doubleValue >= 0,
              current.doubleValue <= maximum.doubleValue else { throw PowerServiceFailure.unsafe }
        var uid: uid_t = 0
        var gid: gid_t = 0
        let console = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?
        let consoleUID = console != nil && console != "loginwindow" && uid > 0 ? uid : nil

        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { throw PowerServiceFailure.unsafe }
        defer { IOObjectRelease(root) }
        let lid = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                                                  kCFAllocatorDefault, 0)?.takeRetainedValue()
        guard let lid, CFGetTypeID(lid) == CFBooleanGetTypeID() else { throw PowerServiceFailure.unsafe }
        let closed = CFBooleanGetValue(unsafeDowncast(lid, to: CFBoolean.self))

        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success, count < 16 else {
            throw PowerServiceFailure.unsafe
        }
        let online = displays.prefix(Int(count))
        // Closing the lid may remove the built-in display from the online list.
        if !closed, online.filter({ CGDisplayIsBuiltin($0) != 0 }).count != 1 {
            throw PowerServiceFailure.unsafe
        }
        return HelperSafety(onAC: battery[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
            batteryPercent: current.doubleValue / maximum.doubleValue * 100,
            thermalNominal: ProcessInfo.processInfo.thermalState == .nominal,
            consoleUID: consoleUID, lidClosed: closed,
            externalDisplays: online.filter { CGDisplayIsBuiltin($0) == 0 }.count)
    }

    public static func sleepNow() {
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard port != 0 else { return }
        _ = IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    public static func systemSleepEventReason(messageType: UInt32) -> String? {
        switch messageType {
        case 0xe000_0280: return "sleepObserved"
        case 0xe000_0300, 0xe000_0320: return "wakeObserved"
        default: return nil
        }
    }
}

/// Passive IOPMrootDomain general-interest subscriber only (never IORegisterForSystemPower/veto).
public final class RootDomainGeneralInterestObserver {
    private let onEvent: @Sendable (String) -> Void
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0

    public init(queue: DispatchQueue = .main, onEvent: @escaping @Sendable (String) -> Void) throws {
        self.onEvent = onEvent
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { throw PowerServiceFailure.unsafe }
        defer { IOObjectRelease(root) }
        guard let createdPort = IONotificationPortCreate(kIOMainPortDefault) else {
            throw PowerServiceFailure.unsafe
        }
        IONotificationPortSetDispatchQueue(createdPort, queue)
        var handle: io_object_t = 0
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = IOServiceAddInterestNotification(
            createdPort, root, kIOGeneralInterest,
            { refcon, _, messageType, _ in
                guard let refcon, let reason = NativeHelperEnvironment.systemSleepEventReason(messageType: messageType) else {
                    return
                }
                Unmanaged<RootDomainGeneralInterestObserver>.fromOpaque(refcon)
                    .takeUnretainedValue().onEvent(reason)
            },
            context, &handle
        )
        guard status == KERN_SUCCESS, handle != 0 else {
            IONotificationPortDestroy(createdPort)
            throw PowerServiceFailure.unsafe
        }
        port = createdPort
        notifier = handle
    }

    public func invalidate() {
        if notifier != 0 {
            IOObjectRelease(notifier)
            notifier = 0
        }
        if let port {
            IONotificationPortDestroy(port)
            self.port = nil
        }
    }

    deinit { invalidate() }
}

/// Single daemon instance, not exclusive ownership of macOS's shared setting.
/// Retained lock cannot provide independent recovery while this daemon is suspended.
public final class HelperStorage {
    public let journal: DurableRecoveryJournal
    private let lockFD: Int32

    /// `holdsHelperLock: false` is for the independent recovery job: it must read and restore while a
    /// hung helper still owns the helper lock. Journal commits stay revision-checked, so a racing
    /// writer is refused rather than overwritten.
    public init(name: String = "CamLidPowerHelper", holdsHelperLock: Bool = true) throws {
        guard ["CamLidPowerHelper", "CamLidPowerHelperLidSpecific"].contains(name) else {
            throw JournalFailure.unsafeStorage
        }
        let parent = open("/private/var/db", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw JournalFailure.unsafeStorage }
        defer { close(parent) }
        var parentInfo = stat()
        guard fstat(parent, &parentInfo) == 0, parentInfo.st_uid == 0,
              parentInfo.st_mode & 0o022 == 0 else { throw JournalFailure.unsafeStorage }
        try requireNoExtendedACL(fd: parent)
        guard mkdirat(parent, name, 0o700) == 0 || errno == EEXIST else { throw JournalFailure.unsafeStorage }
        let directory = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw JournalFailure.unsafeStorage }
        defer { close(directory) }
        var information = stat()
        guard fstat(directory, &information) == 0, information.st_uid == 0,
              information.st_mode & 0o777 == 0o700 else { throw JournalFailure.unsafeStorage }
        try requireNoExtendedACL(fd: directory)
        if !holdsHelperLock {
            journal = try DurableRecoveryJournal(directory: URL(fileURLWithPath: "/private/var/db/\(name)"))
            lockFD = -1
            return
        }
        let fd = openat(directory, ".helper.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw JournalFailure.unsafeStorage }
        var lockInfo = stat()
        guard fstat(fd, &lockInfo) == 0, lockInfo.st_uid == 0, lockInfo.st_nlink == 1,
              lockInfo.st_mode & S_IFMT == S_IFREG, lockInfo.st_mode & 0o777 == 0o600,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw JournalFailure.unsafeStorage
        }
        do {
            try requireNoExtendedACL(fd: fd)
            journal = try DurableRecoveryJournal(directory: URL(fileURLWithPath: "/private/var/db/\(name)"))
            lockFD = fd
        } catch {
            close(fd)
            throw error
        }
    }

    deinit { if lockFD >= 0 { close(lockFD) } }
}
