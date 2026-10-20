import Foundation
import Testing
@testable import CamLidCore

@Suite("Awake automation IPC contracts") struct AutomationIPCContractTests {
    @Test func operationsStayAllowlistedAndPayloadsStayNarrow() throws {
        for name in ["admitCommand", "renewCommand", "finishCommand", "sleep"] {
            #expect(AllowlistedCommand(rawValue: name) != nil)
        }

        let admission = AdmitCommandRequest(label: "swift")
        try admission.validate()
        let admissionJSON = String(decoding: try JSONEncoder().encode(admission), as: UTF8.self)
        #expect(admissionJSON.contains("schemaVersion"))
        #expect(!admissionJSON.contains("argv"))
        #expect(!admissionJSON.contains("stdout"))

        let receipt = CommandReceipt(id: UUID(), sequence: 2, expiresAtMonotonic: 40)
        let renewal = RenewCommandRequest(receipt: receipt)
        try renewal.validate()
        #expect(try JSONDecoder().decode(RenewCommandRequest.self,
            from: JSONEncoder().encode(renewal)) == renewal)
        try FinishCommandRequest(receipt: receipt).validate()

        let dryRun = SleepCommandRequest(dryRun: true)
        try dryRun.validate()
        #expect(String(decoding: try JSONEncoder().encode(dryRun), as: UTF8.self).contains("dryRun"))
    }

    @Test func invalidPayloadsFailClosed() {
        #expect(throws: IPCError.self) { try AdmitCommandRequest(label: "  ").validate() }
        #expect(throws: IPCError.self) { try AdmitCommandRequest(label: String(repeating: "x", count: 81)).validate() }
        #expect(throws: IPCError.self) { try AdmitCommandRequest(label: "job\nname").validate() }
        #expect(throws: IPCError.self) { try AdmitCommandRequest(label: "job", schemaVersion: 2).validate() }
        #expect(throws: IPCError.self) {
            try RenewCommandRequest(receipt: CommandReceipt(id: UUID(), sequence: 0,
                expiresAtMonotonic: .infinity)).validate()
        }
        #expect(throws: IPCError.self) { try SleepCommandRequest(dryRun: false, schemaVersion: 0).validate() }
    }
}
