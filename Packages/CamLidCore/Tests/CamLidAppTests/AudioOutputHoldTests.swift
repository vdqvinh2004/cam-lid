import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

/// Spec 029: "Any audio" holds an Auto session once a process has output for three seconds, ends a minute after the output
/// stops, never counts system or CamLid processes, and never counts a process that an enabled spec 025 source counts.
@Suite("Any audio hold")
struct AudioOutputHoldTests {
    private let names: (Int32) -> (process: String?, app: String?) = { pid in
        switch pid {
        case 10: ("coreaudiod", nil)
        case 11: ("systemsoundserverd", nil)
        case 12: ("CamLid", nil)
        case 20: ("Spotify", "Spotify")
        case 21: ("afplay", nil)
        default: ("Helper", nil)
        }
    }

    @Test func aShortAlertNeverHolds() {
        var hold = AudioOutputHold()
        let atStart = hold.observe(now: 0, outputting: true)
        let twoSeconds = hold.observe(now: 2, outputting: true)
        let stopped = hold.observe(now: 2.5, outputting: false)
        let later = hold.observe(now: 5, outputting: false)
        #expect(!atStart && !twoSeconds && !stopped && !later)
    }

    @Test func outputThatLastsThreeSecondsHolds() {
        var hold = AudioOutputHold()
        let atStart = hold.observe(now: 0, outputting: true)
        let atThreeSeconds = hold.observe(now: 3, outputting: true)
        #expect(!atStart)
        #expect(atThreeSeconds)
    }

    @Test func theHoldEndsAMinuteAfterTheOutputStops() {
        var hold = AudioOutputHold()
        _ = hold.observe(now: 0, outputting: true)
        _ = hold.observe(now: 5, outputting: true)
        let thirtySecondsQuiet = hold.observe(now: 30, outputting: false)
        let sixtySecondsQuiet = hold.observe(now: 65, outputting: false)
        let pastAMinute = hold.observe(now: 66, outputting: false)
        #expect(thirtySecondsQuiet && sixtySecondsQuiet)
        #expect(!pastAMinute)
    }

    @Test func silenceNeverHolds() {
        var hold = AudioOutputHold()
        var heldAtAnyPoint = false
        for second in 0...120 {
            if hold.observe(now: Double(second), outputting: false) { heldAtAnyPoint = true }
        }
        #expect(!heldAtAnyPoint)
    }

    @Test func systemAndCamLidProcessesNeverCount() {
        let processes = [
            MusicOutput.Process(bundleID: nil, isOutputting: true, pid: 10),
            MusicOutput.Process(bundleID: nil, isOutputting: true, pid: 11),
            MusicOutput.Process(bundleID: "com.camlid.CamLid", isOutputting: true, pid: 12),
            MusicOutput.Process(bundleID: nil, isOutputting: true, pid: 21),
        ]
        #expect(AudioOutputHold.countedNames(in: processes, watched: [], names: names) == ["afplay"])
    }

    @Test func aProcessWithoutOutputDoesNotCount() {
        let processes = [MusicOutput.Process(bundleID: nil, isOutputting: false, pid: 21)]
        #expect(AudioOutputHold.countedNames(in: processes, watched: [], names: names).isEmpty)
    }

    @Test func theAppNameIsPreferredForActivity() {
        let processes = [MusicOutput.Process(bundleID: "com.spotify.client", isOutputting: true, pid: 20)]
        #expect(AudioOutputHold.countedNames(in: processes, watched: [], names: names) == ["Spotify"])
    }

    @Test func aProcessCountedByAnEnabledSourceIsNotCountedTwice() {
        let processes = [
            MusicOutput.Process(bundleID: "com.spotify.client", isOutputting: true, pid: 20),
            MusicOutput.Process(bundleID: nil, isOutputting: true, pid: 21),
        ]
        #expect(AudioOutputHold.countedNames(in: processes, watched: [.spotify], names: names) == ["afplay"])
        #expect(AudioOutputHold.countedNames(in: processes, watched: [], names: names) == ["Spotify", "afplay"])
    }

    @Test @MainActor func theChipIsOffByDefaultAndReportsItsChange() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1)
        #expect(!editor.anyAudioHold)
        var reported: Bool?
        editor.onSetAnyAudioHold = { reported = $0 }
        editor.setAnyAudioHold(true)
        #expect(editor.anyAudioHold && reported == true)
    }

    @Test @MainActor func theReasonNamesEachAppAndAudioAloneHoldsOnlyAnAutoSession() {
        #expect(AppCoordinator.audioReasonText(["Spotify", "VLC"]) == "Audio is playing in Spotify, VLC.")
        #expect(AppCoordinator.isHoldingForActivity(mode: .auto, agentWorking: false, musicHolding: [], audioHolding: true))
        #expect(!AppCoordinator.isHoldingForActivity(mode: .timed, agentWorking: false, musicHolding: [], audioHolding: true))
        #expect(!AppCoordinator.isHoldingForActivity(mode: nil, agentWorking: false, musicHolding: [], audioHolding: true))
    }
}
