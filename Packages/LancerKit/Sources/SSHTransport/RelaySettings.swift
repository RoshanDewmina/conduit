import Foundation

/// Single source of truth for the E2E relay endpoint the phone dials out to.
///
/// The default points at the hosted relay, but a self-hosted relay (e.g. a
/// `wss://<host>.<tailnet>.ts.net` URL) can be set from Settings or via the
/// `LANCER_RELAY_URL` build/launch override so the keyless QR pairing path can
/// be exercised against your own `push-backend` deployment.
public enum RelaySettings {

    // The live hosted relay (Cloud Run) — the same push-backend service the app
    // targets via LANCER_PUSH_BACKEND_URL (push-backend doubles as the blind
    // /ws/relay). Pairing is zero-config: the daemon's `lancerd pair` defaults to
    // this same host (see relay_install_helper.go), so phone + daemon rendezvous
    // out of the box. Users never set this; the Settings override is for
    // self-hosters running their own relay.
    public static let defaultURLString = "wss://conduit-push-y4wpy6zeva-ts.a.run.app"

    // Legacy key for a user-set relay override. The override is no longer
    // honored or settable from the UI — the endpoint is fixed to the hosted
    // relay in V1. We still clear the key on read so a stale value saved by an
    // older build (e.g. a dead self-host URL) can't strand a device on a relay
    // the daemon isn't on. Self-hosters use the LANCER_RELAY_URL env override.
    private static let legacyOverrideKey = "lancer.relayURL"

    /// The relay URL string (env override → default). Users never set this.
    public static func urlString(defaults: UserDefaults = .standard) -> String {
        if defaults.object(forKey: legacyOverrideKey) != nil {
            defaults.removeObject(forKey: legacyOverrideKey)
        }
        if let env = ProcessInfo.processInfo.environment["LANCER_RELAY_URL"],
           !env.isEmpty,
           let parsed = URL(string: env),
           let scheme = parsed.scheme?.lowercased(), scheme == "ws" || scheme == "wss",
           parsed.host?.isEmpty == false {
            return env
        }
        // Invalid or non-ws(s) override → fail-safe to the hosted default rather
        // than stranding the device on an unusable endpoint (BUILD-2).
        return defaultURLString
    }

    /// The configured relay URL, falling back to the default if the value
    /// somehow fails to parse.
    public static func url(defaults: UserDefaults = .standard) -> URL {
        URL(string: urlString(defaults: defaults)) ?? URL(string: defaultURLString)!
    }
}
