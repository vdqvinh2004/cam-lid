import Foundation

/// One outside observation of a directly run agent process (spec 015). Nothing here reads file contents.
public struct AgentActivitySample: Sendable, Equatable {
    /// Continuous monotonic seconds.
    public let at: Double
    public let alive: Bool
    /// Cumulative CPU seconds of the agent process and its descendants; nil when unreadable.
    public let cpuSeconds: Double?
    /// Seconds since the newest write in the agent's own session directory; nil when unavailable.
    public let sessionFileAgeSeconds: Double?

    public init(at: Double, alive: Bool, cpuSeconds: Double?, sessionFileAgeSeconds: Double?) {
        self.at = at; self.alive = alive; self.cpuSeconds = cpuSeconds; self.sessionFileAgeSeconds = sessionFileAgeSeconds
    }
}

/// Per-process memory between samples.
public struct AgentActivityMemory: Sendable, Equatable {
    var lastCPU: Double?
    var lastAt: Double?
    var lastActiveAt: Double?
    public init() {}
}

/// Working / idle / unknown from outside signals. A signal that cannot be read never counts as quiet.
public enum AgentActivityClassifier {
    // shortcut: provisional constants until spec 015 T401 calibrates them on real sessions; replace with measured values.
    public static let activityWindowSeconds = 10.0
    public static let quietSeconds = 45.0
    /// CPU-time growth per wall second (fraction of one core) that counts as activity.
    public static let busyCPUFraction = 0.03
    /// How long an unknown result keeps holding (the policy bounds unknown holds with this).
    public static let unknownHoldSeconds = 15.0

    public static func step(_ memory: inout AgentActivityMemory, _ sample: AgentActivitySample) -> (state: TaskState, reason: String) {
        guard sample.at.isFinite else { return (.unknown, "unreadable") }
        guard sample.alive else { return (.completed, "exited") }
        if let lastAt = memory.lastAt, sample.at < lastAt { memory = AgentActivityMemory() }   // clock went back

        var cpuActive: Bool?
        if let cpu = sample.cpuSeconds, cpu.isFinite, cpu >= 0 {
            if let lastCPU = memory.lastCPU, let lastAt = memory.lastAt, sample.at > lastAt {
                // CPU time can only grow for one process; a drop means pid reuse, so start over.
                cpuActive = cpu >= lastCPU ? (cpu - lastCPU) / (sample.at - lastAt) >= busyCPUFraction : nil
            }
            memory.lastCPU = cpu
        } else {
            memory.lastCPU = nil
        }
        memory.lastAt = sample.at
        let fileActive = sample.sessionFileAgeSeconds.map { $0 >= 0 && $0 <= activityWindowSeconds }

        if cpuActive == true || fileActive == true {
            memory.lastActiveAt = sample.at
            return (.working, cpuActive == true ? "cpu" : "sessionFile")
        }
        if let lastActive = memory.lastActiveAt, sample.at - lastActive < quietSeconds {
            return (.working, "recent")
        }
        // A readable CPU signal without a baseline yet is not evidence of quiet.
        if sample.cpuSeconds != nil && cpuActive == nil { return (.unknown, "warmingUp") }
        // Quiet needs at least one signal that was actually read as quiet.
        guard cpuActive == false || fileActive == false else { return (.unknown, "unreadable") }
        return (.idle, "quiet")
    }
}
