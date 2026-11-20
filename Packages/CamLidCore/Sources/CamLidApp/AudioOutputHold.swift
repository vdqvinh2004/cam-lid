import AppKit

/// Spec 029: the rule behind the "Any audio" chip. It reads CoreAudio's output flag, the same read spec 025 uses, for every
/// process. No audio content is read and no permission is added. The hold starts once a process has output for `startSeconds`
/// (short alerts do not count), and ends `quietSeconds` after the output stops.
struct AudioOutputHold: Equatable {
    static let startSeconds = 3.0
    static let quietSeconds = 60.0
    /// Audio-server and alert processes, and CamLid itself, never count (spec 029 D2). Names come from the process path.
    static let excludedProcessNames: Set<String> = ["coreaudiod", "systemsoundserverd", "CamLid", "camlid"]
    static let excludedBundleIDs: Set<String> = ["com.camlid.CamLid"]

    private var outputSince: Double?
    private var lastOutputAt: Double?
    private(set) var holding = false

    /// Pure: `outputting` is true while at least one counted process runs output. Returns whether the hold is on at `now`.
    mutating func observe(now: Double, outputting: Bool) -> Bool {
        if outputting {
            lastOutputAt = now
            let since = outputSince ?? now
            outputSince = since
            if now - since >= Self.startSeconds { holding = true }
        } else {
            outputSince = nil
            if let lastOutputAt, now - lastOutputAt > Self.quietSeconds { holding = false }
        }
        return holding
    }

    /// Pure: the display names of the processes that count at this read. A process counts when it runs output, is not excluded,
    /// and is not already counted by an enabled spec 025 source (so it is not counted twice). `names` maps a PID to its process
    /// name and its app name, and the app name is preferred for Activity (spec 029 D5).
    static func countedNames(in processes: [MusicOutput.Process], watched: Set<MusicSource>,
                             names: (Int32) -> (process: String?, app: String?) = liveNames) -> [String] {
        processes.compactMap { process -> String? in
            guard process.isOutputting else { return nil }
            if let bundleID = process.bundleID {
                if excludedBundleIDs.contains(bundleID) { return nil }
                if let source = MusicSource.matching(bundleID: bundleID), watched.contains(source) { return nil }
            }
            let found = names(process.pid)
            if let processName = found.process, excludedProcessNames.contains(processName) { return nil }
            return found.app ?? found.process ?? process.bundleID
        }
    }

    /// Live names: the app's name when macOS has one, and the process name from its path.
    static func liveNames(_ pid: Int32) -> (process: String?, app: String?) {
        (PlaybackAssertion.processName(Int(pid)), NSRunningApplication(processIdentifier: pid)?.localizedName)
    }
}
