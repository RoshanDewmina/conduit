import Foundation

public struct Host: Identifiable, Codable, Hashable, Sendable {
    public let id: HostID
    public var name: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var authMethod: AuthMethod
    public var tags: [String]
    public var hostKeyFingerprint: String?  // SHA256 of host's public key, set on first connect
    public var preferredShell: String?
    public var tmuxSessionName: String?     // server-side tmux session to attach
    public var startupCommand: String?      // shell command run after connect (and tmux attach)
    public var autoResume: Bool             // attempt agent session resume on reconnect (Tier 1.4)
    public var createdAt: Date
    public var lastConnectedAt: Date?

    public enum AuthMethod: Codable, Hashable, Sendable {
        case password
        case ed25519(keyID: KeyID)
        case agent  // ssh-agent forwarding (M5+)
    }

    public init(
        id: HostID = .init(),
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .password,
        tags: [String] = [],
        hostKeyFingerprint: String? = nil,
        preferredShell: String? = nil,
        tmuxSessionName: String? = nil,
        startupCommand: String? = nil,
        autoResume: Bool = true,
        createdAt: Date = .now,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.tags = tags
        self.hostKeyFingerprint = hostKeyFingerprint
        self.preferredShell = preferredShell
        self.tmuxSessionName = tmuxSessionName
        self.startupCommand = startupCommand
        self.autoResume = autoResume
        self.createdAt = createdAt
        self.lastConnectedAt = lastConnectedAt
    }

    public var displayAddress: String { "\(username)@\(hostname):\(port)" }
}

#if DEBUG
public extension Host {
    static let sample = Host(
        name: "Dev Box",
        hostname: "dev.example.com",
        username: "ubuntu",
        tags: ["work"]
    )
}
#endif
