import SwiftUI

public enum OnboardingPage: Int, Sendable, CaseIterable {
    case welcome, detection, rollback
    public var title: String {
        switch self {
        case .welcome: tr("Meet CamLid")
        case .detection: tr("Your agents")
        case .rollback: tr("Limits and controls")
        }
    }
    var preferredHeight: CGFloat {
        432 // One height for every page (no jump); step 1 is the tallest static page, the agent list scrolls.
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
                Text(trf("Step %lld of %lld", page.rawValue + 1, OnboardingPage.allCases.count))
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
                    tr("Couldn’t complete Welcome. Keep CamLid open and try again. Your settings are unchanged."),
                    systemImage: "exclamationmark.circle", tone: .danger,
                    help: tr("Welcome could not finish; retry without changing settings")
                )
                .accessibilityIdentifier("camlid.onboarding.error")
            }
            Divider()
            HStack {
                Button(tr("Back")) { page = OnboardingPage(rawValue: page.rawValue - 1)! }
                    .disabled(page == .welcome || finishing)
                    .accessibilityIdentifier(CamLidAccessibility.IDs.onboardingBack)
                Spacer()
                Button(page == .rollback ? tr("Close") : tr("Skip"), action: onCancel)
                    .disabled(finishing).keyboardShortcut(.cancelAction)
                if page == .rollback {
                    if finishing { ProgressView().controlSize(.small).accessibilityLabel(tr("Completing Welcome")) }
                    Button(finishFailed ? tr("Retry") : tr("Finish")) {
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
                    Button(tr("Continue")) { page = OnboardingPage(rawValue: page.rawValue + 1)! }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(CamLidAccessibility.IDs.onboardingNext)
                }
            }
        }.padding(20).frame(minWidth: 440, minHeight: 260)
            .onChange(of: page) { _, value in onPageChange(value) }
    }
}

private struct OnboardingModeRow: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(Color.accentColor).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
                Text(tr("Follow your local coding agents from the menu bar."))
                VStack(alignment: .leading, spacing: 10) {
                    OnboardingModeRow(symbol: "arrow.triangle.2.circlepath", title: tr("Auto"),
                                      text: tr("Keeps the Mac awake while your agents work, then lets it sleep."))
                    OnboardingModeRow(symbol: "timer", title: tr("Timed"),
                                      text: tr("Keeps it awake for a time you choose, or until you stop it."))
                }
                CamLidNoticeCard(
                    tone: .info, systemImage: "info.circle", title: tr("Closed lid"),
                    message: tr("Keeping the Mac awake with the lid closed needs the CamLid helper, and works on tested Macs or on this Mac after you allow it in Settings › Closed Lid. Until then you can explore sessions, agents and safety limits.")
                )
                Text(tr("Click the menu-bar icon for the dashboard. Right-click or Control-click for options."))
                    .font(.callout)
            case .detection:
                Text(tr("CamLid can keep your agents working while you step away."))
                if detectedAgents.isEmpty {
                    if isObserving {
                        ProgressView(tr("Looking for local agents…")).controlSize(.small)
                    } else {
                        Text(tr("No supported agents detected on this Mac."))
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
                Text(tr("CamLid finds these agents automatically on this Mac."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .rollback:
                CamLidNoticeCard(
                    tone: .warning, systemImage: "exclamationmark.triangle.fill",
                    title: tr("Use a ventilated desk, never a closed bag."),
                    help: tr("Ventilation is required; keep the Mac out of closed bags")
                )
                Text(tr("Choose Auto or Timed in the dashboard. Click the active mode again to stop. Auto’s Sleep when done sets the delay after selected work ends."))
                Text(tr("Infinite has no time limit. Battery and thermal safety stops still apply. Activity records what happened and why."))
                    .foregroundStyle(.secondary)
                Text(tr("Readings can be delayed or unavailable."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview(tr("Observed agents")) {
    OnboardingView(agents: [AgentBadgeState(provider: "codex", enabled: false, tasks: [], processCount: 1)],
                   isObserving: false, onFinish: { true }, onCancel: {})
}
