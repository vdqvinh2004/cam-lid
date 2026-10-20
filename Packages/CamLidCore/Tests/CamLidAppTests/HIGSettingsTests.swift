import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

@Suite("HIG settings draft outcomes")
struct HIGSettingsTests {
    @Test @MainActor func invalidTextNeverSavesOldNumericValue() throws {
        let original = try Configuration()
        let editor = SettingsEditor(configuration: original, revision: 1)
        editor.numbers[.runCap] = "not a number"
        var calls = 0
        #expect(!editor.save { _, _ in calls += 1; return .saved(revision: 2) })
        #expect(calls == 0)
        #expect(editor.isDirty)
        #expect(editor.numbers[.runCap] == "not a number")
        #expect(editor.errors.contains { $0.field == .runCap })
    }
    @Test @MainActor func conflictPreservesDraftUntilExplicitReload() throws {
        var current = try Configuration(); current.runCapMinutes = 90
        let editor = SettingsEditor(configuration: try Configuration(), revision: 1, section: .safety)
        editor.numbers[.runCap] = "45"
        let conflictSaved = editor.save { _, expected in
            #expect(expected == 1)
            return .conflict(configuration: current, revision: 2)
        }
        #expect(!conflictSaved)
        #expect(editor.numbers[.runCap] == "45")
        #expect(editor.revision == 1 && editor.conflict)
        editor.reloadAfterConflict()
        #expect(editor.numbers[.runCap] == "90")
        #expect(editor.revision == 2 && !editor.isDirty)
        #expect(editor.section == .safety)
    }
    @Test @MainActor func failedCommitPreservesDraftAndValidCommitIsAtomic() throws {
        let editor = SettingsEditor(configuration: try Configuration(), revision: 4)
        editor.numbers[.completionDelay] = "3"
        #expect(!editor.save { _, _ in .failed("Storage unavailable") })
        #expect(editor.isDirty && editor.revision == 4)
        let saved = editor.save { config, revision in
            #expect(config.completionDelayMinutes == 3 && revision == 4)
            return .saved(revision: 5)
        }
        #expect(saved)
        #expect(!editor.isDirty && editor.revision == 5)
    }
}
