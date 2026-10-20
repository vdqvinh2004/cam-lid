import Foundation
import Testing
@testable import CamLidCore

@Suite("Exact lifetime rules") struct LifetimeRuleTests {
    @Test func acceptsOnlyExactSpecificSelectors() throws {
        let executable = try LifetimeRule(
            selectorKind: .exactExecutablePath, selectorValue: "/opt/tools/worker",
            label: "Worker"
        )
        let application = try LifetimeRule(
            selectorKind: .applicationBundleID, selectorValue: "com.example.worker",
            label: "Example worker"
        )
        try executable.validate()
        try application.validate()
        try LifetimeRule.validateCollection([executable, application])
    }

    @Test func rejectsAmbiguousPathsBundlesAndLabels() {
        for path in ["relative/tool", "/", "/tmp/../tool", "/System/Library/launchd", "/Applications/*"] {
            #expect(throws: ValidationError.self) {
                try LifetimeRule(selectorKind: .exactExecutablePath, selectorValue: path, label: "Worker")
            }
        }
        for bundleID in ["worker", "com.apple.Finder", "com.example.*"] {
            #expect(throws: ValidationError.self) {
                try LifetimeRule(selectorKind: .applicationBundleID, selectorValue: bundleID, label: "Worker")
            }
        }
        #expect(throws: ValidationError.self) {
            try LifetimeRule(selectorKind: .applicationBundleID, selectorValue: "com.example.worker", label: "  ")
        }
        #expect(throws: ValidationError.self) {
            try LifetimeRule(selectorKind: .applicationBundleID, selectorValue: "com.example.worker", label: String(repeating: "x", count: 81))
        }
    }

    @Test func rejectsDuplicateSelectorsAndOverCapacity() throws {
        let first = try LifetimeRule(selectorKind: .applicationBundleID,
            selectorValue: "com.example.worker", label: "Worker")
        let duplicate = try LifetimeRule(selectorKind: .applicationBundleID,
            selectorValue: "com.example.worker", label: "Worker again")
        #expect(throws: ValidationError.self) { try LifetimeRule.validateCollection([first, duplicate]) }
        let tooMany = try (0..<21).map { index in
            try LifetimeRule(selectorKind: .applicationBundleID,
                selectorValue: "com.example.worker\(index)", label: "Worker \(index)")
        }
        #expect(throws: ValidationError.self) { try LifetimeRule.validateCollection(tooMany) }
    }

    @Test func configurationMigratesPatchesAndPersistsRules() throws {
        let rule = try LifetimeRule(selectorKind: .applicationBundleID,
            selectorValue: "com.example.worker", label: "Worker")
        let config = try Configuration(lifetimeRules: [rule])
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Configuration.self, from: data).lifetimeRules == [rule])
        #expect(try Configuration.migrate(from: [:]).lifetimeRules == nil)

        var patch = ConfigPatch()
        patch.lifetimeRules = []
        #expect(try config.applying(patch).lifetimeRules == [])
        patch.lifetimeRules = [rule, rule]
        #expect(throws: ConfigError.self) { try config.applying(patch) }

        let rawRules = try JSONSerialization.jsonObject(with: JSONEncoder().encode([rule]))
        let jsonPatch = try ConfigPatch(jsonDictionary: ["lifetimeRules": rawRules])
        #expect(jsonPatch.lifetimeRules == [rule])
    }

    @Test func exactPathAndBundleMatchesRequireSameUserIdentity() throws {
        let path = try LifetimeRule(selectorKind: .exactExecutablePath,
            selectorValue: "/opt/tools/worker", label: "Worker")
        let app = try LifetimeRule(selectorKind: .applicationBundleID,
            selectorValue: "org.example.worker", label: "App")
        let snapshot = try lifetimeSnapshot(100, [
            process(pid: 12, start: 1, uid: 501, path: path.selectorValue),
            process(pid: 13, start: 1, uid: 501, path: "/Applications/Worker.app/Contents/MacOS/Worker",
                bundleID: app.selectorValue),
            process(pid: 12, start: 1, uid: 502, path: path.selectorValue),
        ])
        var tracker = LifetimeRuleTracker()
        let result = try tracker.update(rules: [path, app], snapshot: snapshot, now: 100,
            sessionID: "session", exactTaskEpoch: nil, waitRetentionSeconds: 10)
        #expect(result.holdReason == "lifetimeRuleActive")
        #expect(result.status(for: path.id)?.presence == .present)
        #expect(result.status(for: app.id)?.presence == .present)
        #expect(result.status(for: path.id)?.processCount == 1)
    }

    @Test func absenceNeedsTwoCompleteObservationsFiveSecondsApartAndStillSuppressesCompletion() throws {
        let rule = try LifetimeRule(selectorKind: .exactExecutablePath,
            selectorValue: "/opt/tools/worker", label: "Worker")
        let match = try process(pid: 21, start: 4, uid: 501, path: rule.selectorValue)
        var tracker = LifetimeRuleTracker()
        _ = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(100, [match]), now: 100,
            sessionID: "session", exactTaskEpoch: "run-a", waitRetentionSeconds: 10)

        let firstAbsent = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(102, []), now: 102,
            sessionID: "session", exactTaskEpoch: "run-a", waitRetentionSeconds: 10)
        #expect(firstAbsent.status(for: rule.id)?.presence == .unknown)
        #expect(firstAbsent.holdReason == "lifetimeRuleUnknown")
        #expect(firstAbsent.suppressesAutoCompletion)

        let confirmed = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(107, []), now: 107,
            sessionID: "session", exactTaskEpoch: "run-a", waitRetentionSeconds: 10)
        #expect(confirmed.status(for: rule.id)?.presence == .absent)
        #expect(confirmed.holdReason == nil)
        #expect(confirmed.suppressesAutoCompletion)
    }

    @Test func incompleteOrStaleScanBecomesBoundedUnknown() throws {
        let rule = try LifetimeRule(selectorKind: .exactExecutablePath,
            selectorValue: "/opt/tools/worker", label: "Worker")
        let match = try process(pid: 22, start: 4, uid: 501, path: rule.selectorValue)
        var tracker = LifetimeRuleTracker()
        _ = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(100, [match]), now: 100,
            sessionID: "session", exactTaskEpoch: nil, waitRetentionSeconds: 5)

        let incomplete = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(102, [], complete: false), now: 102,
            sessionID: "session", exactTaskEpoch: nil, waitRetentionSeconds: 5)
        #expect(incomplete.status(for: rule.id)?.presence == .unknown)
        #expect(incomplete.holdReason == "lifetimeRuleUnknown")

        let stale = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(102, [], complete: false), now: 106,
            sessionID: "session", exactTaskEpoch: nil, waitRetentionSeconds: 5)
        #expect(stale.status(for: rule.id)?.presence == .unknown)
        #expect(stale.holdReason == nil)
        #expect(stale.suppressesAutoCompletion)
    }

    @Test func pathChangeAndPIDReuseDoNotInheritAnOldMatch() throws {
        let rule = try LifetimeRule(selectorKind: .exactExecutablePath,
            selectorValue: "/opt/tools/worker", label: "Worker")
        let original = try process(pid: 23, start: 4, uid: 501, path: rule.selectorValue)
        var tracker = LifetimeRuleTracker()
        _ = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(100, [original]), now: 100,
            sessionID: "session", exactTaskEpoch: nil, waitRetentionSeconds: 5)

        let changedPath = try process(pid: 23, start: 4, uid: 501, path: "/opt/tools/replaced")
        let changed = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(102, [changedPath]), now: 102,
            sessionID: "session", exactTaskEpoch: nil, waitRetentionSeconds: 5)
        #expect(changed.status(for: rule.id)?.presence == .unknown)
        #expect(changed.status(for: rule.id)?.reasonCode == "selectorChanged")

        let reusedPID = try process(pid: 23, start: 5, uid: 501, path: "/opt/tools/replaced")
        let reused = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(103, [reusedPID]), now: 103,
            sessionID: "session", exactTaskEpoch: nil, waitRetentionSeconds: 5)
        #expect(reused.status(for: rule.id)?.presence == .unknown)
    }

    @Test func newExactTaskEpochClearsPriorLifetimeCompletionSuppression() throws {
        let rule = try LifetimeRule(selectorKind: .exactExecutablePath,
            selectorValue: "/opt/tools/worker", label: "Worker")
        var tracker = LifetimeRuleTracker()
        let match = try process(pid: 24, start: 4, uid: 501, path: rule.selectorValue)
        _ = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(100, [match]), now: 100,
            sessionID: "session", exactTaskEpoch: "run-a", waitRetentionSeconds: 0)
        _ = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(101, []), now: 101,
            sessionID: "session", exactTaskEpoch: "run-b", waitRetentionSeconds: 0)
        let absent = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(106, []), now: 106,
            sessionID: "session", exactTaskEpoch: "run-b", waitRetentionSeconds: 0)
        #expect(absent.status(for: rule.id)?.presence == .absent)
        #expect(!absent.suppressesAutoCompletion)
    }

    @Test func stopDoesNotRearmAndNextExplicitSessionResetsPriorEpoch() throws {
        let rule = try LifetimeRule(selectorKind: .exactExecutablePath,
            selectorValue: "/opt/tools/worker", label: "Worker")
        var tracker = LifetimeRuleTracker()
        let observed = try process(pid: 25, start: 4, uid: 501, path: rule.selectorValue)
        _ = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(100, [observed]), now: 100,
            sessionID: "session-a", exactTaskEpoch: "run-a", waitRetentionSeconds: 10)
        _ = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(102, []), now: 102,
            sessionID: nil, exactTaskEpoch: "run-a", waitRetentionSeconds: 10)
        let stopped = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(107, []), now: 107,
            sessionID: nil, exactTaskEpoch: "run-a", waitRetentionSeconds: 10)
        #expect(stopped.status(for: rule.id)?.presence == .absent)
        #expect(stopped.suppressesAutoCompletion)

        let restarted = try tracker.update(rules: [rule], snapshot: lifetimeSnapshot(112, []), now: 112,
            sessionID: "session-b", exactTaskEpoch: "run-a", waitRetentionSeconds: 10)
        #expect(restarted.status(for: rule.id)?.presence == .absent)
        #expect(!restarted.suppressesAutoCompletion)
    }

    private func lifetimeSnapshot(
        _ time: Double, _ processes: [LifetimeObservedProcess], complete: Bool = true
    ) throws -> LifetimeProcessSnapshot {
        try LifetimeProcessSnapshot(userID: 501, observedAtMonotonic: time,
            processes: processes, complete: complete)
    }

    private func process(
        pid: Int32, start: Double, uid: UInt32, path: String, bundleID: String? = nil,
        bundleIdentityKnown: Bool = true
    ) throws -> LifetimeObservedProcess {
        try LifetimeObservedProcess(
            identity: LifetimeProcessIdentity(pid: pid, startTime: start, userID: uid),
            executablePath: path, applicationBundleID: bundleID,
            bundleIdentityKnown: bundleIdentityKnown)
    }
}
