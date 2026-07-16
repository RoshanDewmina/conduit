#if os(iOS)
import Foundation
import LancerCore
import SSHTransport
import SecurityKit
import TerminalEngine

/// Observable SSH terminal session — pumps PTY bytes into SwiftTerm via
/// `TerminalFeedHandle` and forwards user input to the remote shell.
@MainActor
@Observable
public final class LiveTerminalModel {
    public enum Status: Equatable, Sendable {
        case connecting
        case connected
        case failed(String)
        case closed
    }

    public private(set) var status: Status = .connecting
    public private(set) var title: String
    public private(set) var pendingHostKeyFingerprint: String?

    /// Shared byte lancer consumed by the displayed `RawTerminalView`.
    public let feedHandle = TerminalFeedHandle()

    private let host: Host
    private let credentialProvider: @Sendable () async throws -> SSHCredential
    private let hostKeyStore: HostKeyStore
    private let autoTrustHostKey: Bool
    private let autoCommand: String?

    private var session: SSHSession?
    private var shell: SSHShell?
    private var pumpTask: Task<Void, Never>?
    private var started = false

    private var lastCols = 80
    private var lastRows = 24

    public init(
        host: Host,
        credentialProvider: @escaping @Sendable () async throws -> SSHCredential,
        hostKeyStore: HostKeyStore,
        autoTrustHostKey: Bool = false,
        autoCommand: String? = nil
    ) {
        self.host = host
        self.title = host.name
        self.credentialProvider = credentialProvider
        self.hostKeyStore = hostKeyStore
        self.autoTrustHostKey = autoTrustHostKey
        self.autoCommand = autoCommand
    }

    /// Connect, open a PTY shell, and start pumping bytes into SwiftTerm.
    public func start() async {
        guard !started else { return }
        started = true
        status = .connecting
        pendingHostKeyFingerprint = nil
        do {
            let session = SSHSession(host: host)
            let credential = try await credentialProvider()
            try await connect(session: session, credential: credential)
            let shell = try await SSHShell.open(session: session, width: lastCols, height: lastRows)
            self.session = session
            self.shell = shell
            try? await shell.resize(cols: lastCols, rows: lastRows)
            self.status = .connected

            if let autoCommand, !autoCommand.isEmpty {
                self.send(Array((autoCommand + "\n").utf8))
            }

            pumpTask = Task { [weak self, shell] in
                for await chunk in await shell.bytes {
                    self?.feedHandle.yield(chunk)
                }
                self?.status = .closed
            }
        } catch LancerError.hostKeyUnknown(let fingerprint) {
            pendingHostKeyFingerprint = fingerprint
            status = .connecting
            started = false
        } catch {
            let message = (error as? LancerError)?.errorDescription ?? error.localizedDescription
            status = .failed(message)
            started = false
        }
    }

    private func connect(session: SSHSession, credential: SSHCredential) async throws {
        #if DEBUG
        do {
            try await session.connect(credential: credential, hostKeyStore: hostKeyStore)
        } catch let LancerError.hostKeyUnknown(fingerprint) where autoTrustHostKey {
            try await hostKeyStore.record(hostID: host.id, fingerprint: fingerprint)
            try await session.connect(credential: credential, hostKeyStore: hostKeyStore)
        }
        #else
        try await session.connect(credential: credential, hostKeyStore: hostKeyStore)
        #endif
    }

    public func send(_ bytes: [UInt8]) {
        guard let shell else { return }
        Task { try? await shell.send(bytes) }
    }

    public func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        lastCols = cols
        lastRows = rows
        guard let shell else { return }
        Task { try? await shell.resize(cols: cols, rows: rows) }
    }

    public func stop() {
        pumpTask?.cancel()
        let shell = self.shell
        let session = self.session
        Task {
            await shell?.close()
            await session?.disconnect()
        }
    }

    public func trustHostKey() async {
        guard let fingerprint = pendingHostKeyFingerprint else { return }
        try? await hostKeyStore.record(hostID: host.id, fingerprint: fingerprint)
        pendingHostKeyFingerprint = nil
        await start()
    }

    public func rejectHostKey() {
        pendingHostKeyFingerprint = nil
        status = .failed("Host key not trusted")
        started = false
    }

    /// Convenience for debug harnesses: build a password-auth model from plain values.
    public static func passwordSession(
        name: String,
        hostname: String,
        port: Int,
        username: String,
        password: String,
        autoTrustHostKey: Bool = false,
        autoCommand: String? = nil
    ) -> LiveTerminalModel {
        let host = Host(name: name, hostname: hostname, port: port, username: username)
        return LiveTerminalModel(
            host: host,
            credentialProvider: { .password(password) },
            hostKeyStore: HostKeyStore(inMemory: true),
            autoTrustHostKey: autoTrustHostKey,
            autoCommand: autoCommand
        )
    }
}
#endif
