import Foundation

/// The preference calls the coordinator, the update controller and the skill installer make. `UserDefaults` conforms as
/// it is. Tests pass an in-memory store instead, so a test run never writes a preferences file (see `MemoryPreferences`).
public protocol PreferenceStore: AnyObject {
    func bool(forKey key: String) -> Bool
    func integer(forKey key: String) -> Int
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: PreferenceStore {}
