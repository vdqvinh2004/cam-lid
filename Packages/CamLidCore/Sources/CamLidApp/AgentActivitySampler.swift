import Foundation
import Darwin
import CamLidCore

/// A directly run agent process and the CPU time of its whole subtree (spec 015). Same-user metadata only.
struct AgentActivityProcess: Sendable, Equatable {
    let provider: String
    let pid: Int32
    let startTime: Double
    let cpuSeconds: Double?
}

extension NativeProcessList {
    /// Process name used for agent matching. Claude Code's installer runs a binary named after its version
    /// (`~/.local/share/claude/versions/2.1.314`), so a version-like name is resolved from the executable path.
    static func agentName(pid: Int32, processName: String) -> String {
        guard !processName.isEmpty, processName.allSatisfy({ $0.isNumber || $0 == "." }) else { return processName }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return processName }
        let path = String(cString: buffer)
        return path.contains("/claude/versions/") ? "claude" : processName
    }

    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    /// Outermost process of each agent (by process name), with the CPU time of it and every descendant. Processes
    /// started under Orca are left out: Orca reports their state as lifecycle evidence, which takes precedence.
    func activityProcesses(providerByName: [String: String], orcaNames: Set<String>) -> [AgentActivityProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        let capacity = min(Self.maximumProcesses, Int(count) + 32)
        var pids = [Int32](repeating: 0, count: capacity)
        let loaded = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard loaded > 0 else { return [] }
        struct Entry { let parent: Int32; let name: String; let start: Double }
        var entries: [Int32: Entry] = [:]
        var children: [Int32: [Int32]] = [:]
        for pid in pids.prefix(min(Int(loaded), capacity)) where pid > 0 {
            var info = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.size
            guard withUnsafeMutablePointer(to: &info, { proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(size)) }) == size,
                  info.pbi_uid == getuid() else { continue }
            let raw = withUnsafeBytes(of: info.pbi_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }.lowercased()
            let name = Self.agentName(pid: pid, processName: raw)
            let parent = Int32(bitPattern: info.pbi_ppid)
            entries[pid] = Entry(parent: parent, name: name,
                                 start: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
            children[parent, default: []].append(pid)
        }
        func ancestors(_ pid: Int32) -> [String] {
            var names: [String] = []
            var current = entries[pid]?.parent ?? 0
            var hops = 0
            while current > 1, let entry = entries[current], hops < 64 { names.append(entry.name); current = entry.parent; hops += 1 }
            return names
        }
        func subtreeCPU(_ root: Int32) -> Double? {
            var total = 0.0
            var stack = [root]
            var visited = 0
            while let pid = stack.popLast(), visited < 512 {
                visited += 1
                var usage = rusage_info_v2()
                let ok = withUnsafeMutablePointer(to: &usage) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
                } == 0
                if ok { total += Double(usage.ri_user_time + usage.ri_system_time) * Self.secondsPerTick }
                else if pid == root { return nil }
                stack.append(contentsOf: children[pid] ?? [])
            }
            return total
        }
        var result: [AgentActivityProcess] = []
        for (pid, entry) in entries {
            guard let provider = providerByName[entry.name] else { continue }
            let above = ancestors(pid)
            guard !above.contains(where: { providerByName[$0] == provider || orcaNames.contains($0) }) else { continue }
            result.append(AgentActivityProcess(provider: provider, pid: pid, startTime: entry.start, cpuSeconds: subtreeCPU(pid)))
            if result.count >= 20 { break }
        }
        return result.sorted { ($0.provider, $0.pid) < ($1.provider, $1.pid) }
    }
}

/// Newest modification time under each agent's own session directory. Reads file metadata only, never contents, and
/// keeps no paths beyond the one file it re-checks between full scans.
final class SessionActivityProbe: @unchecked Sendable {
    static let directories: [String: String] = [
        "claude": ".claude/projects",
        "codex": ".codex/sessions",
        "opencode": ".local/share/opencode",
    ]
    static let rescanSeconds = 30.0
    static let maximumEntries = 5_000

    private let lock = NSLock()
    private let home: URL
    private var newest: [String: (url: URL, date: Date)] = [:]
    private var lastScan: [String: Date] = [:]

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    /// Seconds since the newest write for `provider`, or nil when its directory is missing or unreadable.
    func ageSeconds(provider: String, now: Date = Date()) -> Double? {
        guard let relative = Self.directories[provider] else { return nil }
        lock.lock(); defer { lock.unlock() }
        // Cheap path: re-check the file that was newest last time (it is usually the one being written).
        if var known = newest[provider], let date = Self.modified(known.url), date > known.date {
            known.date = date
            newest[provider] = known
        }
        if now.timeIntervalSince(lastScan[provider] ?? .distantPast) >= Self.rescanSeconds {
            lastScan[provider] = now
            if let found = scan(home.appendingPathComponent(relative)) { newest[provider] = found }
        }
        return newest[provider].map { max(0, now.timeIntervalSince($0.date)) }
    }

    private func scan(_ root: URL) -> (url: URL, date: Date)? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var best: (url: URL, date: Date)?
        var seen = 0
        for case let url as URL in enumerator {
            seen += 1
            // shortcut: scans at most `maximumEntries` entries, so a session file beyond them is missed; move to FSEvents if agents keep larger histories.
            if seen > Self.maximumEntries { break }
            if enumerator.level > 6 { enumerator.skipDescendants(); continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true, let date = values.contentModificationDate else { continue }
            if best == nil || date > best!.date { best = (url, date) }
        }
        return best
    }

    private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
