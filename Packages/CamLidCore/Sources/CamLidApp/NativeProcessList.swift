import Foundation
import Darwin
import CamLidCore

/// Bounded same-user executable metadata only. Arguments, environments, output,
/// terminal buffers and process paths are neither read nor retained.
struct NativeProcessList: ProcessListProvider {
    static let maximumProcesses = LifetimeProcessSnapshot.maximumProcesses
    static let maximumExecutablePathBytes = 4096
    static let executableNames: Set<String> = AgentProviderCatalog.processNames

    struct AgentSnapshot: Sendable {
        let records: [ProcessRecord]
        let complete: Bool
    }

    func snapshot() -> [ProcessRecord] { agentSnapshot().records }

    func agentSnapshot() -> AgentSnapshot {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return AgentSnapshot(records: [], complete: false) }
        let capacity = min(Self.maximumProcesses, Int(count) + 32)
        var pids = [Int32](repeating: 0, count: capacity)
        let loaded = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard loaded > 0 else { return AgentSnapshot(records: [], complete: false) }
        var complete = Int(count) < Self.maximumProcesses && Int(loaded) < capacity
        let now = ContinuousTime.now
        var records: [ProcessRecord] = []
        for pid in pids.prefix(min(Int(loaded), capacity)) where pid > 0 {
            var info = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.size
            let result = withUnsafeMutablePointer(to: &info) { proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(size)) }
            guard result == size else { complete = false; continue }
            guard info.pbi_uid == getuid(), info.pbi_ruid == getuid() else { continue }
            let name = Self.agentName(pid: pid, processName: withUnsafeBytes(of: info.pbi_name) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }.lowercased())
            guard Self.executableNames.contains(name),
                  let identity = try? ProcessIdentity(pid: pid, startTime: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000),
                  let record = try? ProcessRecord(identity: identity, executableName: name, lastSeenMonotonic: now) else { continue }
            records.append(record)
            if records.count >= 20 { complete = false; break }
        }
        return AgentSnapshot(records: records, complete: complete)
    }

    /// Full, bounded same-user metadata is collected only when an explicit
    /// lifetime rule is configured. A failed or truncated scan stays unknown.
    func lifetimeSnapshot() -> LifetimeProcessSnapshot? {
        let now = ContinuousTime.now
        let userID = getuid()
        let count = proc_listallpids(nil, 0)
        guard count > 0 else {
            return try? LifetimeProcessSnapshot(userID: userID, observedAtMonotonic: now,
                processes: [], complete: false)
        }
        let capacity = min(Self.maximumProcesses, Int(count) + 32)
        var pids = [Int32](repeating: 0, count: capacity)
        let loaded = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard loaded > 0 else {
            return try? LifetimeProcessSnapshot(userID: userID, observedAtMonotonic: now,
                processes: [], complete: false)
        }

        var complete = Int(count) < Self.maximumProcesses && Int(loaded) < capacity
        var processes: [LifetimeObservedProcess] = []
        for pid in pids.prefix(min(Int(loaded), capacity)) where pid > 0 {
            var info = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.size
            let result = withUnsafeMutablePointer(to: &info) {
                proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(size))
            }
            guard result == size else { complete = false; continue }
            guard info.pbi_uid == userID, info.pbi_ruid == userID else { continue }
            guard let identity = try? LifetimeProcessIdentity(pid: pid,
                startTime: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000,
                userID: userID) else { complete = false; continue }

            var pathBuffer = [CChar](repeating: 0, count: Self.maximumExecutablePathBytes)
            let pathLength = pathBuffer.withUnsafeMutableBufferPointer {
                proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
            }
            guard pathLength > 0, pathLength < Int32(pathBuffer.count) else {
                if pathLength >= Int32(pathBuffer.count) { complete = false }
                if let process = try? LifetimeObservedProcess(identity: identity, executablePath: nil) {
                    processes.append(process)
                }
                continue
            }
            let pathBytes = pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            guard let path = String(bytes: pathBytes, encoding: .utf8) else { complete = false; continue }
            let (bundleID, bundleKnown) = Self.bundleIdentity(forExecutablePath: path)
            if let process = try? LifetimeObservedProcess(identity: identity, executablePath: path,
                applicationBundleID: bundleID, bundleIdentityKnown: bundleKnown) {
                processes.append(process)
            } else {
                complete = false
            }
        }
        return try? LifetimeProcessSnapshot(userID: userID, observedAtMonotonic: now,
            processes: processes, complete: complete)
    }

    private static func bundleIdentity(forExecutablePath path: String) -> (String?, Bool) {
        var directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        while directory.path != "/" {
            if directory.pathExtension == "app" {
                let identifier = Bundle(url: directory)?.bundleIdentifier
                return (identifier, identifier != nil)
            }
            directory.deleteLastPathComponent()
        }
        return (nil, true)
    }
}
