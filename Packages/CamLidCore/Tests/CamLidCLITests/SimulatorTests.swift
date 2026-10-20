import Foundation
import Testing
import CamLidCLI

@testable import CamLidCore

// Simulator determinism + engine hazard coverage.

func hazardScenario() -> SimulationScenario {
    SimulationScenario(name: "grace-race-cap", steps: [
        SimulationStep(at: 0, taskStates: ["working"]),
        SimulationStep(at: 10, taskStates: ["working"]),
        SimulationStep(at: 20, taskStates: ["completed"]),
        SimulationStep(at: 60, taskStates: ["working"]),
        SimulationStep(at: 400, taskStates: ["working"]),
        SimulationStep(at: 500, taskStates: ["working"]),
    ])
}

@Suite("Simulator")
struct SimulatorTests {
    @Test("same scenario twice yields identical traces")
    func deterministicGolden() throws {
        let config = try Configuration(completionDelayMinutes: 2, runCapMinutes: 5)
        let first = Simulator().run(scenario: hazardScenario(), config: config)
        let second = Simulator().run(scenario: hazardScenario(), config: config)
        #expect(first == second)
        #expect(first.simulated)
        #expect(first.transitions.count == 6)
    }

    @Test("grace race returns to protected; cap never resets")
    func graceRaceAndCap() throws {
        let config = try Configuration(completionDelayMinutes: 2, runCapMinutes: 5)
        let result = Simulator().run(scenario: hazardScenario(), config: config)
        let states = result.transitions.map(\.state)
        #expect(states == [.protected, .protected, .completionGrace, .protected, .expired, .expired])
        #expect(result.transitions[2].reasons.contains("lastTaskStopped"))
        #expect(result.transitions[4].reasons.contains("capReached"))
        #expect(result.transitions[5].reasons.contains("capReached"))
    }

    @Test("scenario decodes from JSON fixtures with missing keys")
    func jsonFixtureDecodes() throws {
        let json = """
            {"name":"fixture","steps":[{"at":0},{"at":10,"lidState":"closed","taskStates":["completed"]}]}
            """
        let scenario = try JSONDecoder().decode(
            SimulationScenario.self, from: Data(json.utf8))
        #expect(scenario.name == "fixture")
        #expect(scenario.steps.count == 2)
        #expect(scenario.steps[0].lidState == nil)
        #expect(scenario.steps[1].lidState == .closed)
        let config = try Configuration()
        let result = Simulator().run(scenario: scenario, config: config)
        #expect(result.simulated)
        #expect(result.transitions.count == 2)
    }
}
