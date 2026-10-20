import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

struct HistoryAdmissionTests {
    @Test func sealedWorkerRejectsMutationsButDrainsPriorWorkAndReads() async throws {
        let storage = InMemoryHistoryStorage()
        let recorder = AsyncHistoryRecorder(store: ActivityStore(storage: storage))
        let record = try StoredTransition(stateRevision: 1, category: .configuration,
            previousState: .ready, newState: .ready, reasonCodes: ["test"])
        #expect(recorder.record(record))
        recorder.sealMutations()
        #expect(!recorder.record(record))
        #expect(await recorder.delete(sessionID: nil) == nil)
        #expect(await recorder.flush())
        #expect(await recorder.transitions()?.count == 1)
        #expect(recorder.lastError == nil)
        recorder.resumeMutations()
        #expect(await recorder.delete(sessionID: nil)?.removedCount == 1)
        #expect(await recorder.flush())
        #expect(await recorder.transitions()?.isEmpty == true)
    }
}
