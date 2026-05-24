import Foundation
@preconcurrency import NIOCore
import NIOSSH
import ConduitCore

/// An actor that wraps a live PTY shell channel. Bytes received from the
/// remote PTY flow out through `bytes`; user input is delivered via
/// `send(_:)`; terminal size changes are reported with `resize(cols:rows:)`.
///
/// ## Opening a shell
/// ```swift
/// let shell = try await SSHShell.open(session: session, width: 80, height: 24)
/// for await chunk in shell.bytes { terminal.feed(chunk) }
/// ```
///
/// ## Platform note
/// The underlying Citadel PTY API (`withPTY`) requires iOS 18 / macOS 15.
/// On earlier targets `open` throws `ConduitError.unsupportedPlatform`.
///
/// TODO: wire Citadel shell channel for iOS 17 via NIOSSH directly.
public actor SSHShell {

    // MARK: - Stream plumbing

    private let (byteStream, byteContinuation): (AsyncStream<[UInt8]>, AsyncStream<[UInt8]>.Continuation)

    /// Async sequence of raw byte chunks arriving from the remote PTY.
    public var bytes: AsyncStream<[UInt8]> { byteStream }

    // MARK: - Channel handle

    /// The live NIO `Channel`; stored once the PTY handshake completes and
    /// used for send / resize operations.
    private var nioChannel: (any Channel)?

    // MARK: - Init

    /// Private — callers must use `SSHShell.open(session:width:height:)`.
    private init() {
        (byteStream, byteContinuation) = AsyncStream<[UInt8]>.makeStream()
    }

    // MARK: - Factory

    /// Open a PTY shell channel on an already-connected `SSHSession`.
    ///
    /// The method returns as soon as the PTY handshake is confirmed. Bytes
    /// arrive asynchronously on `shell.bytes` until the remote closes the
    /// channel or `close()` is called.
    ///
    /// - Throws: `ConduitError.notConnected` if the session is not live.
    /// - Throws: `ConduitError.unsupportedPlatform` on iOS 17 / macOS 14
    ///   (Citadel's `withPTY` requires iOS 18+).
    ///   TODO: wire Citadel shell channel for iOS 17 via NIOSSH directly.
    public static func open(
        session: SSHSession,
        width: Int,
        height: Int
    ) async throws -> SSHShell {
        guard await session.isConnected else {
            throw ConduitError.notConnected
        }

        // TODO: wire Citadel shell channel for iOS 17 via NIOSSH directly.
        // Citadel's withPTY / withTTY require macOS 15.0+ / iOS 18+.
        // For now we gate and surface a clear error so callers can handle it.
        throw ConduitError.unsupportedPlatform
    }

    // MARK: - Internal factory (for tests and future wiring)

    /// Creates an `SSHShell` driven by externally-supplied closures.
    /// Used by unit tests (via `MockSSHShell`) and by higher-level shell
    /// wrappers once the iOS 17 NIOSSH path is implemented.
    ///
    /// - Parameter setup: Called immediately with the stream `Continuation`
    ///   so the caller can feed bytes into the shell and register a channel.
    internal static func makeManual(
        setup: (AsyncStream<[UInt8]>.Continuation) -> Void
    ) -> SSHShell {
        let shell = SSHShell()
        setup(shell.byteContinuation)
        return shell
    }

    // MARK: - Channel storage (actor-isolated)

    /// Store a live NIO channel once the PTY handshake is confirmed.
    internal func storeChannel(_ channel: any Channel) {
        nioChannel = channel
    }

    // MARK: - Public operations

    /// Write raw bytes to the remote PTY's stdin.
    ///
    /// - Throws: `ConduitError.channelClosed` if no channel is live.
    public func send(_ bytes: [UInt8]) async throws {
        guard let ch = nioChannel else {
            throw ConduitError.channelClosed
        }
        var buf = ch.allocator.buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        try await ch.writeAndFlush(
            SSHChannelData(type: .channel, data: .byteBuffer(buf))
        )
    }

    /// Signal a window-size change to the remote PTY.
    ///
    /// - Throws: `ConduitError.channelClosed` if no channel is live.
    public func resize(cols: Int, rows: Int) async throws {
        guard let ch = nioChannel else {
            throw ConduitError.channelClosed
        }
        try await ch.triggerUserOutboundEvent(
            SSHChannelRequestEvent.WindowChangeRequest(
                terminalCharacterWidth: cols,
                terminalRowHeight: rows,
                terminalPixelWidth: 0,
                terminalPixelHeight: 0
            )
        )
    }

    /// Close the shell channel gracefully and finish the byte stream.
    public func close() async {
        try? await nioChannel?.close()
        nioChannel = nil
        byteContinuation.finish()
    }

    // MARK: - Feed (tests / internal mock wiring)

    /// Inject bytes directly into the shell's stream.
    /// Used by mock implementations and future NIOSSH bridge.
    internal func feedBytes(_ bytes: [UInt8]) {
        byteContinuation.yield(bytes)
    }

    /// Finish the byte stream (simulates remote channel close).
    internal func finishStream() {
        byteContinuation.finish()
    }
}
