import Foundation

public enum DeepLinkRoute: Equatable, Sendable {
    case billing(returnURL: URL)
    case authCallback(URL)

    public static func parse(_ url: URL) -> DeepLinkRoute? {
        guard url.scheme == "lancer", let host = url.host else { return nil }

        let path = normalizedPath(url.path)

        // SEC-1: exact-path allowlist per host — reject smuggled path segments
        // (e.g. lancer://auth/evil) while still permitting query/fragment tokens.
        switch host {
        case "auth":
            guard path == "/" || path == "/callback" else { return nil }
            return .authCallback(url)
        case "billing":
            guard path == "/" || path == "/complete" else { return nil }
            return .billing(returnURL: url)
        default:
            return nil
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }

    public static func == (lhs: DeepLinkRoute, rhs: DeepLinkRoute) -> Bool {
        switch (lhs, rhs) {
        case (.billing(let l), .billing(let r)):
            l.absoluteString == r.absoluteString
        case (.authCallback(let l), .authCallback(let r)):
            l.absoluteString == r.absoluteString
        default:
            false
        }
    }
}
