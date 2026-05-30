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

    var client: Citadel.SSHClient?

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
            client = try await withThrowingTimeout(Self.connectTimeout) {
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
        cachedCredential = nil
        cachedHostKeyStore = nil
    }

    /// Clears the cached credential without closing the connection.
    /// Call before a password-retry flow so the new password is accepted.
    public func clearCachedCredential() {
        cachedCredential = nil
        cachedHostKeyStore = nil
    }

    /// Marks the session as disconnected without closing the channel.
    /// Used by keepalive to signal a silently-dropped TCP link.
    public func markDisconnected() {
        isConnected = false
    }

    /// Probe liveness with a no-op remote command. Returns `false` and clears
    /// `isConnected` when the link is dead. Used by the keepalive loop and
    /// `SessionPool.heartbeat()`.
    ///
    /// Note: Citadel does not expose NIO's `ClientBootstrap` for TCP-level
    /// SO_KEEPALIVE configuration; this application-level probe provides the
    /// same dead-link detection.
    public func ping(timeout: Duration = .seconds(10)) async -> Bool {
        guard isConnected, client != nil else { return false }
        do {
            _ = try await withThrowingTimeout(timeout) {
                try await self.executeCollected(":")
            }
            return true
        } catch {
            isConnected = false
            return false
        }
    }

    // MARK: - Exec channel (one-shot command)

    /// Wrap a user command in a login shell invocation so that PATH, env, and
    /// shell profiles (`.zprofile`, `.bash_profile`) are sourced.
    ///
    /// Uses POSIX single-quote escaping so `$`, backticks, and `\` in the
    /// command are not interpreted by the outer shell.
    static func loginShellWrap(_ command: String) -> String {
        // POSIX single-quote escape: ' → '\''
        // Ends the current SQ string, inserts a backslash-quoted ', reopens SQ.
        let escaped = command.replacingOccurrences(of: "'", with: #"'\''"#)
        return "${SHELL:-/bin/sh} -lc '\(escaped)'"
    }

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

    /// Opens a PTY shell channel and returns the writer + the background task
    /// that keeps the channel alive. Call `task.cancel()` to close the shell.
    ///
    /// Data arriving from the remote PTY is fed into `dataContinuation`.
    /// Uses Citadel's `withPTY` API (requires macOS 15 / iOS 18+; our target is 26).
    public func requestShellChannel(
        width: Int,
        height: Int,
        dataContinuation: AsyncStream<[UInt8]>.Continuation
    ) async throws -> (writer: TTYStdinWriter, task: Task<Void, Never>) {
        guard let client else { throw ConduitError.notConnected }

        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: width,
            terminalRowHeight: height,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([:])
        )

        // Pass the writer out of the withPTY closure via an AsyncStream signal.
        let (writerStream, writerCont) = AsyncStream<TTYStdinWriter>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        let task = Task { [client] in
            do {
                try await client.withPTY(ptyRequest) { inbound, outbound in
                    writerCont.yield(outbound)
                    writerCont.finish()
                    for try await output in inbound {
                        if case .stdout(let buf) = output {
                            let bytes = Array(buf.readableBytesView)
                            if !bytes.isEmpty { dataContinuation.yield(bytes) }
                        }
                    }
                    dataContinuation.finish()
                }
            } catch {
                writerCont.finish()
                dataContinuation.finish()
            }
        }

        guard let writer = await writerStream.first(where: { _ in true }) else {
            task.cancel()
            throw ConduitError.channelClosed
        }
        return (writer, task)
    }

    // MARK: - Exec channel (bidirectional, no PTY — used by conduitd)

    /// Opens a raw exec channel for `command` and returns the stdin writer + the
    /// background task keeping it alive. Similar to `requestShellChannel` but
    /// without a PTY allocation, which is correct for daemon stdio protocols.
    public func requestExecChannel(
        command: String,
        dataContinuation: AsyncStream<[UInt8]>.Continuation
    ) async throws -> (writer: TTYStdinWriter, task: Task<Void, Never>) {
        guard let client else { throw ConduitError.notConnected }

        let (writerStream, writerCont) = AsyncStream<TTYStdinWriter>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        let task = Task { [client] in
            do {
                try await client.withExec(command) { inbound, outbound in
                    writerCont.yield(outbound)
                    writerCont.finish()
                    for try await output in inbound {
                        if case .stdout(let buf) = output {
                            let bytes = Array(buf.readableBytesView)
                            if !bytes.isEmpty { dataContinuation.yield(bytes) }
                        }
                    }
                    dataContinuation.finish()
                }
            } catch {
                writerCont.finish()
                dataContinuation.finish()
            }
        }

        guard let writer = await writerStream.first(where: { _ in true }) else {
            task.cancel()
            throw ConduitError.channelClosed
        }
        return (writer, task)
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

    // Internal so tests can exercise the mapping without going through connect().
    internal static func map(error: any Error, host: String) -> ConduitError {
        if let error = error as? ConduitError { return error }

        // Type-based catches for known Citadel/NIOSSH error types.
        if error is AuthenticationFailed {
            return .authFailed(reason: "Server rejected credentials")
        }
        if let clientErr = error as? SSHClientError {
            switch clientErr {
            case .allAuthenticationOptionsFailed:
                return .authFailed(reason: "All authentication methods failed")
            case .channelCreationFailed:
                return .channelClosed
            default:
                break
            }
        }
        if let citadelErr = error as? CitadelError {
            switch citadelErr {
            case .unauthorized:
                return .authFailed(reason: "Unauthorized")
            case .channelCreationFailed, .channelFailure:
                return .channelClosed
            default:
                break
            }
        }

        // Fallback: string inspection for errors without exposed types
        // (NIO transport errors, OS-level ECONNREFUSED, etc.)
        let msg = String(describing: error).lowercased()
        if msg.contains("connection refused")  { return .connectionRefused(host: host) }
        if msg.contains("timeout") || msg.contains("timed out") { return .timeout }
        if msg.contains("cancel")                              { return .cancelled }
        if msg.contains("channel")                             { return .channelClosed }
        return .unknown(detail: String(describing: error))
    }
}
