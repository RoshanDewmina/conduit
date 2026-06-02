import Foundation
import ConduitCore

/// A process-wide pool of active SSHSessions keyed by `HostID`. Callers
/// `attach(host:)` to get the existing session or create a new one. Each
/// session is one transport (TCP/TLS handshake); per-command exec channels
/// multiplex internally.
public actor SessionPool {
    public static let shared = SessionPool()

    private var sessions: [HostID: SSHSession] = [:]

    public init() {}

    /// Return the cached session for this host if any, regardless of state.
    public func existing(hostID: HostID) -> SSHSession? { sessions[hostID] }

    /// Get or create a session for `host`. Connection is the caller's
    /// responsibility because credential acquisition (Keychain unlock,
    /// biometric prompt) cannot live in the engine layer.
    public func session(for host: ConduitCore.Host) -> SSHSession {
        if let existing = sessions[host.id] { return existing }
        let session = SSHSession(host: host)
        sessions[host.id] = session
        return session
    }

    public func disconnect(hostID: HostID) async {
        if let s = sessions[hostID] { await s.disconnect() }
        sessions.removeValue(forKey: hostID)
    }

    public func disconnectAll() async {
        for s in sessions.values { await s.disconnect() }
        sessions.removeAll()
    }

    public var activeCount: Int { sessions.count }

    /// Returns the set of host IDs whose sessions are currently connected.
    public func connectedHostIDs() async -> Set<HostID> {
        var result = Set<HostID>()
        for (id, session) in sessions {
            if await session.isConnected { result.insert(id) }
        }
        return result
    }

    /// Ping every pooled session. Sessions whose TCP link is silently dead have
    /// their `isConnected` flag cleared so callers get accurate status.
    public func heartbeat() async {
        for session in sessions.values {
            _ = await session.ping()
        }
    }
}
