#if os(iOS)
import Foundation
import LancerCore

enum ObservedSessionsCache {
    private static let key = "lancer.observedSessions.cache"
    private static let byHostKey = "lancer.observedSessions.byHost.cache"

    static func load() -> [ObservedSession]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([ObservedSession].self, from: data)
    }

    static func save(_ sessions: [ObservedSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Per-host variant — Home now fans out `loadSessions(host:)` across every
    /// live machine rather than a single implicit "the" live host, so the
    /// cold-start cache needs to be keyed the same way.
    static func loadByHost() -> [String: [ObservedSession]]? {
        guard let data = UserDefaults.standard.data(forKey: byHostKey) else { return nil }
        return try? JSONDecoder().decode([String: [ObservedSession]].self, from: data)
    }

    static func saveByHost(_ sessionsByHost: [String: [ObservedSession]]) {
        guard let data = try? JSONEncoder().encode(sessionsByHost) else { return }
        UserDefaults.standard.set(data, forKey: byHostKey)
    }
}
#endif