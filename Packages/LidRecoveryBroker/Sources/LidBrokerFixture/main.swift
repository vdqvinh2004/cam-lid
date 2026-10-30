import Foundation
import Darwin
import LidRecoveryBroker

// Test-only client: no helpers, registration, power APIs or foreign-process control.
do {
    let args = CommandLine.arguments
    guard args.count == 5 || (args.count == 4 && args[3] == "stream") else { exit(64) }
    let pin = try CodeIdentityPin(cdhash: args[2])
    if args.count == 4 {
        while let line = readLine() {
            let request = try JSONDecoder().decode(BrokerRequest.self, from: Data(line.utf8))
            let reply = try BrokerConnection.exchange(path: args[1], serverPin: pin, request: request)
            var output = try JSONEncoder().encode(reply)
            output.append(10)
            try FileHandle.standardOutput.write(contentsOf: output)
        }
    } else {
        let request = try JSONDecoder().decode(BrokerRequest.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
        let reply = try BrokerConnection.exchange(path: args[1], serverPin: pin, request: request)
        try JSONEncoder().encode(reply).write(to: URL(fileURLWithPath: args[4]), options: .atomic)
    }
    exit(0)
} catch {
    fputs("fixture: \(error)\n", stderr)
    exit(3)
}
