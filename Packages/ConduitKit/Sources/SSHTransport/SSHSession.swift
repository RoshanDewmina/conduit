import Foundation
@preconcurrency import Citadel
@preconcurrency import NIOCore
@preconcurrency import NIOSSH
import ConduitCore
import SecurityKit

/// An actor wrapping a single Citadel SSH client. One `SSHSession` is a
/// single multiplexed connection; many exec/shell channels may be opened
/// on it via `execute`, `executeCollected`.
///
/// All methods are actor-isolated. Streams returned by `execute` were built
/// inside the actor, so handing them to a caller is safe.
public actor SSHSession {
    public let host: ConduitCore.Host
    public private(set) var isConnected: Bool = false
    public private(set) var lastError: ConduitError?

    private var client: Citadel.SSHClient?

    /// The most-recently-used credential, cached for automatic reconnection.
    /// Set on every successful `connect(credential:hostKeyStore:)` call.
    private var cachedCredential: SSHCredential?
    private var cachedHostKeyStore: HostKeyStore?

    public init(host: ConduitCore.Host) {
        self.host = host
    }

    // MARK: - Connect / disconnect

    private static let connectTimeout: Duration = .seconds(15)

    public func connect(credential: SSHCredential, hostKeyStore: HostKeyStore) async throws {
        if isConnected { return }
        let method: SSHAuthenticationMethod = switch credential {
        case .password(let pw):
            .passwordBased(username: host.username, password: pw)
        case .ed25519(let key):
            .ed25519(username: host.username, privateKey: key)
        }
        let hostKeyValidator = TOFUHostKeyValidator(hostID: host.id, store: hostKeyStore)

        do {
            client = try await withThrowingTimeout(connectTimeout) {
                try await Citadel.SSHClient.connect(
                    host: self.host.hostname,
                    port: self.host.port,
                    authenticationMethod: method,
                    hostKeyValidator: .custom(hostKeyValidator),
                    reconnect: .never
                )
            }
            isConnected = true
            lastError = nil
            cachedCredential = credential
            cachedHostKeyStore = hostKeyStore
        } catch {
            let mapped = Self.map(error: error, host: host.hostname)
            lastError = mapped
            throw mapped
        }
    }

    /// Runs `operation` with a deadline. Throws `ConduitError.timeout` if it
    /// does not complete within `duration`.
    private func withThrowingTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw ConduitError.timeout
            }
            guard let result = try await group.next() else {
                throw ConduitError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    /// Re-establishes the SSH connection using the credentials from the most
    /// recent successful `connect(credential:hostKeyStore:)` call.
    ///
    /// - Throws: `ConduitError.unsupportedPlatform` when no cached credential
    ///   is available (e.g. the session was never successfully connected).
    public func attemptReconnect() async throws {
        // Guard: we must have previously connected successfully.
        guard let credential = cachedCredential,
              let hostKeyStore = cachedHostKeyStore else {
            // No cached credential — cannot reconnect automatically.
            // Callers should present the credential UI instead.
            throw ConduitError.unsupportedPlatform
        }
        // Reset state so connect() doesn't early-return.
        isConnected = false
        client = nil
        try await connect(credential: credential, hostKeyStore: hostKeyStore)
    }

    public func disconnect() async {
        if let client { try? await client.close() }
        client = nil
        isConnected = false
    }

    // MARK: - Exec channel (one-shot command)

    /// Stream stdout/stderr chunks from a remote command. Stream finishes
    /// when the remote process closes its channels.
    public func execute(_ command: String) async throws -> AsyncThrowingStream<(Data, BlockChunk.Stream), any Error> {
        guard let client else { throw ConduitError.notConnected }
        let cmdStream = try await client.executeCommandStream(command)

        let (stream, continuation) = AsyncThrowingStream<(Data, BlockChunk.Stream), any Error>.makeStream()
        let task = Task { [cmdStream] in
            do {
                for try await output in cmdStream {
                    try Task.checkCancellation()
                    switch output {
                    case .stdout(let buf):
                        continuation.yield((Data(buf.readableBytesView), .stdout))
                    case .stderr(let buf):
                        continuation.yield((Data(buf.readableBytesView), .stderr))
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Collect a command's full stdout into a String. Exit code is not
    /// surfaced here; `executeCommand` throws `SSHClient.CommandFailed`
    /// when the remote process returns a non-zero status.
    public func executeCollected(_ command: String) async throws -> String {
        guard let client else { throw ConduitError.notConnected }
        do {
            let buf = try await client.executeCommand(command)
            return String(data: Data(buf.readableBytesView), encoding: .utf8) ?? ""
        } catch {
            throw Self.map(error: error, host: host.hostname)
        }
    }

    // MARK: - Shell (interactive PTY)

    /// Opens a PTY shell channel on this SSH connection. Data arriving from the
    /// remote PTY is fed into `dataContinuation`. The returned NIO `Channel` is
    /// used for sending input and resize events.
    ///
    /// The data pump runs in a detached Task for the lifetime of the shell;
    /// when the remote closes the channel, `dataContinuation` is finished.
    ///
    /// Requires iOS 18+ (Citadel's shell API). Since we target iOS 26, this is
    /// always available.
    public func requestShellChannel(
        width: Int,
        height: Int,
        dataContinuation: AsyncStream<[UInt8]>.Continuation
    ) async throws -> any Channel {
        guard let client else { throw ConduitError.notConnected }

        let channel: any Channel = try await withCheckedThrowingContinuation { continuation in
            Task { [client] in
                do {
                    try await client.withTerminal(
                        term: "xterm-256color",
                        width: width,
                        height: height
                    ) { channel, inbound in
                        continuation.resume(returning: channel)
                        for try await var buffer in inbound {
                            if let bytes = buffer.readBytes(length: buffer.readableBytes), !bytes.isEmpty {
                                dataContinuation.yield(bytes)
                            }
                        }
                        dataContinuation.finish()
                    }
                } catch {
                    continuation.resume(throwing: Self.map(error: error, host: ""))
                }
            }
        }
        return channel
    }

    // MARK: - SFTP

    /// Opens an SFTP subsystem on the underlying SSH connection, executes `body`,
    /// and closes the subsystem when the closure returns (or throws).
    public func withSFTP<T: Sendable>(
        _ body: @escaping @Sendable (Citadel.SFTPClient) async throws -> T
    ) async throws -> T {
        guard let client else { throw ConduitError.notConnected }
        return try await client.withSFTP { sftp in
            try await body(sftp)
        }
    }

    // MARK: - Error mapping

    public nonisolated static func commandExitCode(from error: any Error) -> Int? {
        (error as? Citadel.SSHClient.CommandFailed)?.exitCode
    }

    private static func map(error: any Error, host: String) -> ConduitError {
        if let error = error as? ConduitError { return error }
        let msg = String(describing: error).lowercased()
        if msg.contains("connection refused")  { return .connectionRefused(host: host) }
        if msg.contains("authentication") || msg.contains("auth failed") {
            return .authFailed(reason: "Server rejected credentials")
        }
        if msg.contains("timeout") || msg.contains("timed out") { return .timeout }
        if msg.contains("cancel")                              { return .cancelled }
        if msg.contains("channel")                             { return .channelClosed }
        return .unknown(detail: String(describing: error))
    }
}
