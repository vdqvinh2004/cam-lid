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
        #expect(MusicSource.matching(bundleID: "org.mozilla.firefox") == nil)    // Firefox is not detected
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

    @Test func aMutedBrowserKeepsItsHoldWhileItsOutputRunsAndEndsThreeSecondsAfterThePause() {
        var hold = MusicPlaybackHold()
        #expect(hold.observe(now: 0) { MusicReading(outputting: [.browser], assertionHeld: [.browser]) } == [.browser])
        #expect(hold.observe(now: 2) { MusicReading(outputting: [.browser]) } == [.browser])   // muted: the assertion is released, the output runs
        #expect(hold.observe(now: 600) { MusicReading(outputting: [.browser]) } == [.browser])  // still muted ten minutes later
        #expect(hold.observe(now: 602) { MusicReading() } == [.browser])                        // paused: the bridge holds for 3 s
        #expect(hold.observe(now: 606) { MusicReading() }.isEmpty)                              // more than 3 s after the last playing read
    }

    @Test func aBrowserWhoseOutputNeverHeldTheAssertionHoldsNothing() {
        var hold = MusicPlaybackHold()
        #expect(hold.observe(now: 0) { MusicReading(outputting: [.browser]) }.isEmpty)
        #expect(hold.observe(now: 600) { MusicReading(outputting: [.browser]) }.isEmpty)     // silent output that never held the assertion
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

    @Test func settingsListsBrowsersAppleMusicAndSafariAlwaysAndSpotifyOnlyWhenInstalled() {
        #expect(MusicSource.listedSources(installed: []) == [.browser, .appleMusic, .safari])
        #expect(MusicSource.listedSources(installed: [.spotify]) == [.browser, .spotify, .appleMusic, .safari])
        #expect(MusicSource.listedSources(installed: [.browser, .appleMusic]) == [.browser, .appleMusic, .safari])
    }

    @Test func safariIsDetectedByWebKitOutputAndItsOwnMediaAssertion() {
        #expect(MusicSource.matching(bundleID: "com.apple.WebKit.GPU") == .safari)
        #expect(MusicSource.matching(bundleID: "com.apple.Safari") == .safari)
        let safari = AssertionHolder(processName: "Safari",
            assertions: [["AssertName": "com.apple.WebCore: HTMLMediaElement playback", "AssertType": "PreventUserIdleSystemSleep"]])
        let mail = AssertionHolder(processName: "Mail",
            assertions: [["AssertName": "com.apple.WebCore: HTMLMediaElement playback", "AssertType": "PreventUserIdleSystemSleep"]])
        #expect(PlaybackAssertion.isHeld(.safari, in: [safari]))
        #expect(!PlaybackAssertion.isHeld(.safari, in: [mail]))   // another WebKit app's playback is not Safari's
        #expect(!PlaybackAssertion.isHeld(.safari, in: [chromium]))
    }

    @Test func safariCountsWhetherItsVideoHoldsTheDisplayTypeOrItsAudioIsHeldByRunningBoard() {
        // macOS 27.0.1: a video holds the named assertion as display sleep; audio is held by runningboardd for Safari's app.
        let video = AssertionHolder(processName: "Safari",
            assertions: [["AssertName": "com.apple.WebCore: HTMLMediaElement playback", "AssertType": "PreventUserIdleDisplaySleep"]])
        let audio = AssertionHolder(processName: "runningboardd",
            assertions: [["AssertName": "app<application.com.apple.Safari.96478.97144(501)>417-80460-398019:WebKit Media Playback",
                          "AssertType": "PreventUserIdleSystemSleep"]])
        let otherApp = AssertionHolder(processName: "runningboardd",
            assertions: [["AssertName": "app<application.com.apple.mail.1.2(501)>417-1-1:WebKit Media Playback",
                          "AssertType": "PreventUserIdleSystemSleep"]])
        #expect(PlaybackAssertion.isHeld(.safari, in: [video]))
        #expect(PlaybackAssertion.isHeld(.safari, in: [audio]))
        #expect(!PlaybackAssertion.isHeld(.safari, in: [otherApp]))   // WebKit media of another app is not Safari's
        #expect(!PlaybackAssertion.isHeld(.safari, in: [AssertionHolder(processName: "runningboardd", assertions: video.assertions)]))
        let notASleepType = AssertionHolder(processName: "Safari",
            assertions: [["AssertName": "com.apple.WebCore: HTMLMediaElement playback", "AssertType": "NoIdleSleepAssertion"]])
        #expect(!PlaybackAssertion.isHeld(.safari, in: [notASleepType]))
    }

    @Test func safariCountsOnlyWhileItsOutputAndItsAssertionAreBothPresent() {
        let safari = AssertionHolder(processName: "Safari",
            assertions: [["AssertName": "com.apple.WebCore: HTMLMediaElement playback", "AssertType": "PreventUserIdleSystemSleep"]])
        let reading = MusicOutput.reading(in: [MusicOutput.Process(bundleID: "com.apple.WebKit.GPU", isOutputting: true)],
            watched: [.safari], holders: { [safari] })
        #expect(reading == MusicReading(outputting: [.safari], assertionHeld: [.safari]))
        var hold = MusicPlaybackHold()
        #expect(hold.observe(now: 0) { MusicReading(outputting: [.safari]) }.isEmpty)
        #expect(hold.observe(now: 6) { reading } == [.safari])
    }
}
