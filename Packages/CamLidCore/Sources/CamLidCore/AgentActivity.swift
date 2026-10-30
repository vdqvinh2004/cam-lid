import Foundation

/// One outside observation of a directly run agent process (spec 015). Process metadata only.
public struct AgentActivitySample: Sendable, Equatable {
    /// Continuous monotonic seconds.
    public let at: Double
    public let alive: Bool
    /// Cumulative CPU seconds of the agent process and its descendants; nil when unreadable.
    public let cpuSeconds: Double?

    public init(at: Double, alive: Bool, cpuSeconds: Double?) {
        self.at = at; self.alive = alive; self.cpuSeconds = cpuSeconds
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
/// Constants come from the spec 015 calibration (see specs/015-agent-activity-observer/calibration.md): on Claude
/// Code, 5 s averages were 0.006–0.015 of a core while waiting for input and 0.05–0.13 while answering.
public enum AgentActivityClassifier {
    public static let quietSeconds = 45.0
    /// CPU-time growth per wall second (fraction of one core) that counts as activity.
    public static let busyCPUFraction = 0.03
    /// How long an unknown result keeps holding (the policy bounds unknown holds with this).
    public static let unknownHoldSeconds = 15.0

    public static func step(_ memory: inout AgentActivityMemory, _ sample: AgentActivitySample) -> (state: TaskState, reason: String) {
        guard sample.at.isFinite else { return (.unknown, "unreadable") }
        guard sample.alive else { return (.completed, "exited") }
        if let lastAt = memory.lastAt, sample.at < lastAt { memory = AgentActivityMemory() }   // clock went back
        guard let cpu = sample.cpuSeconds, cpu.isFinite, cpu >= 0 else {
            memory.lastCPU = nil; memory.lastAt = sample.at
            return (.unknown, "unreadable")
        }
        var busy: Bool?
        if let lastCPU = memory.lastCPU, let lastAt = memory.lastAt, sample.at > lastAt, cpu >= lastCPU {
            busy = (cpu - lastCPU) / (sample.at - lastAt) >= busyCPUFraction
        }
        // A drop (a child exited, or pid reuse) has no usable delta; it only restarts the baseline.
        memory.lastCPU = cpu
        memory.lastAt = sample.at
        if busy == true {
            memory.lastActiveAt = sample.at
            return (.working, "cpu")
        }
        if let lastActive = memory.lastActiveAt, sample.at - lastActive < quietSeconds { return (.working, "recent") }
        return busy == nil ? (.unknown, "warmingUp") : (.idle, "quiet")
    }
}
