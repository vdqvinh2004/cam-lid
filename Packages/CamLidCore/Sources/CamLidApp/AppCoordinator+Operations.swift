import AppKit
import CamLidCLI
import CamLidCore
import CamLidPowerWire
import Foundation

/// The app-side operations of `camlid`, named by the CLI catalog. Each one acts on state the app owns, through the same
/// functions the windows use, and answers with the CLI's JSON. Refusals name a reason, and `CLIReasons` gives the hint.
enum ControlKeys {
    /// The salt that makes session pseudonyms stable on this Mac, so `logs list` and `logs delete` agree.
    static let activitySalt = "CamLidCLIActivitySalt"
}

/// The CLI's names for the music sources, which are the same on every Mac.
enum MusicIDs {
    static func id(_ source: MusicSource) -> String {
        switch source {
        case .browser: "chromium"
        case .spotify: "spotify"
        case .appleMusic: "apple-music"
        case .safari: "safari"
        }
    }

    static func source(_ id: String) -> MusicSource? {
        MusicSource.allCases.first { Self.id($0) == id }
    }
}

extension AppCoordinator {
    /// The `operate` control command: one catalogued operation. The name must be in the catalog, flags are checked against
    /// it, and a mutating operation is refused while CamLid quits.
    func operate(_ payload: Data) async -> CLIResult {
        guard let request = try? JSONDecoder().decode(OperateRequest.self, from: payload),
              let spec = CommandCatalog.spec(request.name) else {
            return CLIReply.refused("operate", reason: "unknownCommand")
        }
        if spec.mutates, terminationFlowActive { return CLIReply.refused(spec.name, reason: "applicationTerminating") }
        if let refusal = CommandCatalog.check(spec.name, request.options) { return refusal }
        let options = request.options
        switch spec.name {
        case "session duration": return sessionDurationOperation(options)
        case "session sleep-delay": return sessionSleepDelayOperation(options)
        case "logs list": return await logsListOperation(options)
        case "logs delete": return await logsDeleteOperation(options)
        case "music list": return CLIReply.read("musicList", ["sources": MusicSource.allCases.map(musicObject)])
        case "music set": return musicSetOperation(options)
        case "audio-hold": return audioHoldOperation(options)
        case "language get": return CLIReply.read("languageGet", languageObject())
        case "language set": return languageSetOperation(options)
        case "skill status": return CLIReply.read("skillStatus", skillObject())
        case "skill install": return skillInstallOperation(options)
        case "skill remove": return skillRemoveOperation()
        case "update status": return CLIReply.read("updateStatus", updateObject())
        case "update check": return updateCheckOperation()
        case "update install": return updateInstallOperation(options)
        case "update auto": return updateAutoOperation(options)
        case "agents enable", "agents disable": return await agentsOperation(spec.name, options)
        case "closed-lid acknowledge-untested": return untestedOperation(options)
        case "notifications request": return notificationsRequestOperation()
        case "welcome status": return CLIReply.read("welcomeStatus", ["done": preferences.bool(forKey: Self.onboardedKey)])
        case "welcome complete": return welcomeCompleteOperation()
        case "open": return openOperation(options)
        case "login apply": return loginOperation()
        case "version": return versionOperation()
        default: return CLIReply.refused(spec.name, reason: "unknownCommand")
        }
    }

    // MARK: - Session

    private func sessionDurationOperation(_ options: CLIOptions) -> CLIResult {
        let command = "sessionDuration"
        let minutes: Int
        switch DurationText.parse(options.positionals.first ?? "", allowInfinite: true) {
        case .failure(.unitRequired): return CLIReply.refused(command, reason: "durationUnitRequired")
        case .failure(.invalid): return CLIReply.refused(command, reason: "invalidDuration")
        case .success(.infinite): minutes = 0
        case .success(.minutes(let value)):
            guard TimerRules.minutes.contains(value) else { return CLIReply.refused(command, reason: "invalidDuration") }
            minutes = value
        }
        guard let expected = expectedRevisionOption(options) else { return CLIReply.refused(command, reason: "invalidRevision") }
        switch adjustTimer(minutes, expectedRevision: expected) {
        case .failure(let failure):
            return CLIReply.refused(command, reason: failure.rawValue)
        case .success(let adjust):
            return CLIReply.done(command, changed: adjust.changed,
                ["durationSeconds": adjust.minutes * 60, "capApplied": adjust.capApplied, "revision": revision])
        }
    }

