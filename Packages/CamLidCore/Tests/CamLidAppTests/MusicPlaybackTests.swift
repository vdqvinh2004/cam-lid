import Foundation
import Testing
@testable import CamLidApp

/// Spec 025: a music source is recognised by its bundle identifier, only watched sources count, a browser and Apple Music are
/// judged by their playback assertions (Music once it has been seen), and the hold ends after a quiet period.
@Suite("Music playback hold")
struct MusicPlaybackTests {
    private let chromium = AssertionHolder(processName: "Brave Browser Helper (Renderer)",
                                           assertions: [["AssertName": "Playing audio", "AssertType": "NoIdleSleepAssertion"]])
    private let music = AssertionHolder(processName: "Music",
                                        assertions: [["AssertName": "com.apple.Music.playback", "AssertType": "PreventUserIdleSystemSleep"]])

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
        #expect(MusicOutput.reading(in: processes, watched: [.spotify], holders: { [chromium, music] }).outputting.isEmpty)
        #expect(MusicOutput.reading(in: processes, watched: [.browser, .appleMusic], holders: { [chromium, music] }).outputting
                == [.browser, .appleMusic])
        #expect(MusicOutput.reading(in: processes, watched: [], holders: { [chromium, music] }).outputting.isEmpty)
    }

    @Test func aBrowserWithSilentOutputIsNotAssertedWithoutThePlaybackAssertion() {
        let browserOutput = [MusicOutput.Process(bundleID: "com.brave.Browser.helper", isOutputting: true)]
        #expect(MusicOutput.reading(in: browserOutput, watched: [.browser], holders: { [] }).assertionHeld.isEmpty)
        #expect(MusicOutput.reading(in: browserOutput, watched: [.browser], holders: { [chromium] }).assertionHeld == [.browser])
    }

    @Test func aPlaybackAssertionIsReadOnlyWhenAGatedSourceIsOutputting() {
        var reads = 0
        let spotifyOnly = [MusicOutput.Process(bundleID: "com.spotify.client", isOutputting: true)]
        _ = MusicOutput.reading(in: spotifyOnly, watched: [.spotify]) { reads += 1; return [] }
        _ = MusicOutput.reading(in: [], watched: [.browser, .appleMusic]) { reads += 1; return [] }
        #expect(reads == 0)
    }

    @Test func theBrowserHoldEndsThreeSecondsAfterItsLastPlayingRead() {
        var hold = MusicPlaybackHold()
        #expect(hold.observe(now: 0) { MusicReading(outputting: [.browser], assertionHeld: [.browser]) } == [.browser])
        #expect(hold.observe(now: 2) { MusicReading(outputting: [.browser]) } == [.browser])   // one missed read is bridged
        #expect(hold.observe(now: 4) { MusicReading(outputting: [.browser]) }.isEmpty)         // more than 3 s after the last playing read
    }

    @Test func spotifyHoldsFiveSecondsAfterItsLastOutput() {
        var hold = MusicPlaybackHold()
        #expect(hold.observe(now: 0) { MusicReading(outputting: [.spotify]) } == [.spotify])
        #expect(hold.observe(now: 8) { MusicReading(outputting: [.spotify]) } == [.spotify])
        #expect(hold.observe(now: 12) { MusicReading() } == [.spotify])     // 4 s after the last output: still within 5 s
        #expect(hold.observe(now: 14) { MusicReading() }.isEmpty)           // 6 s after: ended
    }

    @Test func aTrackChangeWithAShortGapDoesNotEndSpotifyHold() {
        var hold = MusicPlaybackHold()
        #expect(hold.observe(now: 0) { MusicReading(outputting: [.spotify]) } == [.spotify])
        #expect(hold.observe(now: 2) { MusicReading() } == [.spotify])      // a 2-second gap is bridged
        #expect(hold.observe(now: 4) { MusicReading(outputting: [.spotify]) } == [.spotify])
    }

    @Test func appleMusicIsJudgedByItsOutputUntilItsAssertionHasBeenSeen() {
        var hold = MusicPlaybackHold()
        #expect(hold.observe(now: 0) { MusicReading(outputting: [.appleMusic]) } == [.appleMusic])
        #expect(hold.observe(now: 8) { MusicReading(outputting: [.appleMusic]) } == [.appleMusic])
        #expect(hold.observe(now: 18) { MusicReading() } == [.appleMusic])   // 10 s after the last output: still held
        #expect(hold.observe(now: 20) { MusicReading() }.isEmpty)            // more than 10 s: ended
    }

    @Test func appleMusicStopsWhenItsAssertionGoesOnceSeen() {
        var hold = MusicPlaybackHold()
        // The assertion is seen while Music outputs.
        #expect(hold.observe(now: 0) { MusicReading(outputting: [.appleMusic], assertionHeld: [.appleMusic]) } == [.appleMusic])
        #expect(hold.observe(now: 2) { MusicReading(outputting: [.appleMusic], assertionHeld: [.appleMusic]) } == [.appleMusic])
        // Pause: the assertion goes while the output stays open for a while.
        #expect(hold.observe(now: 4) { MusicReading(outputting: [.appleMusic]) } == [.appleMusic])   // one missed read is bridged
        #expect(hold.observe(now: 6) { MusicReading(outputting: [.appleMusic]) }.isEmpty)            // more than 3 s: ended
    }

    @Test func theReadsAreEveryFiveSecondsWhenIdleAndEveryTwoWhileHolding() {
        var hold = MusicPlaybackHold()
        var reads: [Double] = []
        for second in stride(from: 0.0, through: 10.0, by: 1.0) {
            _ = hold.observe(now: second) { reads.append(second); return MusicReading() }
        }
        #expect(reads == [0, 5, 10])
        reads = []
        for second in stride(from: 15.0, through: 21.0, by: 1.0) {
            _ = hold.observe(now: second) { reads.append(second); return MusicReading(outputting: [.browser], assertionHeld: [.browser]) }
        }
        #expect(reads == [15, 17, 19, 21])
    }

    @Test func aBrowserHoldingThePlaybackAssertionCountsAsPlaying() {
        #expect(PlaybackAssertion.isHeld(.browser, in: [chromium]))
        #expect(PlaybackAssertion.isHeld(.browser, in: [AssertionHolder(processName: "Brave Browser", assertions: chromium.assertions)]))
    }

    @Test func otherAssertionsAndOtherAppsDoNotCountAsPlayingForABrowser() {
        let otherName = AssertionHolder(processName: "Brave Browser",
                                        assertions: [["AssertName": "Wake for sync", "AssertType": "NoIdleSleepAssertion"]])
        let otherType = AssertionHolder(processName: "Brave Browser",
                                        assertions: [["AssertName": "Playing audio", "AssertType": "PreventUserIdleSystemSleep"]])
        #expect(!PlaybackAssertion.isHeld(.browser, in: [otherName, otherType]))
        #expect(!PlaybackAssertion.isHeld(.browser, in: [AssertionHolder(processName: "Music", assertions: chromium.assertions)]))
        #expect(!PlaybackAssertion.isHeld(.browser, in: [AssertionHolder(processName: "Arcade", assertions: chromium.assertions)]))   // "Arc" must not match "Arcade"
    }

    @Test func appleMusicCountsOnlyWithItsOwnPlaybackAssertion() {
        #expect(PlaybackAssertion.isHeld(.appleMusic, in: [music]))
        #expect(!PlaybackAssertion.isHeld(.appleMusic, in: [chromium]))
        #expect(!PlaybackAssertion.isHeld(.spotify, in: [music]))   // Spotify holds no signal to read
    }

    @Test func settingsListsBrowsersAndAppleMusicAlwaysAndSpotifyOnlyWhenInstalled() {
        #expect(MusicSource.listedSources(installed: []) == [.browser, .appleMusic])
        #expect(MusicSource.listedSources(installed: [.spotify]) == [.browser, .spotify, .appleMusic])
        #expect(MusicSource.listedSources(installed: [.browser, .appleMusic]) == [.browser, .appleMusic])
    }
}
