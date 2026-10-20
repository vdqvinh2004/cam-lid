import Testing
import Foundation
import CamLidCore
@testable import CamLidApp

struct QAStoryFixtureTests {
    @Test @MainActor func allFiveStoryFixturesRemainIsolatedAndNeverProtected() async throws {
        let fixture = QARefinementSupport(); defer { fixture.cleanup() }
        let second = QARefinementSupport(); defer { second.cleanup() }
        #expect(fixture.root != second.root && fixture.suite != second.suite)
        let dashboard = fixture.dashboardFixture()
        #expect(dashboard.tasks.count == 20 && !dashboard.powerActuationAvailable && !dashboard.leaseVerified)
        let editor = try fixture.preferencesFixture()
        editor.selectPreset(5, field: .completionDelay)
        #expect(!(await editor.settle()) && editor.isDirty && editor.revision == 1)
        let readings = fixture.sensorFixtures()
        #expect(HealthMonitor().snapshot(from: readings[0], now: 20).snapshot.lidState == .closed)
        #expect(HealthMonitor().snapshot(from: readings[1], now: 20).snapshot.lid?.availability == "stale")
        #expect(readings.allSatisfy { $0.temperature == .unsupported })
        let badges = try fixture.agentFixtures()
        #expect(badges.map(\.observedState) == ["Active", "Waiting", "Inactive", "Unknown"])
        let protection = fixture.protectionFixture()
        #expect(protection.state != .protected && !protection.backendVerified && !protection.leaseVerified)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
    }
}
