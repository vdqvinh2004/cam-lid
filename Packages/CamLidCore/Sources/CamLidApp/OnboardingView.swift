import SwiftUI

public enum OnboardingPage: Int, Sendable, CaseIterable {
    case welcome, detection, rollback
    public var title: String {
        switch self {
        case .welcome: "Meet CamLid"
        case .detection: "Your agents"
        case .rollback: "Limits and controls"
        }
    }
    var preferredHeight: CGFloat {
        400 // Keep navigation buttons stationary while page content scrolls.
    }
}

/// Read-only introduction. Finishing acknowledges completion, never changes
/// consent, enrollment, mode, or power settings.
public struct OnboardingView: View {
    public let agents: [AgentBadgeState]
    public let isObserving: Bool
    public let onFinish: @MainActor () async -> Bool
    public let onCancel: () -> Void
    public let onPageChange: (OnboardingPage) -> Void
    @State private var page: OnboardingPage = .welcome
    @State private var finishing = false
    @State private var finishFailed = false

    public init(agents: [AgentBadgeState] = [], isObserving: Bool = true,
                initialPage: OnboardingPage = .welcome,
                onFinish: @escaping @MainActor () async -> Bool, onCancel: @escaping () -> Void,
                onPageChange: @escaping (OnboardingPage) -> Void = { _ in }) {
        self.agents = agents; self.isObserving = isObserving
        self.onFinish = onFinish; self.onCancel = onCancel
        self.onPageChange = onPageChange; _page = State(initialValue: initialPage)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step \(page.rawValue + 1) of \(OnboardingPage.allCases.count)")
                .font(.caption).foregroundStyle(.secondary)
            Text(page.title).font(.title2).bold()
            ScrollView {
                OnboardingContent(page: page, agents: agents, isObserving: isObserving)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if finishFailed {
                Label("Couldn’t complete Welcome. Keep CamLid open and try again. Your settings are unchanged.",
                      systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .help("Welcome could not finish; retry without changing settings")
                    .accessibilityIdentifier("camlid.onboarding.error")
            }
            HStack {
                Button("Back") { page = OnboardingPage(rawValue: page.rawValue - 1)! }
                    .disabled(page == .welcome || finishing)
                    .accessibilityIdentifier(CamLidAccessibility.IDs.onboardingBack)
                Spacer()
                Button("Skip", action: onCancel)
                    .disabled(finishing).keyboardShortcut(.cancelAction)
                if page == .rollback {
                    if finishing { ProgressView().controlSize(.small).accessibilityLabel("Completing Welcome") }
                    Button(finishFailed ? "Retry" : "Finish") {
                        finishing = true; finishFailed = false
                        Task { @MainActor in
                            let completed = await onFinish()
                            finishing = false; finishFailed = !completed
                        }
                    }
                    .disabled(finishing).keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(CamLidAccessibility.IDs.onboardingFinish)
                } else {
                    Button("Continue") { page = OnboardingPage(rawValue: page.rawValue + 1)! }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(CamLidAccessibility.IDs.onboardingNext)
                }
            }
        }.padding(20).frame(minWidth: 440, minHeight: 260)
            .onChange(of: page) { _, value in onPageChange(value) }
    }
}

private struct OnboardingContent: View {
    let page: OnboardingPage
    let agents: [AgentBadgeState]
    let isObserving: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch page {
            case .welcome:
                Text("Follow your local coding agents from the menu bar.")
                Label("Power control unavailable", systemImage: "shield.slash").font(.headline)
                    .help("Preview only; Mac sleep behavior is unchanged")
                Text("This build observes activity and previews session behavior. It does not keep the Mac awake or change lid-close sleep.")
                    .foregroundStyle(.secondary)
                Text("Click the menu-bar icon for the dashboard. Right-click or Control-click for options.")
            case .detection:
                Text("Dashboard shows selected agents reporting work. Choose agents in Settings → Agents.")
                if isObserving {
                    ProgressView("Looking for local agents…").controlSize(.small)
                }
                ForEach(agents) { agent in
                    HStack {
                        AgentMarkView(provider: agent.provider).help(agent.title)
                        Text(agent.title)
                        Spacer()
                        if agent.waitingCount > 0 {
                            Label("\(agent.waitingCount)", systemImage: "hourglass")
                                .monospacedDigit().foregroundStyle(.secondary)
                                .help("\(agent.waitingCount) tasks waiting for user. Waiting never holds power.")
                                .accessibilityLabel("\(agent.waitingCount) tasks waiting for user")
                        }
                        if agent.workingCount > 0 {
                            Label("\(agent.workingCount)", systemImage: "terminal")
                                .monospacedDigit().foregroundStyle(.secondary)
                                .help("\(agent.workingCount) working tasks reported by \(agent.title)")
                                .accessibilityLabel("\(agent.workingCount) reported working tasks")
                        } else if agent.waitingCount == 0 { Text(agent.compactDetail).foregroundStyle(.secondary) }
                    }.accessibilityElement(children: .combine)
                        .padding(.vertical, 4).help(agent.detail + ". " + agent.observationExplanation)
                        .accessibilityValue(agent.observationExplanation)
                        .accessibilityIdentifier("camlid.onboarding.agent." + agent.provider)
                }
                Text("Detection needs no setup. A running app alone doesn’t prove work or completion.")
                    .font(.callout).foregroundStyle(.secondary)
            case .rollback:
                Label("Use a ventilated desk, never a closed bag.", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .help("Ventilation is required; keep the Mac out of closed bags")
                Text("Click Auto or Timed to start. Click the active mode again to stop. Auto’s Sleep when done sets the delay after selected work ends.")
                Text("Infinite has no time limit. Battery and thermal safety stops still apply. Activity shows what happened and why.")
                    .foregroundStyle(.secondary)
                Text("Readings can be delayed or unavailable. This preview cannot keep the Mac awake or change lid-close sleep.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Observed agents") {
    OnboardingView(agents: [AgentBadgeState(provider: "codex", enabled: false, tasks: [], processCount: 1)],
                   isObserving: false, onFinish: { true }, onCancel: {})
}
