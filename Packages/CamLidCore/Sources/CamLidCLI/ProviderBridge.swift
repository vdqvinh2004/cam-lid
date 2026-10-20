import Foundation
import CamLidCore

/// Explicitly piped provider JSONL -> metadata-only local events. This does
/// not discover ports, install hooks, submit prompts, or infer completion at EOF.
public enum ProviderBridge {
    public static func run(provider: String, channel: any IPCChannel,
        input: FileHandle = .standardInput) -> CLIResult {
        do {
            var stream = try ProviderStream(provider: provider)
            var buffer = Data()
            var accepted = 0
            var failedTools = 0
            func forward(_ events: [NormalizedEvent]) throws {
                for event in events {
                    let reply = try channel.send(command: .event, payload: JSONEncoder().encode(event))
                    guard let object = try JSONSerialization.jsonObject(with: reply) as? [String: Any],
                          object["accepted"] as? Bool == true else { throw IPCError.invalidInput("eventNotAccepted") }
                    accepted += 1
                }
            }
            do {
                while let chunk = try input.read(upToCount: 4_096), !chunk.isEmpty {
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                        if line.isEmpty { continue }
                        try forward(stream.consume(line, now: ContinuousTime.now))
                        if let outcome = stream.lastToolOutcome, outcome.failed {
                            failedTools += 1
                            let diagnostic = ProviderDiagnostic(provider: provider, outcome: outcome)
                            _ = try channel.send(command: .agentDiagnostic, payload: JSONEncoder().encode(diagnostic))
                        }
                    }
                    guard buffer.count <= PolicyLimits.maxEventBytes else { throw IPCError.tooLarge(buffer.count) }
                }
                if !buffer.isEmpty {
                    try forward(stream.consume(buffer, now: ContinuousTime.now))
                    if let outcome = stream.lastToolOutcome, outcome.failed {
                        failedTools += 1
                        _ = try channel.send(command: .agentDiagnostic,
                            payload: JSONEncoder().encode(ProviderDiagnostic(provider: provider, outcome: outcome)))
                    }
                }
                try forward(stream.disconnected(now: ContinuousTime.now))
                return result(0, accepted: accepted, failedTools: failedTools, reason: "streamClosedNotCompletion")
            } catch {
                // Do not fabricate completion on truncation, rejection or loss.
                try? forward(stream.disconnected(now: ContinuousTime.now))
                return result(4, accepted: accepted, failedTools: failedTools, reason: "bridgeInterruptedOrRejected")
            }
        } catch {
            return result(2, accepted: 0, failedTools: 0, reason: "unsupportedProvider")
        }
    }

    private static func result(_ code: Int, accepted: Int, failedTools: Int, reason: String) -> CLIResult {
        let data = (try? JSONSerialization.data(withJSONObject: ["schemaVersion": 1,
            "command": "bridge", "acceptedEvents": accepted, "failedTools": failedTools,
            "reason": reason, "powerActuation": false], options: [.sortedKeys])) ?? Data()
        return CLIResult(json: String(decoding: data, as: UTF8.self), exitCode: code)
    }
}
