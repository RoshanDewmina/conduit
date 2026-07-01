#if os(iOS)
import Foundation
import LancerCore

enum ObservedSessionsCache {
    private static let key = "lancer.observedSessions.cache"

    static func load() -> [ObservedSession]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([ObservedSession].self, from: data)
    }

    static func save(_ sessions: [ObservedSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
#endif