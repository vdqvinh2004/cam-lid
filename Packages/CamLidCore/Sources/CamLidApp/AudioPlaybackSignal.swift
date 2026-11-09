import Darwin
import Foundation
import IOKit.pwr_mgt

/// Spec 023, User Story 3 (FR-007): a Chromium-based browser that holds a named "Playing audio" power assertion is playing
/// audio. Research (spec 019, T070) found no other reliable signal: coreaudiod's assertion is the same with or without
/// playback. Other apps are not detected.
enum AudioPlaybackSignal {
    static let assertionName = "Playing audio"
    static let assertionType = "NoIdleSleepAssertion"
    /// shortcut: browsers are matched by process name, not bundle ID; add one only after checking it live.
    static let browserNames = ["Google Chrome", "Chromium", "Brave Browser", "Microsoft Edge", "Vivaldi", "Opera", "Arc"]

    /// Pure: whether a browser process holds the named playback assertion. `assertions` maps a process ID to the
    /// assertion dictionaries the power manager reported for it.
    static func isPlaybackHeld(assertions: [Int: [[String: Any]]], processName: (Int) -> String?) -> Bool {
        assertions.contains { pid, entries in
            guard let name = processName(pid), browserNames.contains(where: { isNamed(name, $0) }) else { return false }
            return entries.contains {
                ($0["AssertName"] as? String) == assertionName && ($0["AssertType"] as? String) == assertionType
            }
        }
    }

    /// Live: reads this Mac's power assertions and the executables that hold them.
    static func isPlayingAudio() -> Bool {
        var processes: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&processes)
        // Copy APIs transfer ownership, including on error.
        let dictionary = processes?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        guard result == kIOReturnSuccess, let dictionary else { return false }
        let assertions = Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key.intValue, $0.value) })
        return isPlaybackHeld(assertions: assertions, processName: processName)
    }

    /// A browser's helper processes are named "<browser> Helper (...)", so a name matches its browser or a name with a space.
    private static func isNamed(_ name: String, _ browser: String) -> Bool {
        name == browser || name.hasPrefix(browser + " ")
    }

    private static func processName(_ pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }
}

/// Spec 023, User Story 3 (SC-004): the hold keeps an Auto session working while audio plays, and for a quiet period after.
/// It never holds without a playback observation. The power manager is read at most every `sampleEverySeconds`, which is
/// far finer than the quiet period.
struct AudioPlaybackHold {
    static let quietSeconds = 60.0
    static let sampleEverySeconds = 5.0
    private var lastSampleAt: Double?
    private var lastSamplePlaying = false
    private var lastPlayingAt: Double?

    /// Whether the hold is in force at `now`. `sample` reads the power manager, and runs only when a read is due.
    mutating func observe(now: Double, sample: () -> Bool) -> Bool {
        if lastSampleAt.map({ now - $0 >= Self.sampleEverySeconds }) ?? true {
            lastSamplePlaying = sample()
            lastSampleAt = now
        }
        if lastSamplePlaying { lastPlayingAt = now }
        guard let lastPlayingAt else { return false }
        return now - lastPlayingAt <= Self.quietSeconds
    }
}
