import Foundation
import TokenDeskCore

/// Stores only non-sensitive settings in an app-owned `UserDefaults` container.
@MainActor
public final class UserDefaultsSettingsPreferencesStore: SettingsPreferencesStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a preference store. Inject a suite in tests to avoid process-global state.
    public init(defaults: UserDefaults = .standard, key: String = "settings.preferences.v1") {
        self.defaults = defaults
        self.key = key
    }

    /// Restores a valid snapshot or privacy-preserving defaults after missing/corrupt data.
    public func load() -> SettingsPreferences {
        guard let data = defaults.data(forKey: key) else {
            return SettingsPreferences()
        }
        return (try? decoder.decode(SettingsPreferences.self, from: data))
            ?? SettingsPreferences()
    }

    /// Encodes the complete non-sensitive snapshot atomically through `UserDefaults`.
    public func save(_ preferences: SettingsPreferences) throws {
        defaults.set(try encoder.encode(preferences), forKey: key)
    }
}
