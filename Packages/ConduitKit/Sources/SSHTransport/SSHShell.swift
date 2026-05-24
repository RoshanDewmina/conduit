import Foundation
@preconcurrency import Citadel
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
/// The underlying Citadel PTY API requires iOS 18+ / macOS 15+.
/// Since Conduit targets iOS 26, this is always available.
public actor SSHShell {

    // MARK: - Stream plumbing

    internal let (byteStream, byteContinuation): (AsyncStream<[UInt8]>, AsyncStream<[UInt8]>.Continuation)

    /// Async sequence of raw byte chunks arriving from the remote PTY.
    public var bytes: AsyncStream<[UInt8]> { byteStream }

    // MARK: - Channel handles

    /// PTY writer for the live shell (set by `storeWriter(_:task:)`).
    private var ptyWriter: TTYStdinWriter?
    /// Background task keeping the withPTY closure alive; cancelled on close().
    private var ptyTask: Task<Void, Never>?
    /// NIO channel — only used by the test / mock path via `storeChannel(_:)`.
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
    public static func open(
        session: SSHSession,
        width: Int,
        height: Int
    ) async throws -> SSHShell {
        guard await session.isConnected else {
            throw ConduitError.notConnected
        }

        let shell = SSHShell()
        let continuation = shell.byteContinuation

        let (writer, task) = try await session.requestShellChannel(
            width: width,
            height: height,
            dataContinuation: continuation
        )
        await shell.storeWriter(writer, task: task)
        return shell
    }

    // MARK: - Internal factory (for tests)

    /// Creates an `SSHShell` driven by externally-supplied closures.
    /// Used by unit tests (via `MockSSHShell`).
    internal static func makeManual(
        setup: (AsyncStream<[UInt8]>.Continuation) -> Void
    ) -> SSHShell {
        let shell = SSHShell()
        setup(shell.byteContinuation)
        return shell
    }

    // MARK: - Storage (actor-isolated)

    /// Store a live PTY writer + background task once the PTY handshake is confirmed.
    internal func storeWriter(_ writer: TTYStdinWriter, task: Task<Void, Never>) {
        ptyWriter = writer
        ptyTask = task
    }

    /// Store a raw NIO channel — used by the test / manual path only.
    internal func storeChannel(_ channel: any Channel) {
        nioChannel = channel
    }

    // MARK: - Public operations

    /// Write raw bytes to the remote PTY's stdin.
    public func send(_ bytes: [UInt8]) async throws {
        if let w = ptyWriter {
            let buf = ByteBuffer(bytes: bytes)
            try await w.write(buf)
        } else if let ch = nioChannel {
            var buf = ch.allocator.buffer(capacity: bytes.count)
            buf.writeBytes(bytes)
            try await ch.writeAndFlush(
                SSHChannelData(type: .channel, data: .byteBuffer(buf))
            )
        } else {
            throw ConduitError.channelClosed
        }
    }

    /// Signal a window-size change to the remote PTY.
    public func resize(cols: Int, rows: Int) async throws {
        if let w = ptyWriter {
            try await w.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
        } else if let ch = nioChannel {
            try await ch.triggerUserOutboundEvent(
                SSHChannelRequestEvent.WindowChangeRequest(
                    terminalCharacterWidth: cols,
                    terminalRowHeight: rows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0
                )
            )
        } else {
            throw ConduitError.channelClosed
        }
    }

    /// Close the shell channel gracefully and finish the byte stream.
    public func close() async {
        ptyTask?.cancel()
        ptyTask = nil
        ptyWriter = nil
        try? await nioChannel?.close()
        nioChannel = nil
        byteContinuation.finish()
    }

    // MARK: - Feed (tests / internal mock wiring)

    /// Inject bytes directly into the shell's stream.
    internal func feedBytes(_ bytes: [UInt8]) {
        byteContinuation.yield(bytes)
    }

    /// Finish the byte stream (simulates remote channel close).
    internal func finishStream() {
        byteContinuation.finish()
    }
}
