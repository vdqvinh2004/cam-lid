import Foundation
import Testing
import CamLidCore
@testable import CamLidApp

struct NativeProcessListTests {
    @Test func snapshotContainsOnlyBoundedSameUserAllowedNames() {
        let rows = NativeProcessList().snapshot()
        #expect(rows.count <= 20)
        for row in rows {
            #expect(NativeProcessList.executableNames.contains(row.executableName))
            #expect(row.identity.pid > 0 && row.identity.startTime != nil)
            #expect(!row.executableName.contains("/") && !row.executableName.contains(" "))
        }
    }
    @Test func lifetimeSnapshotIsBoundedAndContainsExactSameUserMetadataOnly() throws {
        let snapshot = try #require(NativeProcessList().lifetimeSnapshot())
        #expect(snapshot.processes.count <= LifetimeProcessSnapshot.maximumProcesses)
        for process in snapshot.processes {
            #expect(process.identity.userID == snapshot.userID)
            if let path = process.executablePath { #expect(path.hasPrefix("/")) }
        }
    }
    // Explicit opt-in: version-only runs create no paid requests or provider hooks.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CAMLID_INSTALLED_PROVIDER_QA"] == "1"))
    func installedProviderProcessLifetimes() throws {
        for provider in ["codex", "opencode"] {
            let path = try #require(ProcessInfo.processInfo.environment["CAMLID_QA_" + provider.uppercased()])
            for cycle in 1...20 {
                let child = Process()
                child.executableURL = URL(fileURLWithPath: path)
                child.arguments = ["--version"]
                child.standardOutput = FileHandle.nullDevice
                child.standardError = FileHandle.nullDevice
                try child.run()
                let deadline = Date().addingTimeInterval(10)
                var record: ProcessRecord?
                while child.isRunning && Date() < deadline && record == nil {
                    record = NativeProcessList().snapshot().first { $0.identity.pid == child.processIdentifier }
                }
                #expect(record?.executableName == provider, "\(provider) cycle \(cycle): exact child observed")
                while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
                if child.isRunning { child.terminate(); Issue.record("Version process exceeded deadline"); return }
                child.waitUntilExit()
                #expect(child.terminationStatus == 0)
                #expect(!NativeProcessList().snapshot().contains { $0.identity == record?.identity })
                let badge = AgentBadgeState(provider: provider, enabled: true, tasks: [], processCount: record == nil ? 0 : 1)
                #expect(badge.workingCount == 0 && badge.observedState == "Unknown")
            }
        }
    }
    @Test func discoveryPresenceDoesNotCreateActivityOrConnection() {
        let badge = AgentBadgeState(provider: "codex", enabled: true, tasks: [], processCount: 1)
        #expect(badge.observedState == "Unknown" && badge.readiness == "disconnected")
        #expect(badge.detail == "Process found · task state unknown" && badge.workingCount == 0)
    }
}
