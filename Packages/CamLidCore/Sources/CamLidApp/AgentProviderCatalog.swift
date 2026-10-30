import Foundation
import CamLidCore

/// One supported agent product and the local signals that can identify it.
/// Detection deliberately says nothing about task state or completion.
struct AgentProviderInfo: Sendable, Equatable {
    let id: String
    let title: String
    /// Executable basenames found on PATH.
    let cliNames: [String]
    /// Executable basenames observed in the bounded process scan.
    let processNames: [String]
    /// Installed macOS application bundle identifiers.
    let applicationBundleIDs: [String]
    let assetName: String?
    let symbolName: String?
    let monogram: String?

    var supportsDetection: Bool {
        !cliNames.isEmpty || !processNames.isEmpty || !applicationBundleIDs.isEmpty
    }
}

/// Provider identity and detection metadata live in one place so Settings,
/// onboarding, process discovery, and CLI/application checks stay aligned.
enum AgentProviderCatalog {
    static let providers: [AgentProviderInfo] = [
        AgentProviderInfo(
            id: "orca", title: "Orca",
            cliNames: ["orca", "orca-cli"], processNames: ["orca"],
            applicationBundleIDs: [], assetName: "agent-orca", symbolName: nil, monogram: nil),
        AgentProviderInfo(
            id: "codex", title: "Codex",
            cliNames: ["codex"], processNames: ["codex"],
            applicationBundleIDs: ["com.openai.codex"],
            assetName: "agent-codex", symbolName: nil, monogram: nil),
        AgentProviderInfo(
            id: "opencode", title: "OpenCode",
            cliNames: ["opencode"], processNames: ["opencode"],
            applicationBundleIDs: [], assetName: nil, symbolName: nil, monogram: nil),
        AgentProviderInfo(
            // Observed from outside only (ADR 0002); no bundled artwork, so a neutral symbol.
            id: "claude", title: "Claude Code",
            cliNames: ["claude"], processNames: ["claude"],
            applicationBundleIDs: [], assetName: nil, symbolName: "asterisk", monogram: nil),
        AgentProviderInfo(
            id: "freebuff", title: "Freebuff",
            cliNames: ["freebuff"], processNames: ["freebuff"],
            applicationBundleIDs: [], assetName: "agent-freebuff", symbolName: "bolt.fill", monogram: nil),
        AgentProviderInfo(
            id: "pi", title: "Pi",
            cliNames: ["pi"], processNames: ["pi"],
            applicationBundleIDs: [], assetName: "agent-pi", symbolName: nil, monogram: "π"),
        AgentProviderInfo(
            id: "copilot-cli", title: "GitHub Copilot CLI",
            cliNames: ["copilot"], processNames: ["copilot"],
            applicationBundleIDs: [], assetName: "agent-copilot-cli", symbolName: "paperplane.fill", monogram: nil),
        AgentProviderInfo(
            id: "vscode-copilot", title: "VS Code Copilot",
            cliNames: [], processNames: [], applicationBundleIDs: [],
            assetName: "agent-vscode-copilot", symbolName: "chevron.left.forwardslash.chevron.right", monogram: nil),
        AgentProviderInfo(
            id: "antigravity", title: "Antigravity",
            cliNames: ["agy"], processNames: ["antigravity"],
            applicationBundleIDs: ["com.google.antigravity", "com.google.antigravity-ide"],
            assetName: "agent-antigravity", symbolName: "sparkles", monogram: nil),
        AgentProviderInfo(
            id: "cursor", title: "Cursor",
            cliNames: ["cursor-agent", "agent"], processNames: ["cursor"],
            applicationBundleIDs: ["com.todesktop.230313mzl4w4u92"],
            assetName: "agent-cursor", symbolName: "cursorarrow.rays", monogram: nil),
        AgentProviderInfo(
            id: "windsurf", title: "Windsurf / Devin",
            cliNames: [], processNames: [], applicationBundleIDs: [],
            assetName: "agent-windsurf", symbolName: "wind", monogram: nil),
        AgentProviderInfo(
            id: "aider", title: "Aider",
            cliNames: ["aider"], processNames: ["aider"],
            applicationBundleIDs: [], assetName: "agent-aider", symbolName: "hammer.fill", monogram: nil),
        AgentProviderInfo(
            id: "gemini-cli", title: "Gemini CLI",
            cliNames: ["gemini"], processNames: ["gemini"],
            applicationBundleIDs: [], assetName: "agent-gemini-cli", symbolName: "diamond.fill", monogram: nil),
        AgentProviderInfo(
            id: "cline", title: "Cline",
            cliNames: [], processNames: [], applicationBundleIDs: [],
            assetName: "agent-cline", symbolName: "c.circle.fill", monogram: nil),
        AgentProviderInfo(
            id: "roo-code", title: "Roo Code",
            cliNames: [], processNames: [], applicationBundleIDs: [],
            assetName: "agent-roocode", symbolName: "r.circle.fill", monogram: nil),
        AgentProviderInfo(
            id: "amp", title: "Amp",
            cliNames: ["amp"], processNames: ["amp"],
            applicationBundleIDs: [], assetName: "agent-amp", symbolName: "bolt.circle.fill", monogram: nil),
        AgentProviderInfo(
            id: "goose", title: "Goose",
            cliNames: ["goose"], processNames: ["goose"],
            applicationBundleIDs: [], assetName: "agent-goose", symbolName: "bird.fill", monogram: nil)
    ]

    static let byID: [String: AgentProviderInfo] = Dictionary(
        uniqueKeysWithValues: providers.map { ($0.id, $0) })

    static var ids: [String] { providers.map(\.id) }
    static var supportedIDs: Set<String> { Set(providers.filter(\.supportsDetection).map(\.id)) }
    static var processNames: Set<String> { Set(providers.flatMap(\.processNames)) }

    static var processPatterns: [CandidatePattern] {
        providers.flatMap { info in
            info.processNames.map { CandidatePattern(executableContains: $0, provider: info.id) }
        }
    }

    static func info(for id: String) -> AgentProviderInfo? { byID[id] }
    static func title(for id: String) -> String { byID[id]?.title ?? id.capitalized }
}
