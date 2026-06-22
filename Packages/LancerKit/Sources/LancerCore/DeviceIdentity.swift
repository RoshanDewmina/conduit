import Foundation

/// The single stable per-install device/session identifier (MAJOR-8).
///
/// Previously ~4 call sites independently computed
/// `UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString`.
/// When `identifierForVendor` is nil (the boot window before first unlock — and
/// APNs registration can fire that early) each site invented a *different*
/// random UUID, so lancerd registered/polled under one id while the relay
/// POSTed decisions under another → the decision landed under a session key
/// lancerd never polled → silent 120 s timeout-deny, and APNs approvals never
/// reached the device.
///
/// This resolves one id *once* and persists it, so every site agrees for the
/// life of the install. In particular the `sessionID` sent in
/// `DaemonChannel.registerDevice` is guaranteed identical to the `sessionId` in
/// the `ApprovalRelay` decision POST body — the backend uses it as the
/// per-session token lookup key, so they MUST match (B2).
///
/// We deliberately do not derive from `identifierForVendor`: a freshly minted,
/// persisted UUID is *more* stable (IDFV resets when every vendor app is
/// uninstalled) and sidesteps the nil-at-boot race that caused the divergence.
public enum DeviceIdentity {
    private static let storageKey = "dev.lancer.stableDeviceSessionID"
    private static let lock = NSLock()

    /// The stable session id for this install. Generated + persisted on first
    /// access; the same value is returned for every subsequent call.
    public static func sessionID(defaults: UserDefaults = .standard) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: storageKey)
        return value
    }
}
