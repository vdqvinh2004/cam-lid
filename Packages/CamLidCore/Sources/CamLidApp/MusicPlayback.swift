import CoreAudio
import Darwin
import Foundation
import IOKit.pwr_mgt

/// Spec 025: a music source that keeps an Auto session awake while it plays. CoreAudio lists the processes that run audio
/// output. A browser and Apple Music also hold a playback assertion while they play (`PlaybackAssertion`). Both reads need no
/// permission and send nothing to the program.
public enum MusicSource: String, CaseIterable, Codable, Sendable {
    case browser, spotify, appleMusic, safari

    /// Bundle identifiers. A helper matches by prefix: "com.brave.Browser.helper" is Brave.
    /// shortcut: only Brave was checked live; check any other browser's output process on this Mac before relying on it.
    var bundleIDs: [String] {
        switch self {
        case .browser:
            ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
             "com.operasoftware.Opera", "company.thebrowser.Browser", "org.chromium.Chromium"]
        case .spotify: ["com.spotify.client"]
        case .appleMusic: ["com.apple.Music"]
        case .safari: ["com.apple.Safari", "com.apple.WebKit.GPU"]
        }
    }

    /// The source's name in the Dashboard status.
    public var name: String {
        switch self {
        case .browser: "a browser"
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        case .safari: "Safari"
        }
    }

    /// The Settings chip's help.
    public var help: String {
        switch self {
        case .browser: "Chromium browsers: Chrome, Brave, Edge, Vivaldi, Opera, Arc and Chromium. Firefox is not detected."
        case .spotify: "Detected from Spotify's audio output. When the music stops, Sleep when done applies, as after agent work."
        case .appleMusic: "Detected from Music's audio output. When the music stops, Sleep when done applies, as after agent work."
        case .safari: "Detected from Safari's audio output and its media-playback assertion. When the music stops, Sleep when done applies, as after agent work."
        }
    }

    /// The source that owns a bundle identifier, or nil. A prefix must end at a dot: "com.spotify.clientx" is not Spotify.
    static func matching(bundleID: String) -> MusicSource? {
        allCases.first { source in source.bundleIDs.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") } }
    }

    /// The sources Settings lists on this Mac. Browsers and Apple Music are always listed and can be clicked; Spotify is
    /// listed only when its app is installed.
    static func listedSources(installed: Set<MusicSource>) -> [MusicSource] {
        allCases.filter { $0 != .spotify || installed.contains($0) }
    }
}

/// The processes that run audio output right now. CoreAudio reports them from macOS 14.2; earlier systems detect nothing.
enum MusicOutput {
    struct Process: Equatable {
        let bundleID: String?
        let isOutputting: Bool
    }

    /// Live: reads CoreAudio's process list.
    static func processes() -> [Process] {
        guard #available(macOS 14.2, *) else { return [] }
        return processObjects().map { object in
            Process(bundleID: bundleID(of: object), isOutputting: flag(kAudioProcessPropertyIsRunningOutput, of: object))
        }
    }

    /// Pure: what one read found. `outputting` lists the watched sources with a process running audio output, and
    /// `assertionHeld` the outputting sources whose playback assertion is held. `holders` is read only when a browser, Safari or Apple
    /// Music outputs, so an idle Mac reads no assertions.
    static func reading(in processes: [Process], watched: Set<MusicSource>, holders: () -> [AssertionHolder]) -> MusicReading {
        let outputting = Set(processes.compactMap { process -> MusicSource? in
            guard process.isOutputting, let bundleID = process.bundleID else { return nil }
            return MusicSource.matching(bundleID: bundleID)
        }).intersection(watched)
        let gated = outputting.intersection([.browser, .appleMusic, .safari])
        guard !gated.isEmpty else { return MusicReading(outputting: outputting) }
        let table = holders()
        return MusicReading(outputting: outputting, assertionHeld: gated.filter { PlaybackAssertion.isHeld($0, in: table) })
    }

    @available(macOS 14.2, *)
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    @available(macOS 14.2, *)
    private static func processObjects() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    @available(macOS 14.2, *)
    private static func flag(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> Bool {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr && value == 1
    }

    @available(macOS 14.2, *)
    private static func bundleID(of object: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var reference: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &reference) == noErr, let reference else { return nil }
        return reference.takeRetainedValue() as String
    }
}

/// What one read found: the watched sources with audio output, and the outputting ones whose playback assertion is held.
struct MusicReading: Equatable {
    var outputting: Set<MusicSource> = []
    var assertionHeld: Set<MusicSource> = []
}

/// A process that holds power assertions, identified by its executable name.
struct AssertionHolder {
    let processName: String
    let assertions: [[String: Any]]
}

/// The playback assertions (read from IOKit; no permission is needed). A Chromium browser holds the named "Playing audio" assertion
/// and Apple's Music app holds "com.apple.Music.playback" while audio plays. Each is released when playback stops, and a silent output
/// stream holds neither. Measured: Brave's assertion went about 2 to 3 s after pause, and Music's went at the pause, while each output
/// stream stayed open for about 5 to 10 s. Safari's media playback holds "com.apple.WebCore: HTMLMediaElement playback" under its own process name, so only Safari matches it. Spotify holds no assertion, so it is judged by its output alone.
enum PlaybackAssertion {
    struct Signal {
        let processNames: [String]
        let assertionName: String
        let assertionType: String
    }

