import Testing
@testable import CamLidApp

/// Spec 018 US4 (T042), reading agreed 2026-11-05: a CPU-busy process that is not a recognised agent is never sampled,
/// so it cannot become Working. Agent work is inferred only from recognised agent processes (ADR 0002).
@Suite("A busy process that is not an agent")
struct BusyNonAgentProcessTests {
    @Test func unrelatedBusyCommandsHaveNoAgentIdentity() {
        #expect(!AgentProviderCatalog.processNames.contains("yes"))
        #expect(!AgentProviderCatalog.processNames.contains("caffeinate"))
    }

    @Test func aBusyInterpreterScriptIsNotAnAgentUnlessItsArgumentsNameOne() {
        #expect(NativeProcessList.agent(fromArguments: ["node", "/Users/x/project/dev-server.js"]) == nil)
        #expect(NativeProcessList.agent(fromArguments: ["/usr/bin/python3", "-m", "http.server"]) == nil)
    }
}
