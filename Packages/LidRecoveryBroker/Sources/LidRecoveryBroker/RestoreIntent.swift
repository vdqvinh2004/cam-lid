import Foundation
import LidRecoveryJournal

// Shared journal-only operation. It neither restores policy nor proves ownership.
func restoreIntent(after previous: JournalEntry) throws -> JournalEntry {
    guard previous.revision < UInt64.max else { throw JournalFailure.revisionConflict }
    return JournalEntry(revision: previous.revision + 1, sessionID: previous.sessionID,
        ownerIdentity: previous.ownerIdentity, bootID: previous.bootID,
        generation: previous.generation, operationID: UUID().uuidString,
        intent: .restoreLidPolicy, disposition: .unresolved,
        continuousDeadlineNanos: previous.continuousDeadlineNanos)
}
