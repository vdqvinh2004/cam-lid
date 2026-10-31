import AppKit
import Darwin
import CamLidCore

/// A view-only subprocess owns heavyweight UI framework caches. The persistent
/// process remains the sole policy, preference, history and CLI authority.
enum UtilitySurface: String, Codable, Sendable { case dashboard, settings, activity, onboarding, updates, sleepDiagnostics }
struct UtilityUIState: Codable, Sendable {
    var dashboard: DashboardData
    var configuration: Configuration
    var revision: Int
    var protection: ProtectionReadiness
    var settingsSection: SettingsSection
    var anchorFrame: NSRect
    var installationPending: Bool
    var observationReady: Bool = false
    var updates = UpdateSnapshot(phase: .unavailable, reason: "developerIDRequired")
    var canCheckUpdates = false
    var loginState = "notRegistered"
    var loginMessage = "Login registration has not been checked."
    var notificationPermission = "notDetermined"
    var accessibilityPermission = "unavailable"
    var permissionSettingsError: String?
    var helperState = "unknown"
    var helperMessage = "Helper status has not been checked."
    var helperBusy = false
    var closedLidPermit = "notPermitted"
    var strictTested = false
    var systemModel = ""
    var systemBuild = ""
    var keepAwakeApps: [KeepAwakeApp] = []
    var capabilityText = ""
}
enum UtilityUICommand: Codable, Sendable {
    case show(UtilitySurface, UtilityUIState)
    case update(UtilityUIState)
    case diagnostics(UUID, DiagnosticSnapshot)
    case closeDashboard
    case commitResult(UUID, SettingsCommitResult)
    case exportData(Data)
    case prepareToQuit
    case historyLoading(UUID)
    case history(UUID, [StoredTransition], error: String?, outcome: String?)
    case onboardingResult(UUID, Bool)
}
enum UtilityUIEvent: Codable, Sendable {
    case visibility(dashboard: Bool, settings: Bool)
    case commit(UUID, ConfigPatch, Int)
    case activateMode(RequestedMode, Int)
    case timerDuration(Int, Int)
    case sleepDelay(Int, Int)
    case start, stop, activity, onboarding, updates, sleepDiagnostics, quit, restoreStatusFocus
    case notice(String)
    case editorState(dirty: Bool)
    case section(SettingsSection)
case settings(SettingsSection)
    case quitDecision(Bool)
    case activityOutcome(String)
    case exportHistory
    case deleteHistory(String?)
    case finishOnboarding(UUID)
    case cancelOnboarding
    case readDiagnostics(UUID)
    case reloadHistory
    case checkUpdates
    case authorizeNotifications, applyLoginPreference
    case installHelper, uninstallHelper
    case setUntestedAcknowledgement(Bool)
    case authorizeAccessibility, refreshPermissions
    case openPermissionSettings(AppPermission)
}

/// Anonymous pipes are accessible only to this parent and its owned child.
/// Frames are bounded JSON lines; handlers consume them in FIFO order on main.
@MainActor
final class UtilityUIPipe {
    private let input: FileHandle
    private let output: FileHandle
    private let writes = DispatchQueue(label: "CamLid.UI.pipe-writes", qos: .utility)
    private var buffer = Data()
    private var scannedBytes = 0
    private let receive: (Data) -> Void
    private let closed: () -> Void
    private var ended = false
    // History is bounded at 20 MiB; its existing decoded projection may be larger.
    nonisolated static let maximumFrameBytes = 64 * 1024 * 1024
    init(input: FileHandle, output: FileHandle, receive: @escaping (Data) -> Void, closed: @escaping () -> Void) {
        self.input = input; self.output = output; self.receive = receive; self.closed = closed
        _ = fcntl(output.fileDescriptor, F_SETNOSIGPIPE, 1)
        input.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            DispatchQueue.main.async { self?.consume(chunk) }
        }
    }
    private func consume(_ chunk: Data) {
        guard !ended else { return }
        guard !chunk.isEmpty else { end(); return }
        buffer.append(chunk)
        while let newline = buffer.dropFirst(scannedBytes).firstIndex(of: 10) {
            guard newline < Self.maximumFrameBytes else { end(); return }
            let frame = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            scannedBytes = 0
            receive(frame)
        }
        scannedBytes = buffer.count
        if buffer.count >= Self.maximumFrameBytes { end() }
    }
    @discardableResult func send<T: Encodable & Sendable>(_ value: T) -> Bool {
        guard !ended else { return false }
        let output = self.output
        writes.async { [weak self] in
            guard var data = try? JSONEncoder().encode(value), data.count < Self.maximumFrameBytes else {
                DispatchQueue.main.async { self?.end() }; return
            }
            data.append(10)
            do { try output.write(contentsOf: data) } catch { DispatchQueue.main.async { self?.end() } }
        }
        return true
    }
    func end() {
        guard !ended else { return }; ended = true
        input.readabilityHandler = nil
        try? input.close()
        let output = self.output; writes.async { try? output.close() }
        buffer.removeAll(); scannedBytes = 0; closed()
    }
}

@MainActor
final class UtilityUIProcess {
    private let process = Process()
    private var pipe: UtilityUIPipe?
    private var quitWaiter: CheckedContinuation<Bool, Never>?
    private let event: (UtilityUIEvent) -> Void
    private let exited: (Int32) -> Void
    private(set) var dashboardVisible = false
    private(set) var settingsVisible = false
    private(set) var settingsDirty = false
    var pid: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }
    init(event: @escaping (UtilityUIEvent) -> Void, exited: @escaping (Int32) -> Void) throws {
        self.event = event; self.exited = exited
        let incoming = Pipe(); let outgoing = Pipe()
        process.executableURL = Bundle.main.executableURL
        process.arguments = ["--utility-ui"]
        process.standardInput = outgoing
        process.standardOutput = incoming
        process.standardError = FileHandle.nullDevice
        pipe = UtilityUIPipe(input: incoming.fileHandleForReading, output: outgoing.fileHandleForWriting, receive: { [weak self] data in
            guard let self, let message = try? JSONDecoder().decode(UtilityUIEvent.self, from: data) else { return }
            switch message {
            case .visibility(let dashboard, let settings): self.dashboardVisible = dashboard; self.settingsVisible = settings
            case .editorState(let dirty): self.settingsDirty = dirty
            case .quitDecision(let approved): self.quitWaiter?.resume(returning: approved); self.quitWaiter = nil
            default: break
            }
            self.event(message)
        }, closed: { [weak self] in
            guard let self, !self.finished else { return }
            if self.process.isRunning { self.process.terminate() } else { self.finish() }
        })
        process.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.finish() } }
        try process.run()
        // Parent must not retain the child's ends: EOF is a lifecycle signal.
        try incoming.fileHandleForWriting.close(); try outgoing.fileHandleForReading.close()
    }
    @discardableResult func send(_ command: UtilityUICommand) -> Bool { pipe?.send(command) ?? false }
    func prepareToQuit() async -> Bool {
        guard isRunning else { return true }
        return await withCheckedContinuation { continuation in
            guard quitWaiter == nil else { continuation.resume(returning: false); return }
            quitWaiter = continuation
            if !send(.prepareToQuit) { quitWaiter = nil; continuation.resume(returning: true) }
        }
    }
    private var finished = false
    private func finish() {
        guard !finished else { return }; finished = true
        dashboardVisible = false; settingsVisible = false
        quitWaiter?.resume(returning: true); quitWaiter = nil
        pipe?.end(); pipe = nil
        exited(process.processIdentifier)
    }
    func close() { pipe?.end(); if process.isRunning { process.terminate() } }
}
