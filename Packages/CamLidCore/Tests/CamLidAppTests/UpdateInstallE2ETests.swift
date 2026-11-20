import CamLidCore
import Foundation
import Testing
@testable import CamLidApp

/// Opt-in end-to-end check (spec 026 SC-003), run only with CAMLID_E2E_UPDATE set. CAMLID_E2E_INSTALLED is a release-signed
/// candidate bundle, and CAMLID_E2E_HOME a QA state folder. The test downloads the real 0.2.0 release from GitHub and runs
/// the installer. The swap happens after this test process exits: the script replaces the candidate and opens the new
/// version with the QA folder as its argument.
@Suite("In-app update end to end", .enabled(if: ProcessInfo.processInfo.environment["CAMLID_E2E_UPDATE"] != nil))
@MainActor struct UpdateInstallE2ETests {
    @Test func installsTheRealReleaseOverTheCandidate() async throws {
        let env = ProcessInfo.processInfo.environment
        let installed = URL(fileURLWithPath: try #require(env["CAMLID_E2E_INSTALLED"]))
        let home = try #require(env["CAMLID_E2E_HOME"])
        let base = "https://github.com/vdqvinh2004/cam-lid/releases/download/v0.2.0/"
        let zip = "CamLid-0.2.0-macos-arm64.zip"
        let assets = UpdateAssets(zipURL: URL(string: base + zip)!, checksumURL: URL(string: base + zip + ".sha256")!)
        let installer = UpdateInstaller(home: URL(fileURLWithPath: home, isDirectory: true), installed: installed,
                                        launchArguments: ["--qa-state-directory", home])
        #expect(installer.canInstall)
        let outcome: UpdateInstallOutcome = await withCheckedContinuation { continuation in
            installer.install(assets, version: "0.2.0", current: ReleaseVersion("0.1.0")!) { continuation.resume(returning: $0) }
        }
        #expect(outcome.isLaunched)
    }
}
