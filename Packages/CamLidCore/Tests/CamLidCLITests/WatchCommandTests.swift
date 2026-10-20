import Foundation
import Testing
@testable import CamLidCLI
@testable import CamLidCore

private struct WatchCommandChannel: IPCChannel {
    let configReply: Data
    let setReply: Data
    let inspectSet: @Sendable (CLIOptions) throws -> Void

    func send(command: AllowlistedCommand, payload: Data) throws -> Data {
        switch command {
        case .configGet:
            #expect(payload.isEmpty)
            return configReply
        case .configSet:
            try inspectSet(try JSONDecoder().decode(CLIOptions.self, from: payload))
            return setReply
        default:
            throw IPCError.policyDenied("unexpectedCommand")
        }
    }
}

@Suite("Lifetime rule CLI") struct WatchCommandTests {
    @Test func addWritesValidatedRuleWithRevisionAndReturnsItsID() throws {
        let (root, executable) = try fakeExecutable()
        defer { try? FileManager.default.removeItem(at: root) }
        let channel = try channel(rules: [], revision: 7) { options in
            #expect(options.flags["expectedRevision"] == "7")
            let patch = try #require(options.flags["patchJSON"])
            let object = try #require(JSONSerialization.jsonObject(with: Data(patch.utf8)) as? [String: Any])
            let data = try JSONSerialization.data(withJSONObject: try #require(object["lifetimeRules"]))
            let rules = try JSONDecoder().decode([LifetimeRule].self, from: data)
            #expect(rules.count == 1)
            #expect(rules[0].selectorKind == .exactExecutablePath)
            #expect(rules[0].selectorValue == executable.path)
            #expect(rules[0].label == "worker")
        }

        let result = Commands.runWithRealIO(
            argv: ["watch", "add", "--executable", executable.path], channel: channel)
        let output = try json(result)
        #expect(result.exitCode == 0)
        #expect(output["command"] as? String == "watchAdd")
        #expect(output["revision"] as? Int == 8)
        #expect(UUID(uuidString: try #require(output["ruleID"] as? String)) != nil)
    }

    @Test func listReturnsPersistedRulesAndRevision() throws {
        let rule = try LifetimeRule(selectorKind: .applicationBundleID,
            selectorValue: "com.example.worker", label: "Worker")
        let channel = try channel(rules: [rule], revision: 11) { _ in Issue.record("list must not write") }
        let result = Commands.runWithRealIO(argv: ["watch", "list", "--json"], channel: channel)
        let output = try json(result)
        #expect(result.exitCode == 0)
        #expect(output["command"] as? String == "watchList")
        #expect(output["revision"] as? Int == 11)
        let encodedRules = try #require(output["rules"])
        let data = try JSONSerialization.data(withJSONObject: encodedRules)
        #expect(try JSONDecoder().decode([LifetimeRule].self, from: data) == [rule])
    }

    @Test func invalidAndDuplicateSelectorsNeverWrite() throws {
        let (root, executable) = try fakeExecutable()
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = try LifetimeRule(selectorKind: .exactExecutablePath,
            selectorValue: executable.path, label: "Worker")
        let channel = try channel(rules: [existing], revision: 3) { _ in Issue.record("invalid rule must not write") }

        let generic = Commands.runWithRealIO(
            argv: ["watch", "add", "--executable", "/usr/bin/worker"], channel: channel)
        #expect(generic.exitCode == 2)
        #expect(try json(generic)["accepted"] as? Bool == false)

        let duplicate = Commands.runWithRealIO(
            argv: ["watch", "add", "--executable", executable.path], channel: channel)
        #expect(duplicate.exitCode == 2)
    }

    @Test func bundleIDMustResolveToAnInstalledApplication() throws {
        let channel = try channel(rules: [], revision: 1) { _ in Issue.record("uninstalled app must not write") }
        let missingID = "com.example.camlidmissing." + UUID().uuidString.lowercased()
        let result = Commands.runWithRealIO(
            argv: ["watch", "add", "--bundle-id", missingID], channel: channel)
        #expect(result.exitCode == 2)
        #expect(try json(result)["reason"] as? String == "applicationNotInstalled")
    }

    @Test func removeUsesRevisionAndPropagatesConflict() throws {
        let rule = try LifetimeRule(selectorKind: .applicationBundleID,
            selectorValue: "com.example.worker", label: "Worker")
        let conflict = try JSONEncoder().encode(CLIResult(
            json: "{\"accepted\":false,\"reason\":\"revisionConflict\",\"currentRevision\":9}", exitCode: 2))
        let channel = try channel(rules: [rule], revision: 8, setReply: conflict) { options in
            #expect(options.flags["expectedRevision"] == "8")
            let patch = try #require(options.flags["patchJSON"])
            let object = try #require(JSONSerialization.jsonObject(with: Data(patch.utf8)) as? [String: Any])
            #expect((object["lifetimeRules"] as? [Any])?.isEmpty == true)
        }

        let result = Commands.runWithRealIO(argv: ["watch", "remove", rule.id.uuidString], channel: channel)
        let output = try json(result)
        #expect(result.exitCode == 2)
        #expect(output["reason"] as? String == "revisionConflict")
    }
}

private func channel(
    rules: [LifetimeRule], revision: Int,
    setReply: Data? = nil,
    inspectSet: @escaping @Sendable (CLIOptions) throws -> Void
) throws -> WatchCommandChannel {
    let config = try Configuration(lifetimeRules: rules)
    var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
    value["command"] = "configGet"
    value["revision"] = revision
    let data = try JSONSerialization.data(withJSONObject: value)
    let getReply = try JSONEncoder().encode(CLIResult(json: String(decoding: data, as: UTF8.self), exitCode: 0))
    let response = try setReply ?? JSONEncoder().encode(CLIResult(
        json: "{\"accepted\":true,\"revision\":\(revision + 1)}", exitCode: 0))
    return WatchCommandChannel(configReply: getReply, setReply: response, inspectSet: inspectSet)
}

private func fakeExecutable() throws -> (URL, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("camlid-watch-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let executable = root.appendingPathComponent("worker")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    return (root, executable)
}

private func json(_ result: CLIResult) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])
}
