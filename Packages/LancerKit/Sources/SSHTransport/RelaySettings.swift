import Foundation

/// Single source of truth for the E2E relay endpoint the phone dials out to.
///
/// The default points at the hosted relay, but a self-hosted relay (e.g. a
/// `wss://<host>.<tailnet>.ts.net` URL) can be set from Settings or via the
/// `LANCER_RELAY_URL` build/launch override so the keyless QR pairing path can
/// be exercised against your own `push-backend` deployment.
public enum RelaySettings {

    /// The retired hosted endpoint. It is kept only as an exact-match migration
    /// sentinel; lookalike and self-hosted URLs must never be rewritten.
    public static let retiredHostedURLString = "wss://conduit-push-y4wpy6zeva-ts.a.run.app"

    // The live hosted relay (Fly.io) — the same push-backend service the app
    // targets via LANCER_PUSH_BACKEND_URL (push-backend doubles as the blind
    // /ws/relay). Pairing is zero-config: the daemon's `lancerd pair` defaults to
    // this same host (see relay_install_helper.go), so phone + daemon rendezvous
    // out of the box. Users never set this; the Settings override is for
    // self-hosters running their own relay.
    public static let defaultURLString = "wss://conduit-push.fly.dev"

    /// Canonicalizes only the retired first-party endpoint. This deliberately
    /// uses string equality so custom relays and lookalike hostnames are left
    /// untouched.
    static func migrateRetiredHostedURL(_ value: String) -> String {
        value == retiredHostedURLString ? defaultURLString : value
    }

    // Legacy key for a user-set relay override. The override is no longer
    // honored or settable from the UI — the endpoint is fixed to the hosted
    // relay in V1. We still clear the key on read so a stale value saved by an
    // older build (e.g. a dead self-host URL) can't strand a device on a relay
    // the daemon isn't on. Self-hosters use the LANCER_RELAY_URL env override.
    private static let legacyOverrideKey = "lancer.relayURL"

#if DEBUG
    // DEBUG-only persisted relay override. `LANCER_RELAY_URL` only lives as
    // long as the specific process a debug tool (Xcode, devicectl) launched
    // with that env var — a normal Home Screen tap launches a fresh process
    // with no env var, silently falling back to the hosted default. Remembering
    // the last env-var value here means a self-hosted relay chosen once (e.g.
    // for a testing session) keeps working across ordinary launches too. Never
    // compiled into a release build, so this can't affect real users — the
    // "users never set this" invariant below still holds for shipped builds.
    private static let debugPersistedOverrideKey = "lancer.debug.relayURL"
#endif

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
            let migrated = migrateRetiredHostedURL(env)
#if DEBUG
            defaults.set(migrated, forKey: debugPersistedOverrideKey)
#endif
            return migrated
        }
#if DEBUG
        if let stored = defaults.string(forKey: debugPersistedOverrideKey),
           !stored.isEmpty,
           let parsed = URL(string: stored),
           let scheme = parsed.scheme?.lowercased(), scheme == "ws" || scheme == "wss",
           parsed.host?.isEmpty == false {
            let migrated = migrateRetiredHostedURL(stored)
            if migrated != stored {
                defaults.set(migrated, forKey: debugPersistedOverrideKey)
            }
            return migrated
        }
#endif
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
