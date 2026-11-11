import Testing
import CamLidCore
@testable import CamLidApp

// Which provider state changes are written to Activity history. Behaviour under test: AppCoordinator.isNewsForHistory.
// OutcomeNotificationsTests reads the "agentStateChanged" lines that this rule keeps.
@Suite("Activity history keeps news only")
@MainActor struct AgentHistoryTests {
    @Test func idleAndUnknownFlickerIsNotHistory() {
        #expect(!AppCoordinator.isNewsForHistory(from: .idle, to: .unknown))
        #expect(!AppCoordinator.isNewsForHistory(from: .unknown, to: .idle))
        #expect(!AppCoordinator.isNewsForHistory(from: nil, to: .idle))
        #expect(!AppCoordinator.isNewsForHistory(from: nil, to: .unknown))
    }

    @Test func startingAndEndingWorkIsHistory() {
        #expect(AppCoordinator.isNewsForHistory(from: .idle, to: .working))
        #expect(AppCoordinator.isNewsForHistory(from: .working, to: .idle))
        #expect(AppCoordinator.isNewsForHistory(from: .unknown, to: .working))
        #expect(AppCoordinator.isNewsForHistory(from: .working, to: .unknown))
        #expect(AppCoordinator.isNewsForHistory(from: nil, to: .working))
    }

    @Test func waitingCompletionAndFailureAreHistory() {
        #expect(AppCoordinator.isNewsForHistory(from: .working, to: .waiting))
        #expect(AppCoordinator.isNewsForHistory(from: .idle, to: .waiting))
        #expect(AppCoordinator.isNewsForHistory(from: .working, to: .completed))
        #expect(AppCoordinator.isNewsForHistory(from: .idle, to: .failed))
        #expect(AppCoordinator.isNewsForHistory(from: .failed, to: .idle))
    }

    @Test func anUnchangedStateIsNeverHistory() {
        for state in [TaskState.idle, .working, .waiting, .unknown, .completed, .failed] {
            #expect(!AppCoordinator.isNewsForHistory(from: state, to: state))
        }
    }
}