    private func sessionSleepDelayOperation(_ options: CLIOptions) -> CLIResult {
        let command = "sessionSleepDelay"
        let minutes: Int
        switch DurationText.parse(options.positionals.first ?? "", allowInfinite: false) {
        case .failure(.unitRequired): return CLIReply.refused(command, reason: "durationUnitRequired")
        case .failure(.invalid), .success(.infinite): return CLIReply.refused(command, reason: "invalidDuration")
        case .success(.minutes(let value)):
            guard TimerRules.sleepDelay.contains(value) else { return CLIReply.refused(command, reason: "invalidDuration") }
            minutes = value
        }
        guard let expected = expectedRevisionOption(options) else { return CLIReply.refused(command, reason: "invalidRevision") }
        switch adjustSleepDelay(minutes, expectedRevision: expected) {
        case .failure(let failure):
            return CLIReply.refused(command, reason: failure.rawValue)
        case .success(let adjust):
            return CLIReply.done(command, changed: adjust.changed, ["sleepDelayMinutes": adjust.minutes, "revision": revision])
        }
    }

    /// The revision a write is checked against: the one the caller passed, or the current one when it passed none.
    private func expectedRevisionOption(_ options: CLIOptions) -> Int? {
        guard let raw = options.flags["expectedRevision"] else { return revision }
        guard let value = Int(raw), value >= 1 else { return nil }
        return value
    }

    // MARK: - Activity history

    private func logsListOperation(_ options: CLIOptions) async -> CLIResult {
        let command = "logsList"
        let limit: Int
        if let raw = options.flags["limit"] {
            guard let value = Int(raw), (1...200).contains(value) else { return CLIReply.refused(command, reason: "invalidFilter", detail: raw) }
            limit = value
        } else {
            limit = 50
        }
        var category: ActivityCategory?
        if let raw = options.flags["category"] {
            guard let value = ActivityCategory(rawValue: raw) else { return CLIReply.refused(command, reason: "invalidFilter", detail: raw) }
            category = value
        }
        let filter = ActivityFilter(query: options.flags["query"] ?? "", sessionPseudonym: nil,
                                    reasonCode: options.flags["reason"], category: category)
        let includeRoutine = options.flags["include-routine"] != nil
        guard let stored = await history.transitions() else { return CLIReply.refused(command, reason: "storageUnavailable") }
        // Newest first. Routine sensor updates are hidden unless asked for, as the Activity window hides them. The search and
        // the filters are the window's own, so the command finds what the window finds.
        var records = stored.reversed().filter(filter.matches)
        let hidden = records.filter(ActivityPresentation.isRoutineSensorUpdate).count
        if !includeRoutine { records.removeAll(where: ActivityPresentation.isRoutineSensorUpdate) }
        if let cursor = options.flags["cursor"] {
            guard let index = records.firstIndex(where: { $0.id.uuidString == cursor }) else {
                return CLIReply.refused(command, reason: "invalidCursor")
            }
            records = Array(records[(index + 1)...])
        }
        let page = Array(records.prefix(limit))
        let more = records.count > page.count
        let salt = activitySalt
        let items = page.map { record in redactedObject(ActivityStore.redacted(record, salt: salt)) }
        guard !items.contains(where: { $0.isEmpty }) else { return CLIReply.refused(command, reason: "invalidAppReply") }
        return CLIReply.read(command, [
            "records": items,
            "nextCursor": more ? jsonString(page.last?.id.uuidString) : NSNull(),
            "hiddenRoutineCount": hidden,
        ])
    }