    /// Browser process names. A helper is named "<browser> Helper (...)", so a name matches its browser by prefix.
    /// shortcut: only Brave was checked live; check another browser's assertion before relying on it.
    static let browserProcessNames = ["Google Chrome", "Chromium", "Brave Browser", "Microsoft Edge", "Vivaldi", "Opera", "Arc"]

    static func signal(for source: MusicSource) -> Signal? {
        switch source {
        case .browser:
            Signal(processNames: browserProcessNames, assertionName: "Playing audio", assertionType: "NoIdleSleepAssertion")
        case .appleMusic:
            Signal(processNames: ["Music"], assertionName: "com.apple.Music.playback", assertionType: "PreventUserIdleSystemSleep")
        case .safari:
            Signal(processNames: ["Safari"], assertionName: "com.apple.WebCore: HTMLMediaElement playback", assertionType: "PreventUserIdleSystemSleep")
        case .spotify:
            nil
        }
    }

    /// Pure: whether a source's playback assertion is held by one of the holders.
    static func isHeld(_ source: MusicSource, in holders: [AssertionHolder]) -> Bool {
        guard let signal = signal(for: source) else { return false }
        return holders.contains { holder in
            signal.processNames.contains { isNamed(holder.processName, $0) } && holder.assertions.contains {
                ($0["AssertName"] as? String) == signal.assertionName && ($0["AssertType"] as? String) == signal.assertionType
            }
        }
    }

    /// Live: reads this Mac's power assertions with the executable name of each holder. Copy APIs transfer ownership, also on error.
    static func holders() -> [AssertionHolder] {
        var processes: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&processes)
        let dictionary = processes?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        guard result == kIOReturnSuccess, let dictionary else { return [] }
        return dictionary.compactMap { pid, assertions in
            processName(pid.intValue).map { AssertionHolder(processName: $0, assertions: assertions) }
        }
    }

    private static func isNamed(_ process: String, _ name: String) -> Bool {
        process == name || process.hasPrefix(name + " ")
    }

    private static func processName(_ pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid_t(pid), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
    }
}

/// Spec 025: a watched source that plays keeps an Auto session working until it stops, then Sleep when done applies, as after
/// agent work. A source judged by its playback assertion (a browser, and Apple Music once its assertion has been seen on this
/// Mac) plays only while the assertion is held, and keeps a 3-second bridge over missed reads. Spotify plays while its output
/// runs and keeps a 5-second bridge: its output had no gap at three manual track changes (2026-11-10). Apple Music before its
/// assertion is seen plays while its output runs and keeps a 10-second bridge, since its track changes are not measured.
/// Reads come every 2 s while a hold is in force, and every 5 s otherwise.
struct MusicPlaybackHold {
    static let idleSampleSeconds = 5.0
    static let holdingSampleSeconds = 2.0
    static let assertedQuietSeconds = 3.0
    static let spotifyQuietSeconds = 5.0
    static let outputOnlyQuietSeconds = 10.0
    private var lastSampleAt: Double?
    private var lastPlayingAt: [MusicSource: Double] = [:]
    private var holding: Set<MusicSource> = []
    /// Whether Apple Music's playback assertion has been seen on this Mac. Until it has, Music is judged by its output alone, so a
    /// Mac without that assertion still gets the output-only hold.
    private var musicAssertionSeen = false

    /// Whether a source is judged by its playback assertion right now.
    private func isAsserted(_ source: MusicSource) -> Bool {
        switch source {
        case .browser, .safari: true
        case .appleMusic: musicAssertionSeen
        case .spotify: false
        }
    }

    /// A source plays when its output runs, and, if it is judged by its assertion, when the assertion is held too.
    private func isPlaying(_ source: MusicSource, in reading: MusicReading) -> Bool {
        guard reading.outputting.contains(source) else { return false }
        return !isAsserted(source) || reading.assertionHeld.contains(source)
    }

    /// How long a source keeps the hold after its last playing read.
    static func quietSeconds(for source: MusicSource, asserted: Bool) -> Double {
        if asserted { return assertedQuietSeconds }
        return source == .spotify ? spotifyQuietSeconds : outputOnlyQuietSeconds
    }

    /// The sources that hold the session at `now`. `sample` reads the sources, and runs only when a read is due.
    mutating func observe(now: Double, sample: () -> MusicReading) -> Set<MusicSource> {
        let interval = holding.isEmpty ? Self.idleSampleSeconds : Self.holdingSampleSeconds
        if lastSampleAt.map({ now - $0 >= interval }) ?? true {
            let reading = sample()
            if reading.assertionHeld.contains(.appleMusic) { musicAssertionSeen = true }
            for source in MusicSource.allCases where isPlaying(source, in: reading) {
                lastPlayingAt[source] = now
            }
            lastSampleAt = now
        }
        holding = Set(MusicSource.allCases.filter { source in
            guard let last = lastPlayingAt[source] else { return false }
            return now - last <= Self.quietSeconds(for: source, asserted: isAsserted(source))
        })
        return holding
    }
}
