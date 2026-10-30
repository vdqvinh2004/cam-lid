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
    /// Tripwire: every row is a safety decision. Change this list only together with an owner-approved G2 result.
    @Test func onlyOwnerApprovedRowsAreQualified() {
        #expect(QualifiedSupportRows.rows == [SupportRow(id: "mac17-3-26a434", model: "Mac17,3", osBuild: "26A434")])
    }

    @Test func theCurrentSystemIsReadable() {
        let system = QualifiedSupportRows.currentSystem()
        #expect(system.model?.isEmpty == false && system.osBuild?.isEmpty == false)
    }
}

@Suite struct ClosedLidPermitTests {
    private let rows = [SupportRow(id: "row-1", model: "Mac17,3", osBuild: "26A434")]
    private func ack(_ model: String = "Mac16,1", _ build: String = "26A500") -> UntestedAcknowledgement {
        UntestedAcknowledgement(model: model, osBuild: build, acceptedAt: .distantPast)
    }

    @Test func aQualifiedRowWinsWithoutAnAcknowledgement() {
        #expect(ClosedLidPermit.decide(model: "Mac17,3", osBuild: "26A434", rows: rows, acknowledgement: nil) == .qualified(rowID: "row-1"))
    }

    @Test func anUntrialledMacNeedsAMatchingAcknowledgement() {
        #expect(ClosedLidPermit.decide(model: "Mac16,1", osBuild: "26A500", rows: rows, acknowledgement: nil) == .notPermitted)
        #expect(ClosedLidPermit.decide(model: "Mac16,1", osBuild: "26A500", rows: rows, acknowledgement: ack()) == .untestedAcknowledged)
    }

    @Test func aMacOSUpdateOrAnotherMacVoidsTheAcknowledgement() {
        #expect(ClosedLidPermit.decide(model: "Mac16,1", osBuild: "26B100", rows: rows, acknowledgement: ack()) == .notPermitted)
        #expect(ClosedLidPermit.decide(model: "Mac16,2", osBuild: "26A500", rows: rows, acknowledgement: ack()) == .notPermitted)
        #expect(ClosedLidPermit.decide(model: nil, osBuild: "26A500", rows: rows, acknowledgement: ack()) == .notPermitted)
    }

    @Test func aQualifiedMacAfterAnUpdateFallsBackToTheAcknowledgement() {
        #expect(ClosedLidPermit.decide(model: "Mac17,3", osBuild: "26B1", rows: rows, acknowledgement: nil) == .notPermitted)
        #expect(ClosedLidPermit.decide(model: "Mac17,3", osBuild: "26B1", rows: rows, acknowledgement: ack("Mac17,3", "26B1")) == .untestedAcknowledged)
    }

    @Test func onlyNotPermittedBlocksActuationAndCodesAreStable() {
        #expect(ClosedLidPermit.qualified(rowID: "r").allowsActuation && ClosedLidPermit.untestedAcknowledged.allowsActuation)
        #expect(!ClosedLidPermit.notPermitted.allowsActuation)
        #expect(ClosedLidPermit.qualified(rowID: "r").statusCode == "qualified:r")
    }

    @Test func keepAwakeAppsAreFoundFromAppsHelpersAndProcesses() {
        let found = KeepAwakeApps.detect(runningBundleIDs: ["com.if.Amphetamine", "com.apple.Safari"],
                                         runningProcesses: ["caffeinate", "zsh"],
                                         isLoaded: { $0 == "com.lidrun.app.helper" })
        #expect(found == [KeepAwakeApp(name: "Amphetamine", resetsSleepSetting: false),
                          KeepAwakeApp(name: "LidRun", resetsSleepSetting: true),
                          KeepAwakeApp(name: "caffeinate", resetsSleepSetting: false)])
        #expect(KeepAwakeApps.detect(runningBundleIDs: [], runningProcesses: [], isLoaded: { _ in false }).isEmpty)
    }

    @Test func anAppSeenThroughTwoSourcesIsListedOnceAndKeepsTheResetFlag() {
        let found = KeepAwakeApps.detect(runningBundleIDs: ["com.lidrun.app"], runningProcesses: [],
                                         isLoaded: { $0 == "com.lidrun.app.helper" })
        #expect(found == [KeepAwakeApp(name: "LidRun", resetsSleepSetting: true)])
    }
}
