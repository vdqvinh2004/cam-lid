import CoreAudio
import Foundation

/// Spec 025: a music source that keeps an Auto session awake while it plays. Playback is read from CoreAudio, which lists
/// the processes that run audio output. The read needs no permission and sends nothing to the program.
public enum MusicSource: String, CaseIterable, Codable, Sendable {
    case browser, spotify, appleMusic

    /// Bundle identifiers. A helper matches by prefix: "com.brave.Browser.helper" is Brave.
    /// shortcut: only Brave was checked live; check any other browser's output process on this Mac before relying on it.
    var bundleIDs: [String] {
        switch self {
        case .browser:
            ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
             "com.operasoftware.Opera", "company.thebrowser.Browser", "org.chromium.Chromium"]
        case .spotify: ["com.spotify.client"]
        case .appleMusic: ["com.apple.Music"]
        }
    }

    /// The source's name in the Dashboard status.
    public var name: String {
        switch self {
        case .browser: "a browser"
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    /// The Settings toggle's title.
    public var toggleTitle: String {
        switch self {
        case .browser: "Keep Auto awake while a browser plays audio"
        case .spotify: "Keep Auto awake while Spotify plays"
        case .appleMusic: "Keep Auto awake while Apple Music plays"
        }
    }

    /// The Settings toggle's help.
    public var help: String {
        switch self {
        case .browser: "Chromium browsers: Chrome, Brave, Edge, Vivaldi, Opera, Arc and Chromium. Safari and Firefox are not detected."
        case .spotify: "Detected from Spotify's audio output. When the music stops, Sleep when done applies, as after agent work."
        case .appleMusic: "Detected from Music's audio output. When the music stops, Sleep when done applies, as after agent work."
        }
    }

    /// The source that owns a bundle identifier, or nil. A prefix must end at a dot: "com.spotify.clientx" is not Spotify.
    static func matching(bundleID: String) -> MusicSource? {
        allCases.first { source in source.bundleIDs.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") } }
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

    /// Pure: the watched sources that have a process running audio output.
    static func activeSources(in processes: [Process], watched: Set<MusicSource>) -> Set<MusicSource> {
        let sources = processes.compactMap { process -> MusicSource? in
            guard process.isOutputting, let bundleID = process.bundleID else { return nil }
            return MusicSource.matching(bundleID: bundleID)
        }
        return Set(sources).intersection(watched)
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

/// Spec 025 (SC-004 of spec 023, extended): a watched source that plays keeps an Auto session working. The hold lasts for a
/// short quiet period after the last playing observation, which bridges two samples. The Auto completion delay (Sleep when
/// done) then waits, as it does after agent work. The outputs are read at most every `sampleEverySeconds`.
struct MusicPlaybackHold {
    static let quietSeconds = 10.0
    static let sampleEverySeconds = 5.0
    private var lastSampleAt: Double?
    private var lastPlayingAt: [MusicSource: Double] = [:]

    /// The sources that hold the session at `now`. `sample` reads the outputs, and runs only when a read is due.
    mutating func observe(now: Double, sample: () -> Set<MusicSource>) -> Set<MusicSource> {
        if lastSampleAt.map({ now - $0 >= Self.sampleEverySeconds }) ?? true {
            for source in sample() { lastPlayingAt[source] = now }
            lastSampleAt = now
        }
        return Set(lastPlayingAt.filter { now - $0.value <= Self.quietSeconds }.keys)
    }
}
