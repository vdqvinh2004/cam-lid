import Foundation
import Testing
@testable import CamLidCore

@Suite("Session-bound command admission") struct CommandAdmissionTests {
    func session(_ mode: RequestedMode = .auto) throws -> ProtectionSession {
        try ProtectionSession(id: "auto-1", requestedMode: mode, armedClosedLid: false,
            startedAtMonotonic: 0, capDeadlineMonotonic: 1000)
    }
    @Test func capacityReplayIdentityExpiryAndStop() throws {
        var admissions = CommandAdmissions()
        let active = try session()
        var receipts: [CommandReceipt] = []
        for _ in 0..<20 { receipts.append(try admissions.admit(label: "job", session: active,
            uid: 501, bootID: "boot", generation: 1, backendVerified: true, safetyClear: true, now: 0)) }
        #expect(throws: IPCError.self) { try admissions.admit(label: "job", session: active,
            uid: 501, bootID: "boot", generation: 1, backendVerified: true, safetyClear: true, now: 1) }
        let first = receipts[0]
        #expect(throws: IPCError.self) { try admissions.renew(first, session: active, uid: 502,
            bootID: "boot", generation: 1, backendVerified: true, safetyClear: true, now: 10) }
        let renewed = try admissions.renew(first, session: active, uid: 501, bootID: "boot",
            generation: 1, backendVerified: true, safetyClear: true, now: 10)
        #expect(renewed.sequence == 1 && renewed.expiresAtMonotonic == 40)
        #expect(throws: IPCError.self) { try admissions.renew(first, session: active, uid: 501,
            bootID: "boot", generation: 1, backendVerified: true, safetyClear: true, now: 11) }
        #expect(throws: IPCError.self) { try admissions.renew(renewed, session: active, uid: 501,
            bootID: "other", generation: 1, backendVerified: true, safetyClear: true, now: 11) }
        #expect(throws: IPCError.self) { try admissions.renew(renewed, session: active, uid: 501,
            bootID: "boot", generation: 2, backendVerified: true, safetyClear: true, now: 11) }
        admissions.expire(now: 30)
        #expect(admissions.count == 1)
        admissions.revokeAll()
        #expect(throws: IPCError.self) { try admissions.renew(renewed, session: active, uid: 501,
            bootID: "boot", generation: 1, backendVerified: true, safetyClear: true, now: 31) }
        #expect(admissions.count == 0)
    }
    @Test func modeSafetyBackendAndFailedSpawnCleanup() throws {
        var admissions = CommandAdmissions()
        for mode in [RequestedMode.off, .timed] {
            #expect(throws: IPCError.self) { try admissions.admit(label: "job", session: session(mode),
                uid: 501, bootID: "boot", generation: 1, backendVerified: true, safetyClear: true, now: 0) }
        }
        let active = try session()
        #expect(throws: IPCError.self) { try admissions.admit(label: "job", session: active,
            uid: 501, bootID: "boot", generation: 1, backendVerified: false, safetyClear: true, now: 0) }
        #expect(throws: IPCError.self) { try admissions.admit(label: "job", session: active,
            uid: 501, bootID: "boot", generation: 1, backendVerified: true, safetyClear: false, now: 0) }
        let receipt = try admissions.admit(label: "job", session: active, uid: 501,
            bootID: "boot", generation: 1, backendVerified: true, safetyClear: true, now: 0)
        try admissions.finish(receipt, uid: 501, bootID: "boot", generation: 1, now: 1)
        #expect(admissions.count == 0)
        #expect(throws: IPCError.self) { try admissions.finish(receipt, uid: 501, bootID: "boot", generation: 1, now: 2) }
    }
}
