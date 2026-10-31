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
        424 // Keep the agent list and its note visible above the pinned footer.
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
            HStack(alignment: .center) {
                Text("Step \(page.rawValue + 1) of \(OnboardingPage.allCases.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(OnboardingPage.allCases, id: \.self) { item in
                        Capsule()
                            .fill(item.rawValue <= page.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: item == page ? 18 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            Text(page.title).font(.title2).bold()
            ScrollView {
                OnboardingContent(page: page, agents: agents, isObserving: isObserving)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if finishFailed {
                CamLidStatusLabel(
                    "Couldn’t complete Welcome. Keep CamLid open and try again. Your settings are unchanged.",
                    systemImage: "exclamationmark.circle", tone: .danger,
                    help: "Welcome could not finish; retry without changing settings"
                )
                .accessibilityIdentifier("camlid.onboarding.error")
            }
            Divider()
            HStack {
                Button("Back") { page = OnboardingPage(rawValue: page.rawValue - 1)! }
                    .disabled(page == .welcome || finishing)
                    .accessibilityIdentifier(CamLidAccessibility.IDs.onboardingBack)
                Spacer()
                Button(page == .rollback ? "Close" : "Skip", action: onCancel)
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
    private var detectedAgents: [AgentBadgeState] {
        agents.filter { $0.isDetected || $0.cliDetected == true }.sortedForAgentDisplay()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch page {
            case .welcome:
                Text("Follow your local coding agents from the menu bar.")
                CamLidNoticeCard(
                    tone: .info, systemImage: "info.circle", title: "Closed lid",
                    message: "Keeping the Mac awake with the lid closed needs the CamLid helper, and works on tested Macs or on this Mac after you allow it in Settings › Closed Lid. Until then you can explore sessions, agents and safety limits."
                )
                Text("Click the menu-bar icon for the dashboard. Right-click or Control-click for options.")
                    .font(.callout)
            case .detection:
                Text("CamLid can keep your agents working while you step away.")
                if detectedAgents.isEmpty {
                    if isObserving {
                        ProgressView("Looking for local agents…").controlSize(.small)
                    } else {
                        Text("No supported agents detected on this Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    BadgeFlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(detectedAgents) { agent in
                            AgentBadge(provider: agent.provider, title: agent.title)
                                .accessibilityIdentifier("camlid.onboarding.agent." + agent.provider)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("CamLid finds these agents automatically on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .rollback:
                CamLidNoticeCard(
                    tone: .warning, systemImage: "exclamationmark.triangle.fill",
                    title: "Use a ventilated desk, never a closed bag.",
                    help: "Ventilation is required; keep the Mac out of closed bags"
                )
                Text("Choose Auto or Timed in the dashboard. Click the active mode again to stop. Auto’s Sleep when done sets the delay after selected work ends.")
                Text("Infinite has no time limit. Battery and thermal safety stops still apply. Activity records what happened and why.")
                    .foregroundStyle(.secondary)
                Text("Readings can be delayed or unavailable.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Observed agents") {
    OnboardingView(agents: [AgentBadgeState(provider: "codex", enabled: false, tasks: [], processCount: 1)],
                   isObserving: false, onFinish: { true }, onCancel: {})
}
