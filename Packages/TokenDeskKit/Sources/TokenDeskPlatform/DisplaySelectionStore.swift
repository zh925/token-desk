import Foundation

@MainActor
protocol DisplaySelectionStoring: AnyObject {
    func load() -> DisplayFingerprint?
    func save(_ fingerprint: DisplayFingerprint?)
}

@MainActor
final class UserDefaultsDisplaySelectionStore: DisplaySelectionStoring {
    private static let key = "display.selectedFingerprint.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DisplayFingerprint? {
        guard let data = defaults.data(forKey: Self.key) else {
            return nil
        }
        return try? decoder.decode(DisplayFingerprint.self, from: data)
    }

    func save(_ fingerprint: DisplayFingerprint?) {
        guard let fingerprint, let data = try? encoder.encode(fingerprint) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}
