import Foundation
import Testing
@testable import CamLidApp

/// Spec 025: a music source is recognised by its bundle identifier, only watched sources count, and the hold keeps an Auto
/// session working for a short quiet period after playback stops.
@Suite("Music playback hold")
struct MusicPlaybackTests {
    @Test func bundleIdentifiersAndTheirHelpersMatchTheirSource() {
        #expect(MusicSource.matching(bundleID: "com.brave.Browser.helper") == .browser)
        #expect(MusicSource.matching(bundleID: "com.brave.Browser") == .browser)
        #expect(MusicSource.matching(bundleID: "com.spotify.client") == .spotify)
        #expect(MusicSource.matching(bundleID: "com.apple.Music") == .appleMusic)
        #expect(MusicSource.matching(bundleID: "com.apple.Music.helper") == .appleMusic)
        #expect(MusicSource.matching(bundleID: "com.spotify.clientx") == nil)   // a prefix must end at a dot
        #expect(MusicSource.matching(bundleID: "com.apple.Safari") == nil)       // Safari is not detected
    }

    @Test func onlyWatchedSourcesThatAreOutputtingCount() {
        let processes = [
            MusicOutput.Process(bundleID: "com.brave.Browser.helper", isOutputting: true),
            MusicOutput.Process(bundleID: "com.spotify.client", isOutputting: false),
            MusicOutput.Process(bundleID: "com.apple.Music", isOutputting: true),
            MusicOutput.Process(bundleID: nil, isOutputting: true),
        ]
        #expect(MusicOutput.activeSources(in: processes, watched: [.spotify]).isEmpty)
        #expect(MusicOutput.activeSources(in: processes, watched: [.browser, .appleMusic]) == [.browser, .appleMusic])
        #expect(MusicOutput.activeSources(in: processes, watched: []).isEmpty)
    }

    @Test func theHoldBridgesSamplesAndEndsAfterAQuietPeriod() {
        var hold = MusicPlaybackHold()
        #expect(hold.observe(now: 0) { [.browser] } == [.browser])
        #expect(hold.observe(now: 5) { [] } == [.browser])          // still within the quiet period
        #expect(hold.observe(now: 10) { [] } == [.browser])         // at the quiet limit
        #expect(hold.observe(now: 15) { [] }.isEmpty)               // after it
        #expect(hold.observe(now: 20) { [.spotify] } == [.spotify]) // a new source resumes the hold
    }

    @Test func theOutputsAreReadAtMostEveryFiveSeconds() {
        var hold = MusicPlaybackHold()
        var reads = 0
        for second in 0...12 {
            _ = hold.observe(now: Double(second)) { reads += 1; return [] }
        }
        #expect(reads == 3)                                          // at 0, 5 and 10 seconds
    }
}
