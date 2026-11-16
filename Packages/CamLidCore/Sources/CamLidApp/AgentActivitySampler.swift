import Foundation
import Darwin
import CamLidCore

/// A directly run agent process and the CPU time of its whole subtree (spec 015). Same-user metadata only.
struct AgentActivityProcess: Sendable, Equatable {
    let provider: String
    let pid: Int32
    let startTime: Double
    let cpuSeconds: Double?
    /// Started under an Orca process (its terminal host is `orca-terminal-host`, outside Orca.app since 1.4.258).
    var underOrca = false
    /// Left to Orca's report by `applyingOrcaReports`: neither sampled nor counted here.
    var orcaHosted = false
    /// Anything running under Orca is counted as Orca, under no other provider.
    var reportedProvider: String { underOrca ? "orca" : provider }
}

extension Array where Element == AgentActivityProcess {
    /// Orca's fresh report decides for each provider it names an agent of: those processes under Orca are left to it,
    /// neither sampled nor counted here, so their CPU never adds work on top of Orca's state. Any other process under
    /// Orca (a provider Orca names no agent of, or every one while Orca is stale or unreachable) is sampled like any
    /// terminal agent, so an agent Orca does not report is not invisible.
    func applyingOrcaReports(reportedProviders: Set<String>?) -> [AgentActivityProcess] {
        map { process in
            var marked = process
            marked.orcaHosted = process.underOrca && (reportedProviders?.contains(process.provider) ?? false)
            return marked
        }
    }
}

extension NativeProcessList {
    /// Process name used for agent matching. Claude Code's installer runs a binary named after its version
    /// (`~/.local/share/claude/versions/2.1.314`), so a version-like name is resolved from the executable path.
    static func agentName(pid: Int32, processName: String) -> String {
        if isInterpreter(processName) { return scriptName(pid) ?? processName }
        guard !processName.isEmpty, processName.allSatisfy({ $0.isNumber || $0 == "." }) else { return processName }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return processName }
        let path = String(cString: buffer)
        return path.contains("/claude/versions/") ? "claude" : processName
    }

    /// Script CLIs run under an interpreter, so the kernel names them `node` (Pi, Freebuff, Gemini, Copilot, Amp) or
    /// `python` (Aider).
    static func isInterpreter(_ name: String) -> Bool {
        ["node", "bun", "deno"].contains(name) || name.hasPrefix("python")
    }

    /// The agent an interpreter runs: the file name of argv[0] (Pi rewrites it to `pi`) or argv[1] (`node …/bin/freebuff`)
    /// when it is a known agent name. Later arguments belong to the script and are ignored.
    static func scriptName(_ pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size, size <= 1 << 20 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        // Layout: argc, the executable path, padding NULs, then argv.
        let strings = buffer[MemoryLayout<Int32>.size..<size].split(separator: 0, omittingEmptySubsequences: true)
        return agent(fromArguments: strings.dropFirst().prefix(min(max(argc, 0), 2)).map { String(decoding: $0, as: UTF8.self) })
    }

    static func agent(fromArguments argv: [String]) -> String? {
        argv.prefix(2).map { ($0 as NSString).lastPathComponent.lowercased() }.first(where: executableNames.contains)
    }

    /// Parent pid, short command name and owner for any process, via `sysctl kern.proc.pid` (readable without privileges).
    static func kernelEntry(_ pid: Int32) -> (parent: Int32, name: String, uid: uid_t)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }.lowercased()
        return (info.kp_eproc.e_ppid, name, info.kp_eproc.e_ucred.cr_uid)
    }

    /// Names of the processes above `pid`, nearest first, read through `lookup` (parent pid and name, nil when unknown).
    /// Bounded, so a corrupt table cannot loop.
    static func ancestorNames(of pid: Int32, lookup: (Int32) -> (parent: Int32, name: String)?) -> [String] {
        var names: [String] = []
        var current = lookup(pid)?.parent ?? 0
        var hops = 0
        while current > 1, hops < 64, let entry = lookup(current) {
            names.append(entry.name); current = entry.parent; hops += 1
        }
        return names
    }

    /// Whether a process runs inside Orca: its terminal host sits outside Orca.app since 1.4.258, so any ancestor named
    /// `orca…` counts. Read from the kernel's table, so the root-owned `login` on the way does not end the walk.
    static func runsUnderOrca(_ pid: Int32) -> Bool {
        let names = ancestorNames(of: pid) { current in kernelEntry(current).map { (parent: $0.parent, name: $0.name) } }
        return names.contains { $0.hasPrefix("orca") }
    }

    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    /// Outermost process of each agent (by process name), with the CPU time of it and every descendant. Agents under an
    /// Orca process are marked `underOrca`; `applyingOrcaReports` decides whether Orca's report covers them.
    func activityProcesses(providerByName: [String: String]) -> [AgentActivityProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        let capacity = min(Self.maximumProcesses, Int(count) + 32)
        var pids = [Int32](repeating: 0, count: capacity)
        let loaded = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard loaded > 0 else { return [] }
        struct Entry { let parent: Int32; let name: String; let start: Double; var hasTerminal = true }
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
                                 start: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000,
                                 hasTerminal: info.e_tdev != UInt32.max)   // NODEV: no controlling terminal
            children[parent, default: []].append(pid)
        }
        func ancestors(_ pid: Int32) -> [String] {
            // Terminals start shells through a root-owned `login`, which the same-user scan cannot read; fall back to
            // the kernel's process table (what `ps` uses) so the walk reaches the terminal (for example Orca's host).
            Self.ancestorNames(of: pid) { current in
                if let entry = entries[current] { return (parent: entry.parent, name: entry.name) }
                return Self.kernelEntry(current).map { (parent: $0.parent, name: $0.name) }
            }
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
            // Agents someone opened run in a terminal; a headless agent started by a daemon or plugin (a memory
            // plugin's `claude --output-format stream-json`, 2026-11-03) is not the owner's work and holds nothing.
            guard let provider = providerByName[entry.name], entry.hasTerminal else { continue }
            let above = ancestors(pid)
            guard !above.contains(where: { providerByName[$0] == provider }) else { continue }
            result.append(AgentActivityProcess(provider: provider, pid: pid, startTime: entry.start,
                cpuSeconds: subtreeCPU(pid), underOrca: above.contains(where: { $0.hasPrefix("orca") })))
            if result.count >= 64 { break }
        }
        return result.sorted { ($0.provider, $0.pid) < ($1.provider, $1.pid) }
    }
}
