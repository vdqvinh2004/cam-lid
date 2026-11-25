import AppKit
import Testing
import CamLidCore
@testable import CamLidApp

/// The three changes that cut wakeups and CPU while an Auto session keeps the Mac awake: the music sampler reads identities
/// only of outputting processes, the Orca poll runs every 15 s, and the spinner's arc is a layer animation.
struct WakeupBudgetTests {
    /// A process that is not outputting costs one CoreAudio read; an outputting process costs its identity as well.
    @Test func musicReadAsksForIdentityOnlyOfOutputtingProcesses() {
        var identityReads = 0
        let objects: [(bundle: String, outputting: Bool)] = [
            ("com.apple.finder", false), ("com.spotify.client", true), ("com.apple.Safari", false),
        ]
        let processes = MusicOutput.readProcesses(objects: objects, isOutputting: { $0.outputting },
                                                  bundleID: { object in identityReads += 1; return object.bundle },
                                                  pid: { _ in identityReads += 1; return 42 })
        #expect(identityReads == 2)
        #expect(processes == [MusicOutput.Process(bundleID: nil, isOutputting: false),
                              MusicOutput.Process(bundleID: "com.spotify.client", isOutputting: true, pid: 42),
                              MusicOutput.Process(bundleID: nil, isOutputting: false)])
    }

    /// The poll runs only while Orca is open, once per poll interval. A stale state needs three polls without a good reply,
    /// and the snapshot resolver shares that window, so the Dashboard never drops an Orca row between two normal replies.
    @Test @MainActor func orcaPollsOnlyWhileOrcaRunsAndSharesOneStaleWindow() {
        #expect(AppCoordinator.orcaPollDue(orcaRunning: false, sinceLastPoll: 3_600) == false)
        #expect(AppCoordinator.orcaPollDue(orcaRunning: true, sinceLastPoll: 14.9) == false)
        #expect(AppCoordinator.orcaPollDue(orcaRunning: true, sinceLastPoll: 15) == true)
        #expect(AppCoordinator.orcaMetadataStaleSeconds == 3 * AppCoordinator.orcaMetadataPollSeconds)
        #expect(OrcaHostResolver().maxSnapshotAgeSeconds == AppCoordinator.orcaMetadataStaleSeconds)
        #expect(AppCoordinator.orcaMetadataPollSeconds + 4.5 < AppCoordinator.orcaMetadataStaleSeconds)
    }

    /// A closed Orca costs one process per poll: the worktree listing does not run once the runtime reports it unreachable.
    @Test func unreachableOrcaSkipsTheWorktreeListing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orca-closed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("calls.log")
        let reply = #"{"ok":true,"result":{"target":{"kind":"local"},"runtime":{"appVersion":"1","reachable":false,"runtimeId":"r1"}}}"#
        let script = dir.appendingPathComponent("orca")
        try "#!/bin/sh\necho \"$*\" >> '\(log.path)'\necho '\(reply)'\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        #expect(throws: OrcaPollError.unavailable) { try OrcaPoller(executable: script).snapshot(consent: true) }
        #expect(try String(contentsOf: log, encoding: .utf8) == "status --json\n")
    }

    /// The die is read every 5 s, and its reading stays inside the 10 s stale window with one pass and one stall to spare.
    @Test func temperatureIsReadEveryFiveSecondsInsideItsStaleWindow() {
        #expect(LiveSensorProvider.temperatureIsDue(now: 0, lastStarted: nil))
        #expect(!LiveSensorProvider.temperatureIsDue(now: 4.9, lastStarted: 0))
        #expect(LiveSensorProvider.temperatureIsDue(now: 5, lastStarted: 0))
        #expect(LiveSensorProvider.temperatureIsDue(now: 0, lastStarted: 10))
        #expect(LiveSensorProvider.temperatureSampleSeconds + 1 + LiveSensorProvider.stallBudgetSeconds
            < TemperatureObservation.staleAfterSeconds)
    }

    /// The arc turns while activity keeps the Mac awake and stops when it does not; the laptop is the button's own still image.
    @Test @MainActor func spinnerTurnsOnlyWhileActivityHolds() throws {
        let actions = SpinnerActions()
        actions.mode = .auto
        let controller = MenuBarController()
        controller.actions = actions
        defer { controller.remove() }
        controller.install()
        let button = try #require(controller.anchorButton)
        func turning() -> [NSView] { button.subviews.filter { $0.layer?.animation(forKey: "camlid.autoSpin") != nil } }

        controller.update(status: MenuBarStatus(state: .protected, leaseVerified: true, activityHolding: true))
        #expect(turning().count == 1 && turning().allSatisfy { !$0.isHidden })
        #expect(button.image != nil && button.image?.isTemplate == true)

        controller.update(status: MenuBarStatus(state: .protected, leaseVerified: true, activityHolding: false))
        #expect(turning().isEmpty)
        #expect(button.subviews.allSatisfy { $0.isHidden || $0.layer?.animation(forKey: "camlid.autoSpin") == nil })
    }

    /// The arc turns clockwise once per twelve frames (1.2 s) for as long as the session runs, as the frames it replaces did.
    @Test @MainActor func spinAnimationTurnsClockwiseOncePerTurn() throws {
        let spin = MenuBarController.spinAnimation()
        #expect(spin.keyPath == "transform.rotation.z")
        #expect(spin.duration == 1.2)
        #expect(spin.repeatCount == .infinity)
        #expect(try #require(spin.fromValue as? Double) == 0)
        #expect(try #require(spin.toValue as? Double) == -2 * Double.pi)
    }

    /// The arc sits in the badge, the lower right corner of the mark, as drawn. The status button is flipped, so its bottom
    /// is the larger y. This reads the drawn pixels, not the frame the code computes.
    @Test @MainActor func spinnerArcSitsInTheBadgeCorner() throws {
        let actions = SpinnerActions()
        actions.mode = .auto
        let controller = MenuBarController()
        controller.actions = actions
        defer { controller.remove() }
        controller.install()
        let button = try #require(controller.anchorButton)
        controller.update(status: MenuBarStatus(state: .protected, leaseVerified: true, activityHolding: true))
        let arcView = try #require(button.subviews.compactMap { $0 as? NSImageView }.first)
        arcView.layer?.removeAnimation(forKey: "camlid.autoSpin")
        arcView.isHidden = false
        let withArc = Self.rendered(button)
        arcView.isHidden = true
        let laptopOnly = Self.rendered(button)
        let scale = CGFloat(laptopOnly.pixelsWide) / button.bounds.width
        let laptop = try #require(Self.opaqueBox(laptopOnly, scale: scale, height: button.bounds.height, flipped: button.isFlipped))
        let arc = try #require(Self.opaqueBox(withArc, excluding: laptopOnly, scale: scale, height: button.bounds.height,
                                              flipped: button.isFlipped))
        #expect(arc.midX > laptop.midX)
        #expect((arc.midY - laptop.midY) * (button.isFlipped ? 1 : -1) > 0)
    }

    @MainActor private static func rendered(_ view: NSView) -> NSBitmapImageRep {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// Bounding box of the opaque pixels in the view's points, leaving out pixels already opaque in `other`.
    @MainActor private static func opaqueBox(_ rep: NSBitmapImageRep, excluding other: NSBitmapImageRep? = nil, scale: CGFloat,
                                  height: CGFloat, flipped: Bool) -> NSRect? {
        guard let data = rep.bitmapData else { return nil }
        let spp = rep.samplesPerPixel
        var minCol = Int.max, maxCol = -1, minRow = Int.max, maxRow = -1
        for row in 0..<rep.pixelsHigh {
            for col in 0..<rep.pixelsWide {
                guard data[row * rep.bytesPerRow + col * spp + spp - 1] > 0 else { continue }
                if let other, let otherData = other.bitmapData,
                   otherData[row * other.bytesPerRow + col * other.samplesPerPixel + other.samplesPerPixel - 1] > 0 { continue }
                minCol = min(minCol, col); maxCol = max(maxCol, col); minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        guard maxCol >= 0 else { return nil }
        // Rows run from the top of the view. A flipped view measures y the same way; otherwise y starts at the bottom.
        let top = CGFloat(minRow) / scale, bottom = CGFloat(maxRow + 1) / scale
        return NSRect(x: CGFloat(minCol) / scale, y: flipped ? top : height - bottom,
                      width: CGFloat(maxCol + 1 - minCol) / scale, height: bottom - top)
    }
}

@MainActor
private final class SpinnerActions: MenuBarActions {
    var mode: RequestedMode?
    var menuBarCanStart = true
    var menuBarCanStop = true
    var menuBarAutoAvailable = true
    var menuBarActiveMode: RequestedMode? { mode }
    func menuBarStartProtection() {}
    func menuBarStopProtection() {}
    func menuBarOpenSettings() {}
    func menuBarOpenActivityLog() {}
    func menuBarQuit() {}
}