    private func logsDeleteOperation(_ options: CLIOptions) async -> CLIResult {
        let command = "logsDelete"
        let pseudonym = options.flags["session"]
        let all = options.flags["all"] != nil
        guard (pseudonym != nil) != all else {
            return CLIReply.refused(command, reason: "invalidOptions", detail: "session or all",
                hint: "Pass exactly one of --session <sessionPseudonym> or --all, with --confirm.")
        }
        var target: String?
        if let pseudonym {
            guard let stored = await history.transitions() else { return CLIReply.refused(command, reason: "storageUnavailable") }
            let salt = activitySalt
            guard let raw = stored.compactMap(\.sessionID).first(where: { ActivityStore.pseudonym(sessionID: $0, salt: salt) == pseudonym }) else {
                return CLIReply.refused(command, reason: "unknownSession", detail: pseudonym)
            }
            target = raw
        }
        guard let receipt = await history.delete(sessionID: target) else {
            return CLIReply.refused(command, reason: "storageUnavailable",
                hint: "The deletion is not confirmed. Read `camlid logs list` before you try again.")
        }
        return CLIReply.done(command, changed: receipt.removedCount > 0, ["receipt": receiptObject(receipt)])
    }

    /// A session's pseudonym for this Mac, from the stored salt.
    var activitySalt: String {
        if let salt = preferences.string(forKey: ControlKeys.activitySalt), !salt.isEmpty { return salt }
        let salt = UUID().uuidString
        preferences.set(salt, forKey: ControlKeys.activitySalt)
        return salt
    }

    private func receiptObject(_ receipt: DeletionReceipt) -> [String: Any] {
        let pseudonym = receipt.sessionID.map { ActivityStore.pseudonym(sessionID: $0, salt: activitySalt) }
        return [
            "id": receipt.id.uuidString,
            "scope": receipt.scope.rawValue,
            "sessionPseudonym": jsonString(pseudonym),
            "removedCount": receipt.removedCount,
            "deletedAt": ISO8601DateFormatter().string(from: receipt.deletedAt),
        ]
    }

    // MARK: - Agents, music and audio

    private func agentsOperation(_ name: String, _ options: CLIOptions) async -> CLIResult {
        let command = name == "agents enable" ? "agentsEnable" : "agentsDisable"
        let all = options.flags["all"] != nil
        let provider = options.positionals.first
        guard all != (provider != nil) else {
            return CLIReply.refused(command, reason: "invalidOptions", detail: "provider or all",
                hint: "Name one provider, or pass --all.")
        }
        let providers = AgentBadgeState.providers
        if let provider, !providers.contains(provider) {
            return CLIReply.refused(command, reason: "unknownProvider", detail: provider)
        }
        let targets = all ? providers : [provider ?? ""]
        let current = config.adapterEnrollment
        var updated = current
        if command == "agentsEnable" {
            for id in targets where !updated.contains(id) { updated.append(id) }
        } else {
            updated.removeAll { targets.contains($0) }
        }
        guard updated != current else { return CLIReply.done(command, changed: false, ["enrolled": current]) }
        var patch = ConfigPatch()
        patch.adapterEnrollment = updated
        switch await applySettingsPatchAsync(patch, expectedRevision: revision) {
        case .saved:
            return CLIReply.done(command, changed: true, ["enrolled": updated, "revision": revision])
        case .conflict:
            return CLIReply.refused(command, reason: "revisionConflict")
        case .failed(let message):
            return CLIReply.refused(command, reason: "storageUnavailable", detail: message)
        case .unconfirmed:
            return CLIReply.refused(command, reason: "commitUnconfirmed")
        }
    }

    private func musicSetOperation(_ options: CLIOptions) -> CLIResult {
        let command = "musicSet"
        guard options.positionals.count == 2 else { return CLIReply.refused(command, reason: "invalidOptions") }
        guard let source = MusicIDs.source(options.positionals[0]) else {
            return CLIReply.refused(command, reason: "unknownSource", detail: options.positionals[0])
        }
        guard let on = onOff(options.positionals[1]) else {
            return CLIReply.refused(command, reason: "invalidOptions", detail: options.positionals[1])
        }
        let before = preferences.bool(forKey: Self.musicKey(source))
        setMusicSource(source, on)
        return CLIReply.done(command, changed: before != on, ["id": MusicIDs.id(source), "enabled": on])
    }

    private func audioHoldOperation(_ options: CLIOptions) -> CLIResult {
        let command = "audioHold"
        guard options.positionals.count == 1, let on = onOff(options.positionals[0]) else {
            return CLIReply.refused(command, reason: "invalidOptions", detail: "on or off")
        }
        let before = preferences.bool(forKey: Self.anyAudioKey)
        setAnyAudioHold(on)
        return CLIReply.done(command, changed: before != on, ["enabled": on, "holding": audioHoldingNow])
    }

