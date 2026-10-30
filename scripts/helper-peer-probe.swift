import Foundation

// Connects to the helper's Mach service WITHOUT the app's identity and asks for a read-only inspect.
// The helper pins its peer's code signature, so XPC must refuse this process: exit 0 means refused (good),
// exit 1 means the helper answered an unpinned peer (bad), exit 2 means no verdict (timeout). A missing helper
// also looks like "refused", so always run the app's `--helper-inspect` right before as the positive control.
// Build: swiftc scripts/helper-peer-probe.swift -o /tmp/helper-peer-probe
@objc protocol PowerHelperXPC {
    func perform(_ data: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}

final class Verdict: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    let done = DispatchSemaphore(value: 0)
    func set(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        guard value == nil else { return }
        value = text
        done.signal()
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return value ?? "no verdict" }
}

let verdict = Verdict()
let connection = NSXPCConnection(machServiceName: "com.camlid.power-helper", options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: PowerHelperXPC.self)
connection.invalidationHandler = { verdict.set("refused: connection invalidated") }
connection.interruptionHandler = { verdict.set("refused: connection interrupted") }
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    verdict.set("refused: \(error.localizedDescription)")
} as? PowerHelperXPC
proxy?.perform(Data(#"{"version":1,"operation":"inspect"}"#.utf8)) { data in
    verdict.set("ANSWERED: \(String(decoding: data.prefix(200), as: UTF8.self))")
}
_ = verdict.done.wait(timeout: .now() + 5)
let text = verdict.text
print("helper-peer-probe: \(text)")
exit(text.hasPrefix("refused") ? 0 : (text.hasPrefix("ANSWERED") ? 1 : 2))
