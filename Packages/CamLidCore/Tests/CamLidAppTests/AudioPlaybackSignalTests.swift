import Foundation
import Testing
@testable import CamLidApp

/// Spec 023, User Story 3 (FR-007, SC-004): the Chromium audio hold recognises only a browser's named playback assertion,
/// and it holds for a quiet period after playback stops.
@Suite("Chromium audio hold")
struct AudioPlaybackSignalTests {
    private let playing: [String: Any] = ["AssertName": "Playing audio", "AssertType": "NoIdleSleepAssertion"]

    @Test func aBrowserHoldingThePlaybackAssertionCountsAsPlaying() {
        let found = AudioPlaybackSignal.isPlaybackHeld(assertions: [501: [playing]]) { _ in "Brave Browser Helper (Renderer)" }
        #expect(found)
    }

    @Test func otherAssertionsAndOtherAppsAreIgnored() {
        let otherName: [String: Any] = ["AssertName": "Wake for sync", "AssertType": "NoIdleSleepAssertion"]
        let otherType: [String: Any] = ["AssertName": "Playing audio", "AssertType": "PreventUserIdleSystemSleep"]
        #expect(!AudioPlaybackSignal.isPlaybackHeld(assertions: [501: [otherName, otherType]]) { _ in "Brave Browser" })
        #expect(!AudioPlaybackSignal.isPlaybackHeld(assertions: [501: [playing]]) { _ in "Music" })
        #expect(!AudioPlaybackSignal.isPlaybackHeld(assertions: [501: [playing]]) { _ in "Arcade" })   // "Arc" must not match "Arcade"
        #expect(!AudioPlaybackSignal.isPlaybackHeld(assertions: [501: [playing]]) { _ in nil })        // unknown process
    }

    @Test func theHoldEndsAfterAQuietPeriodAndNeverStartsWithoutAPlaybackObservation() {
        var hold = AudioPlaybackHold()
        let silentAtStart = hold.observe(now: 0) { false }
        let startsOnPlayback = hold.observe(now: 5) { true }
        let inQuietPeriod = hold.observe(now: 10) { false }
        let atQuietLimit = hold.observe(now: 65) { false }      // 60 s after the last playback observation (at 5 s)
        let afterQuietLimit = hold.observe(now: 70) { false }
        let resumes = hold.observe(now: 100) { true }
        #expect(!silentAtStart)
        #expect(startsOnPlayback)
        #expect(inQuietPeriod)
        #expect(atQuietLimit)
        #expect(!afterQuietLimit)
        #expect(resumes)
    }

    @Test func thePowerManagerIsReadAtMostEveryFiveSeconds() {
        var hold = AudioPlaybackHold()
        var reads = 0
        for second in 0...12 {
            _ = hold.observe(now: Double(second)) { reads += 1; return false }
        }
        #expect(reads == 3)                                     // at 0, 5 and 10 seconds
    }
}
