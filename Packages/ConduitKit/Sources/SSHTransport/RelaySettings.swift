import Foundation

/// Single source of truth for the E2E relay endpoint the phone dials out to.
///
/// The default points at the hosted relay, but a self-hosted relay (e.g. a
/// `wss://<host>.<tailnet>.ts.net` URL) can be set from Settings or via the
/// `CONDUIT_RELAY_URL` build/launch override so the keyless QR pairing path can
/// be exercised against your own `push-backend` deployment.
public enum RelaySettings {

    // TODO: swap for wss://relay.conduit.dev once the production relay is deployed
    // (Task #6). Temporary: points at the hermes-box Tailscale Funnel relay so
    // pairing is zero-config — users never set this; the Settings override is for
    // self-hosters running their own relay.
    public static let defaultURLString = "wss://hermes-box.tail8c17ee.ts.net:8443"
    private static let overrideKey = "conduit.relayURL"

    /// The configured relay URL string (override → env → default).
    public static func urlString(defaults: UserDefaults = .standard) -> String {
        if let stored = defaults.string(forKey: overrideKey),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        if let env = ProcessInfo.processInfo.environment["CONDUIT_RELAY_URL"],
           !env.isEmpty {
            return env
        }
        return defaultURLString
    }

    /// The configured relay URL, falling back to the default if a stored value
    /// somehow fails to parse.
    public static func url(defaults: UserDefaults = .standard) -> URL {
        URL(string: urlString(defaults: defaults)) ?? URL(string: defaultURLString)!
    }

    /// Persist a user-supplied relay URL. Empty input clears the override and
    /// reverts to the default. Returns the normalized value that was stored.
    @discardableResult
    public static func setURLString(_ value: String, defaults: UserDefaults = .standard) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: overrideKey)
            return defaultURLString
        }
        defaults.set(trimmed, forKey: overrideKey)
        return trimmed
    }
}