    /// The setting and what it does for one source, as `music list` and `status` report it.
    func musicObject(_ source: MusicSource) -> [String: Any] {
        ["id": MusicIDs.id(source), "enabled": preferences.bool(forKey: Self.musicKey(source)),
         "playingNow": musicHolding.contains(source)]
    }

    /// Turns one music source on or off, then redraws, as the Settings toggle does.
    func setMusicSource(_ source: MusicSource, _ on: Bool) {
        preferences.set(on, forKey: Self.musicKey(source))
        refresh()
    }

    /// Turns the general audio hold on or off, then redraws, as the Settings toggle does.
    func setAnyAudioHold(_ on: Bool) {
        preferences.set(on, forKey: Self.anyAudioKey)
        refresh()
    }

    func agentObject(_ agent: AgentBadgeState) -> [String: Any] {
        ["provider": agent.provider, "enabled": agent.detectionEnabled, "observedState": agent.observedState,
         "readiness": agent.readiness, "workingCount": agent.workingCount, "waitingCount": agent.waitingCount,
         "unknownCount": agent.unknownCount, "processCount": jsonInt(agent.processCount),
         "confidence": agent.confidence, "evidenceAgeSeconds": jsonDouble(agent.evidenceAgeSeconds),
         "cliDetected": jsonBool(agent.cliDetected), "appDetected": jsonBool(agent.appDetected)]
    }

    // MARK: - Language, skill, updates

    func languageObject() -> [String: Any] {
        ["language": language.rawValue, "resolved": Localization.resolve(language) ? "vi" : "en"]
    }

    private func languageSetOperation(_ options: CLIOptions) -> CLIResult {
        let command = "languageSet"
        guard options.positionals.count == 1 else { return CLIReply.refused(command, reason: "invalidOptions") }
        guard let choice = AppLanguage(rawValue: options.positionals[0]) else {
            return CLIReply.refused(command, reason: "invalidLanguage", detail: options.positionals[0])
        }
        let changed = language != choice
        setLanguage(choice)
        return CLIReply.done(command, changed: changed, languageObject())
    }

    func skillObject() -> [String: Any] {
        ["installed": agentSkill.installedPath != nil, "path": agentSkill.location.path]
    }

    private func skillInstallOperation(_ options: CLIOptions) -> CLIResult {
        let command = "skillInstall"
        guard !isQACopy else { return CLIReply.refused(command, reason: "qaCopy") }
        let wasInstalled = agentSkill.installedPath != nil
        switch agentSkill.perform(.install(replacing: options.flags["replace"] != nil)) {
        case .installed:
            refresh()
            return CLIReply.done(command, changed: !wasInstalled, skillObject())
        case .conflict(let path):
            return CLIReply.refused(command, reason: "skillConflict", detail: path)
        case .failed(let message):
            return CLIReply.refused(command, reason: "skillWriteFailed", detail: message)
        case .removed, .nothingToRemove, .keptModified:
            return CLIReply.refused(command, reason: "skillWriteFailed", detail: "unexpected outcome")
        }
    }

    private func skillRemoveOperation() -> CLIResult {
        let command = "skillRemove"
        guard !isQACopy else { return CLIReply.refused(command, reason: "qaCopy") }
        switch agentSkill.perform(.remove) {
        case .removed:
            refresh()
            return CLIReply.done(command, changed: true, skillObject())
        case .nothingToRemove:
            return CLIReply.done(command, changed: false, skillObject())
        case .keptModified:
            return CLIReply.refused(command, reason: "skillModified", detail: agentSkill.location.path)
        case .failed(let message):
            return CLIReply.refused(command, reason: "skillWriteFailed", detail: message)
        case .installed, .conflict:
            return CLIReply.refused(command, reason: "skillWriteFailed", detail: "unexpected outcome")
        }
    }

