import Testing
@testable import CamLidCore

@Suite struct SupportRowsTests {
    private let table = [SupportRow(id: "row-1", model: "Mac17,1", osBuild: "27A1")]

    @Test func aRowMatchesOnlyTheExactModelAndBuild() {
        #expect(QualifiedSupportRows.matching(model: "Mac17,1", osBuild: "27A1", in: table) == "row-1")
        #expect(QualifiedSupportRows.matching(model: "Mac17,1", osBuild: "27A2", in: table) == nil)
        #expect(QualifiedSupportRows.matching(model: "Mac17,2", osBuild: "27A1", in: table) == nil)
        #expect(QualifiedSupportRows.matching(model: nil, osBuild: "27A1", in: table) == nil)
        #expect(QualifiedSupportRows.matching(model: "Mac17,1", osBuild: nil, in: table) == nil)
    }

    /// Tripwire: adding a row is a safety decision that needs the owner's approval after the attended trial.
    @Test func noRowIsQualifiedInShippedCode() {
        #expect(QualifiedSupportRows.rows.isEmpty)
        let system = QualifiedSupportRows.currentSystem()
        #expect(QualifiedSupportRows.matching(model: system.model, osBuild: system.osBuild) == nil)
    }

    @Test func theCurrentSystemIsReadable() {
        let system = QualifiedSupportRows.currentSystem()
        #expect(system.model?.isEmpty == false && system.osBuild?.isEmpty == false)
    }
}
