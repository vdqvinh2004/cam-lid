import Darwin

/// Raw filesystem boundary for fault injection. Custom implementations are trusted
/// test inputs, not proof of durable storage. Not an IPC or power interface.
@_spi(FaultInjection)
public protocol JournalSystemCalls {
    func write(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int
    func synchronize(_ fd: Int32) -> Int32
    func publish(directoryFD: Int32, temporaryName: String, finalName: String) -> Int32
}

@_spi(FaultInjection)
public struct DarwinJournalSystemCalls: JournalSystemCalls {
    public init() {}
    public func write(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int) -> Int {
        Darwin.write(fd, bytes, count)
    }
    public func synchronize(_ fd: Int32) -> Int32 { Darwin.fsync(fd) }
    public func publish(directoryFD: Int32, temporaryName: String, finalName: String) -> Int32 {
        Darwin.renameat(directoryFD, temporaryName, directoryFD, finalName)
    }
}