    func updateObject() -> [String: Any] {
        let snapshot = updates.snapshot
        return ["phase": snapshot.phase.rawValue, "reason": snapshot.reason, "version": jsonString(snapshot.version),
                "sessionActive": session != nil, "recoveryRequired": snapshot.reason == "recoveryRequired",
                "installationAvailable": updates.canInstall, "automaticChecks": updates.automaticChecks]
    }

    private func updateCheckOperation() -> CLIResult {
        let command = "updateCheck"
        guard !isQACopy else { return CLIReply.refused(command, reason: "qaCopy") }
        let busy: Set<UpdatePhase> = [.checking, .preparing, .installing]
        if busy.contains(updates.snapshot.phase) { return CLIReply.done(command, changed: false, updateObject()) }
        updates.check()
        refresh()
        return CLIReply.done(command, changed: true, updateObject())
    }

    private func updateInstallOperation(_ options: CLIOptions) -> CLIResult {
        let command = "updateInstall"
        guard !isQACopy else { return CLIReply.refused(command, reason: "qaCopy") }
        guard updates.canInstall else { return updateNotReady(command) }
        let endingSession = options.flags["stop-session"] != nil
        if session != nil, !endingSession { return CLIReply.refused(command, reason: "sessionActive") }
        // The same agreement the Updates window records: a session ends only when the user agreed, and only at the restart.
        agreedSessionStart = endingSession ? session?.startedAtMonotonic : nil
        updates.installAvailable(endingSession: endingSession)
        refresh()
        let phase = updates.snapshot.phase
        guard phase == .preparing || phase == .installing else {
            agreedSessionStart = nil
            return updateNotReady(command)
        }
        return CLIReply.done(command, changed: true, updateObject())
    }

    /// Why the update cannot install now. A recovery that is still needed has its own reason, which exits 5.
    private func updateNotReady(_ command: String) -> CLIResult {
        let reason = updates.snapshot.reason == "recoveryRequired" ? "recoveryRequired" : "updateNotReady"
        return CLIReply.refused(command, reason: reason, detail: updates.snapshot.reason)
    }

    private func updateAutoOperation(_ options: CLIOptions) -> CLIResult {
        let command = "updateAuto"
        guard options.positionals.count == 1, let on = onOff(options.positionals[0]) else {
            return CLIReply.refused(command, reason: "invalidOptions", detail: "on or off")
        }
        let before = updates.automaticChecks
        updates.setAutomaticChecks(on)
        refresh()
        return CLIReply.done(command, changed: before != on, ["automaticChecks": on])
    }

    // MARK: - Closed lid, notifications, welcome, windows, login, version

    private func untestedOperation(_ options: CLIOptions) -> CLIResult {
        let command = "closedLidAcknowledge"
        let confirm = options.flags["confirm"] != nil
        let revoke = options.flags["revoke"] != nil
        guard !(confirm && revoke) else {
            return CLIReply.refused(command, reason: "invalidOptions", detail: "confirm and revoke",
                hint: "Pass --confirm to allow closed-lid protection on this Mac, or --revoke to withdraw it, not both.")
        }
        guard confirm || revoke else {
            return CLIReply.refused(command, reason: "confirmationRequired",
                hint: "CamLid hasn’t been tested on this Mac. If something fails, this Mac may stay awake with the lid closed until "
                    + "the helper or its recovery job restores the sleep setting. This applies to this Mac and macOS build only. "
                    + "Run the same command with --confirm to allow it, or with --revoke to withdraw the allowance.")
        }
        let before = untestedAcknowledgementStored
        setUntestedAcknowledgement(confirm)
        let after = untestedAcknowledgementStored
        // The acknowledgement needs this Mac's model and macOS build. Without them nothing is recorded, and the reply says so.
        guard after == confirm else { return CLIReply.refused(command, reason: "macIdentityUnavailable") }
        return CLIReply.done(command, changed: before != after,
            ["acknowledged": after, "closedLidPermit": closedLidPermit().statusCode])
    }

    private func notificationsRequestOperation() -> CLIResult {
        let command = "notificationsRequest"
        let before = outcomeNotifications.permissionState
        guard before != "unavailable" else { return CLIReply.refused(command, reason: "notificationsUnavailable") }
        // macOS asks once. A permission already decided, or a request already running, stands: nothing changes.
        guard before == "notDetermined" else { return CLIReply.done(command, changed: false, ["permission": before]) }
        Task { await outcomeNotifications.authorizeFromUserAction() }
        refresh()
        return CLIReply.done(command, changed: true, ["permission": "requesting"])
    }

