import Foundation
@testable import CamLidApp

/// An in-memory `PreferenceStore` for tests. Nothing reaches the preference daemon, so a test run writes no preferences
/// file. (`UserDefaults(suiteName:)` writes one, and the daemon can recreate it a few seconds after it is removed.)
final class MemoryPreferences: PreferenceStore {
    private var values: [String: Any] = [:]

    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func string(forKey key: String) -> String? { values[key] as? String }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}
