import Foundation
import Testing
import CamLidCore
@testable import CamLidCLI

/// The contract an agent relies on: a refusal names a reason with its exit code, retry advice and next step; durations
/// carry units; `start` reads its flags the same way on the command line and in the app; and the catalog is the one list of
/// what each command accepts. Behaviour in the app is tested in AgentOperationsTests.
@Suite("Agent CLI contract")
struct AgentCLITests {
    private func object(_ result: CLIResult) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])
    }

    private func refusalReason(_ parsed: StartParse) throws -> String? {
        guard case .refused(let result) = parsed else { return nil }
        return try object(result)["reason"] as? String
    }

    private func accepted(_ parsed: StartParse) -> StartRequest? {
        guard case .accepted(let request) = parsed else { return nil }
        return request
    }

    @Test func everyRefusalACommandListsIsExplained() {
        for reason in Set(CommandCatalog.all.flatMap(\.refusals)).sorted() {
            #expect(CLIReasons.table[reason] != nil, "No hint for the refusal \(reason)")
        }
    }

    @Test func aRefusalCarriesItsExitCodeRetryAdviceAndHint() throws {
        let result = CLIReply.refused("start", reason: "batteryEntryLow")
        let fields = try object(result)
        #expect(result.exitCode == 3)
        #expect(fields["accepted"] as? Bool == false)
        #expect(fields["reason"] as? String == "batteryEntryLow")
        #expect(fields["retryable"] as? Bool == true)
        #expect((fields["hint"] as? String)?.isEmpty == false)
        #expect(fields["schemaVersion"] as? Int == 1)
        #expect(fields["command"] as? String == "start")
    }

    @Test func durationsNeedAUnitAndOnlyMinutesAndHoursAreRead() {
        #expect(DurationText.parse("45m", allowInfinite: false) == .success(.minutes(45)))
        #expect(DurationText.parse("2h", allowInfinite: false) == .success(.minutes(120)))
        #expect(DurationText.parse("infinite", allowInfinite: true) == .success(.infinite))
        #expect(DurationText.parse("infinite", allowInfinite: false) == .failure(.invalid))
        #expect(DurationText.parse("60", allowInfinite: true) == .failure(.unitRequired))
        #expect(DurationText.parse("45s", allowInfinite: true) == .failure(.invalid))
        #expect(DurationText.parse("", allowInfinite: true) == .failure(.invalid))
    }

    @Test func startReadsManualAsTimedAndRefusesAmbiguousDurations() throws {
        let manual = accepted(StartRequest.parse(CLIOptions(flags: ["mode": "manual", "duration": "45m"])))
        #expect(manual?.mode == .timed)
        #expect(manual?.minutes == 45)
        #expect(accepted(StartRequest.parse(CLIOptions()))?.mode == .auto)
        #expect(accepted(StartRequest.parse(CLIOptions(flags: ["mode": "timed", "duration": "infinite"])))?.minutes == 0)
        #expect(try refusalReason(StartRequest.parse(CLIOptions(flags: ["mode": "timed"]))) == "durationRequired")
        #expect(try refusalReason(StartRequest.parse(CLIOptions(flags: ["mode": "auto", "duration": "45m"]))) == "durationNotApplicable")
        #expect(try refusalReason(StartRequest.parse(CLIOptions(flags: ["mode": "timed", "duration": "60"]))) == "durationUnitRequired")
        #expect(try refusalReason(StartRequest.parse(CLIOptions(flags: ["mode": "timed", "duration": "0m"]))) == "invalidDuration")
        #expect(try refusalReason(StartRequest.parse(CLIOptions(flags: ["mode": "timed", "duration": "2m"]))) == "invalidDuration")
        #expect(try refusalReason(StartRequest.parse(CLIOptions(flags: ["mode": "off"]))) == "invalidMode")
    }

    @Test func startReadsItsSwitchesAsAsked() {
        let request = accepted(StartRequest.parse(CLIOptions(flags: [
            "mode": "timed", "duration": "45m", "replace": "true", "save-mode": "true",
        ])))
        #expect(request?.replace == true)
        #expect(request?.saveMode == true)
        #expect(request?.closedLid == false)
    }

    @Test func theCatalogRefusesUnknownFlagsAndMissingConfirmationBeforeAnythingIsSent() throws {
        let unknown = try #require(CommandCatalog.check("start", CLIOptions(flags: ["bogus": "1"])))
        #expect(unknown.exitCode == 2)
        #expect(try object(unknown)["reason"] as? String == "unknownOption")
        let unconfirmed = try #require(CommandCatalog.check("logs delete", CLIOptions(flags: ["all": "true"])))
        #expect(unconfirmed.exitCode == 2)
        #expect(try object(unconfirmed)["reason"] as? String == "confirmationRequired")
        #expect(CommandCatalog.check("start", CLIOptions(flags: ["mode": "auto"])) == nil)
    }

    @Test func multiWordCommandsParseToOneNameAndASwitchTakesNoValue() {
        let (name, options) = Commands.parse(argv: ["session", "duration", "45m", "--expectedRevision", "7"])
        #expect(name == "session duration")
        #expect(options.positionals == ["45m"])
        #expect(options.flags["expectedRevision"] == "7")
        let (startName, startOptions) = Commands.parse(argv: ["start", "--replace", "--mode", "timed"])
        #expect(startName == "start")
        #expect(startOptions.flags["replace"] == "true")
        #expect(startOptions.flags["mode"] == "timed")
    }

    @Test func commandsListsEveryCommandWithItsExitCodes() throws {
        let listing = CommandCatalog.listing()
        #expect(listing.exitCode == 0)
        let fields = try object(listing)
        #expect(fields["schemaVersion"] as? Int == 1)
        #expect(fields["exitCodes"] != nil)
        let commands = try #require(fields["commands"] as? [[String: Any]])
        #expect(commands.contains { $0["name"] as? String == "start" })
        #expect(CommandCatalog.settingKeys.count == 19)
    }

    @Test func everyAppOperationIsCatalogued() {
        for name in CommandCatalog.operated {
            #expect(CommandCatalog.spec(name) != nil, "\(name) is answered by the app but not catalogued")
        }
    }
}
