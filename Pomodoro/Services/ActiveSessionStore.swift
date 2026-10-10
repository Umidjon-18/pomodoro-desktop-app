import Foundation

/// Snapshot of the running session, persisted as JSON in UserDefaults so a crash or
/// forced quit can be recorded on the next launch.
struct ActiveSessionStore: Codable, Equatable {
    static let defaultsKey = "activeSession"

    var startDate: Date
    var endDate: Date
    var plannedMinutes: Int
    var sessionAllowedBundleIDs: Set<String>

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> ActiveSessionStore? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ActiveSessionStore.self, from: data)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
