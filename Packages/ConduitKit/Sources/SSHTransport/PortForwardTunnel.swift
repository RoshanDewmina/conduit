#if canImport(Network)
import Foundation
import Network
@preconcurrency import NIOCore
@preconcurrency import NIOSSH
@preconcurrency import Citadel
import ConduitCore

// MARK: - Thread-safe value box (avoids NIOConcurrencyHelpers dep)

private final class Protected<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()
    init(_ value: T) { _value = value }
    @discardableResult
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&_value)
    }
}

// MARK: - Tunnel protocol

public protocol PortForwardTunnel: Sendable {
    var forward: PortForward { get }
    var isActive: Bool { get }
    func stop() async
}

// MARK: - Local forward (localhost:localPort → remoteHost:remotePort via SSH)

public final class LocalPortForwardTunnel: PortForwardTunnel, @unchecked Sendable {
    public let forward: PortForward
    public private(set) var isActive: Bool = false

    private var listener: NWListener?
    private let connections = Protected<[NWConnection]>([])
    private weak var sshSession: SSHSession?

    init(sshSession: SSHSession, forward: PortForward) {
        self.sshSession = sshSession
        self.forward = forward
    }

    func start() async throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let port = NWEndpoint.Port(rawValue: UInt16(clamping: forward.localPort)) ?? .any
        let l = try NWListener(using: params, on: port)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            let resumed = Protected<Bool>(false)
            l.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isActive = true
                    resumed.withLock { done in
                        if !done { done = true; cont.resume() }
                    }
                case .failed(let err):
                    resumed.withLock { done in
                        if !done { done = true; cont.resume(throwing: err) }
                    }
                case .cancelled:
                    self.isActive = false
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] nwConn in
                guard let self else { nwConn.cancel(); return }
                Task { await self.bridge(nwConn) }
            }
            l.start(queue: .global(qos: .utility))
            self.listener = l
        }
    }

    private func bridge(_ nwConn: NWConnection) async {
        guard let session = sshSession else { nwConn.cancel(); return }
        nwConn.start(queue: .global(qos: .utility))
        connections.withLock { $0.append(nwConn) }
        defer {
            connections.withLock { $0.removeAll { $0 === nwConn } }
            nwConn.cancel()
        }
        do {
            let stream = try await session.openDirectTCPIPStream(
                remoteHost: forward.remoteHost,
                remotePort: forward.remotePort
            )
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await Self.pumpNWToSSH(nwConn, sshChannel: stream.channel) }
                group.addTask { await Self.pumpSSHToNW(stream, nw: nwConn) }
            }
        } catch {}
    }

    private static func pumpNWToSSH(_ nw: NWConnection, sshChannel: any Channel) async {
        let alloc = ByteBufferAllocator()
        while true {
            let data: Data? = await withCheckedContinuation { cont in
                nw.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, _ in
                    cont.resume(returning: (isComplete || data == nil) ? nil : data)
                }
            }
            guard let bytes = data, !bytes.isEmpty else { break }
            var buf = alloc.buffer(capacity: bytes.count)
            buf.writeBytes(bytes)
            do { try await sshChannel.writeAndFlush(buf).get() } catch { break }
        }
        try? await sshChannel.close().get()
    }

    private static func pumpSSHToNW(_ stream: DirectTCPIPStream, nw: NWConnection) async {
        for await var buf in stream.inboundStream {
            guard let bytes = buf.readBytes(length: buf.readableBytes), !bytes.isEmpty else { continue }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                nw.send(content: Data(bytes), completion: .contentProcessed { _ in cont.resume() })
            }
        }
        nw.cancel()
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        let all = connections.withLock { conns -> [NWConnection] in
            let copy = conns; conns.removeAll(); return copy
        }
        all.forEach { $0.cancel() }
        isActive = false
    }
}

// MARK: - Inbound stream wrapper for directTCPIP channel

final class DirectTCPIPStream: @unchecked Sendable {
    let channel: any Channel
    let inboundStream: AsyncStream<ByteBuffer>
    private let continuation: AsyncStream<ByteBuffer>.Continuation

    init(channel: any Channel) {
        self.channel = channel
        var cont: AsyncStream<ByteBuffer>.Continuation!
        self.inboundStream = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func yield(_ buf: ByteBuffer) { continuation.yield(buf) }
    func finish() { continuation.finish() }
}

private final class DirectTCPIPInboundHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let stream: DirectTCPIPStream
    init(stream: DirectTCPIPStream) { self.stream = stream }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) { stream.yield(unwrapInboundIn(data)) }
    func channelInactive(context: ChannelHandlerContext) { stream.finish() }
    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        stream.finish(); context.close(promise: nil)
    }
}

// MARK: - SSHSession extensions

extension SSHSession {
    public func startLocalPortForward(_ forward: PortForward) async throws -> LocalPortForwardTunnel {
        let tunnel = LocalPortForwardTunnel(sshSession: self, forward: forward)
        try await tunnel.start()
        return tunnel
    }

    func openDirectTCPIPStream(remoteHost: String, remotePort: Int) async throws -> DirectTCPIPStream {
        guard let c = client else { throw ConduitError.notConnected }
        let originatorAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
        let settings = SSHChannelType.DirectTCPIP(
            targetHost: remoteHost,
            targetPort: remotePort,
            originatorAddress: originatorAddress
        )
        var streamRef: DirectTCPIPStream?
        let channel = try await c.createDirectTCPIPChannel(using: settings) { channel in
            let stream = DirectTCPIPStream(channel: channel)
            streamRef = stream
            return channel.pipeline.addHandler(DirectTCPIPInboundHandler(stream: stream))
        }
        guard let stream = streamRef else {
            try? await channel.close().get()
            throw ConduitError.channelClosed
        }
        return stream
    }
}
#endif