    private func welcomeCompleteOperation() -> CLIResult {
        let command = "welcomeComplete"
        if preferences.bool(forKey: Self.onboardedKey) { return CLIReply.done(command, changed: false, ["done": true]) }
        guard finishOnboarding() else { return CLIReply.refused(command, reason: "appUnavailable") }
        return CLIReply.done(command, changed: true, ["done": true])
    }

    /// Opens one window, as the menus do. Windows show state and change nothing, so the reply reports no change.
    private func openOperation(_ options: CLIOptions) -> CLIResult {
        let command = "open"
        guard options.positionals.count == 1 else { return CLIReply.refused(command, reason: "invalidOptions") }
        let window = options.positionals[0]
        switch window {
        case "dashboard": toggleDashboard(show: true)
        case "settings": showSettings()
        case "settings.general": showSettingsPane(.general)
        case "settings.agents": showSettingsPane(.agents)
        case "settings.closed-lid": showSettingsPane(.safety)
        case "activity": showActivityLog()
        case "updates": menuBarOpenUpdates()
        case "diagnostics": menuBarOpenSleepDiagnostics()
        case "welcome": showOnboarding()
        case "about": AboutPanel.show()
        case "releases": NSWorkspace.shared.open(GitHubReleaseDriver.releasesPage)
        default: return CLIReply.refused(command, reason: "unknownWindow", detail: window)
        }
        return CLIReply.done(command, changed: false, ["window": window])
    }

    private func loginOperation() -> CLIResult {
        let command = "loginApply"
        let before = loginItem.state
        loginItem.apply(config.launchAtLogin)
        refresh()
        let state = loginItem.state
        guard state != "error" else { return CLIReply.refused(command, reason: "loginItemFailed") }
        return CLIReply.done(command, changed: before != state, ["launchAtLogin": config.launchAtLogin, "state": state])
    }

    private func versionOperation() -> CLIResult {
        CLIReply.read("version", ["app": appVersionObject(),
                                  "helper": ["bundledVersion": PowerHelperVersion.current, "state": helper.state]])
    }

    /// The app's version and build, from its bundle.
    func appVersionObject() -> [String: Any] {
        let bundle = Bundle.main
        return ["version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                "copyright": bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "unknown"]
    }

    /// Whether a configuration reply says the setting changed. A reply without the key counts as a change, as before.
    static func replyChanged(_ result: CLIResult) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(result.json.utf8)) as? [String: Any])?["changed"] as? Bool ?? true
    }

    /// The fields `status` adds for the CLI. Existing fields are unchanged.
    func controlStatusFields() -> [String: Any] {
        ["version": appVersionObject(), "language": languageObject(),
         "music": MusicSource.allCases.map(musicObject),
         "audioHold": ["enabled": preferences.bool(forKey: Self.anyAudioKey), "holding": audioHoldingNow],
         "skill": skillObject(), "welcome": ["done": preferences.bool(forKey: Self.onboardedKey)]]
    }

    /// `agents list`: each provider the app watches, with its enrolment and what it observes.
    func agentsListReply() -> CLIResult {
        CLIReply.read("agentsList", ["available": true, "agents": badgeStates().map(agentObject)])
    }

    // MARK: - Helpers

    /// `on` or `off`. Anything else is not a choice.
    func onOff(_ text: String) -> Bool? {
        switch text {
        case "on": true
        case "off": false
        default: nil
        }
    }

    /// A string, or JSON null when there is none.
    func jsonString(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }

    private func jsonInt(_ value: Int?) -> Any { value.map { $0 as Any } ?? NSNull() }

    private func jsonDouble(_ value: Double?) -> Any { value.map { $0 as Any } ?? NSNull() }

    private func jsonBool(_ value: Bool?) -> Any { value.map { $0 as Any } ?? NSNull() }

    /// A redacted record as a JSON object with ISO 8601 dates, for `logs list`. Empty when it cannot be encoded.
    private func redactedObject(_ record: RedactedTransition) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
}
