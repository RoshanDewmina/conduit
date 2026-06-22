import Darwin
import Foundation
import Testing
import LancerCore
@testable import HostControlKit

/// Minimal fake `lancerd` speaking the same JSON-RPC-over-framed-Unix-socket
/// wire protocol as the real daemon, for exercising `HostServiceClient`
/// without a live `lancerd` process.
// ponytail: test-only fixture. Coordinates raw fds between this fake-server
// task and the client under test via a deliberate accept-then-respond
// rendezvous (never mutated concurrently in practice) — @unchecked Sendable
// rather than threading an actor through a Unix-socket accept loop.
private final class FakeDaemonServer: @unchecked Sendable {
    let socketPath: String
    private(set) var listenFD: Int32 = -1

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() throws {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw TestSetupError.socket("socket() failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw TestSetupError.socket("path too long")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            let buf = rawPtr.bindMemory(to: UInt8.self)
            for (i, byte) in pathBytes.enumerated() { buf[i] = byte }
            buf[pathBytes.count] = 0
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw TestSetupError.socket("bind() failed: \(String(cString: strerror(errno)))") }
        guard listen(fd, 1) == 0 else { throw TestSetupError.socket("listen() failed") }

        listenFD = fd
    }

    func stop() {
        if listenFD >= 0 { close(listenFD) }
        unlink(socketPath)
    }

    /// Accepts exactly one connection, reads one framed JSON-RPC request,
    /// and returns it alongside the connection fd so the test can assert on
    /// the request and choose what to write back.
    func acceptOneRequest() throws -> (connFD: Int32, requestJSON: [String: Any]) {
        let connFD = accept(listenFD, nil, nil)
        guard connFD >= 0 else { throw TestSetupError.socket("accept() failed") }

        let frameData = try Self.readFramedBlocking(fd: connFD)
        guard let json = (try? JSONSerialization.jsonObject(with: frameData)) as? [String: Any] else {
            throw TestSetupError.socket("failed to parse request JSON")
        }
        return (connFD, json)
    }

    /// Accepts a connection, services the `hello` handshake with a default
    /// success reply, and returns the connFD plus the *next* framed request
    /// (the test's actual method call) for the caller to assert on/respond
    /// to — mirrors `acceptOneRequest()`'s shape but with the handshake
    /// already out of the way.
    func acceptHandshakeThenOneRequest(
        protocolVersion: Int = 1,
        serviceVersion: String = "test-1.0"
    ) throws -> (connFD: Int32, requestJSON: [String: Any]) {
        let connFD = accept(listenFD, nil, nil)
        guard connFD >= 0 else { throw TestSetupError.socket("accept() failed") }

        try respondToHandshake(connFD: connFD, server: self, protocolVersion: protocolVersion, serviceVersion: serviceVersion)

        let frameData = try Self.readFramedBlocking(fd: connFD)
        guard let json = (try? JSONSerialization.jsonObject(with: frameData)) as? [String: Any] else {
            throw TestSetupError.socket("failed to parse request JSON")
        }
        return (connFD, json)
    }

    /// Reads the raw bytes of exactly one frame (4-byte BE length + payload)
    /// directly off the socket — used both to drive the fake server and, in
    /// the dedicated framing test, to assert on exact wire bytes.
    static func readFramedBlocking(fd: Int32) throws -> Data {
        var buffer = Data()
        while buffer.count < 4 {
            buffer.append(try readSomeBlocking(fd: fd, upTo: 4 - buffer.count))
        }
        if let (payload, _) = DaemonFraming.unframe(buffer) {
            return payload
        }
        let lengthBytes = buffer.prefix(4)
        let len = (UInt32(lengthBytes[lengthBytes.startIndex]) << 24)
            | (UInt32(lengthBytes[lengthBytes.startIndex + 1]) << 16)
            | (UInt32(lengthBytes[lengthBytes.startIndex + 2]) << 8)
            | UInt32(lengthBytes[lengthBytes.startIndex + 3])
        let needed = 4 + Int(len)
        while buffer.count < needed {
            buffer.append(try readSomeBlocking(fd: fd, upTo: needed - buffer.count))
        }
        guard let (payload, _) = DaemonFraming.unframe(buffer) else {
            throw TestSetupError.socket("failed to unframe")
        }
        return payload
    }

    /// Reads the raw framed bytes (length prefix included) of exactly one
    /// frame — for the test that asserts the wire format itself.
    static func readRawFrameBlocking(fd: Int32) throws -> Data {
        var buffer = Data()
        while buffer.count < 4 {
            buffer.append(try readSomeBlocking(fd: fd, upTo: 4 - buffer.count))
        }
        let lengthBytes = buffer.prefix(4)
        let len = (UInt32(lengthBytes[lengthBytes.startIndex]) << 24)
            | (UInt32(lengthBytes[lengthBytes.startIndex + 1]) << 16)
            | (UInt32(lengthBytes[lengthBytes.startIndex + 2]) << 8)
            | UInt32(lengthBytes[lengthBytes.startIndex + 3])
        let needed = 4 + Int(len)
        while buffer.count < needed {
            buffer.append(try readSomeBlocking(fd: fd, upTo: needed - buffer.count))
        }
        return buffer
    }

    static func writeFramedBlocking(fd: Int32, json: Data) throws {
        let framed = DaemonFraming.frame(json)
        var remaining = framed
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { rawPtr -> Int in
                Darwin.write(fd, rawPtr.baseAddress, remaining.count)
            }
            guard written > 0 else { throw TestSetupError.socket("write() failed") }
            remaining = remaining.dropFirst(written)
        }
    }

    private static func readSomeBlocking(fd: Int32, upTo maxLength: Int) throws -> Data {
        var tempBuffer = [UInt8](repeating: 0, count: max(maxLength, 1))
        let bytesRead = tempBuffer.withUnsafeMutableBytes { rawPtr -> Int in
            Darwin.read(fd, rawPtr.baseAddress, rawPtr.count)
        }
        guard bytesRead > 0 else { throw TestSetupError.socket("read() failed or EOF") }
        return Data(tempBuffer[0..<bytesRead])
    }

    enum TestSetupError: Error {
        case socket(String)
    }
}

private func makeTempSocketPath() -> String {
    // `sockaddr_un.sun_path` is only 104 bytes on Darwin; NSTemporaryDirectory()
    // (under /var/folders/.../T/) plus a UUID-based name routinely overflows
    // that. /tmp is short and POSIX-guaranteed, keeping us well under the limit.
    let shortID = UUID().uuidString.prefix(8)
    return "/tmp/hck-\(shortID).sock"
}

private let testToken = "deadbeefcafef00d"

/// Reads and asserts on the `hello` handshake request, then writes back a
/// success response. Returns the parsed `hello` request JSON for tests that
/// want to assert on its contents.
@discardableResult
private func respondToHandshake(
    connFD: Int32,
    server: FakeDaemonServer,
    protocolVersion: Int = 1,
    serviceVersion: String = "test-1.0"
) throws -> [String: Any] {
    let helloJSON = (try? JSONSerialization.jsonObject(
        with: FakeDaemonServer.readFramedBlocking(fd: connFD)
    )) as? [String: Any]
    guard let helloJSON else {
        throw FakeDaemonServer.TestSetupError.socket("failed to parse hello request")
    }
    let id = helloJSON["id"] as? Int
    let response = try JSONSerialization.data(withJSONObject: [
        "jsonrpc": "2.0",
        "id": id as Any,
        "result": ["protocolVersion": protocolVersion, "serviceVersion": serviceVersion],
    ])
    try FakeDaemonServer.writeFramedBlocking(fd: connFD, json: response)
    return helloJSON
}

/// Same as `respondToHandshake` but replies with a JSON-RPC `error` instead
/// of a success result — for the rejection-path tests.
private func respondToHandshakeWithError(connFD: Int32, code: Int, message: String) throws -> [String: Any] {
    let helloJSON = (try? JSONSerialization.jsonObject(
        with: FakeDaemonServer.readFramedBlocking(fd: connFD)
    )) as? [String: Any]
    guard let helloJSON else {
        throw FakeDaemonServer.TestSetupError.socket("failed to parse hello request")
    }
    let id = helloJSON["id"] as? Int
    let response = try JSONSerialization.data(withJSONObject: [
        "jsonrpc": "2.0",
        "id": id as Any,
        "error": ["code": code, "message": message],
    ])
    try FakeDaemonServer.writeFramedBlocking(fd: connFD, json: response)
    return helloJSON
}

@Suite("HostServiceClient")
struct HostServiceClientTests {
    @Test("ping round-trips and returns pong")
    func pingRoundTrip() async throws {
        let socketPath = makeTempSocketPath()
        let server = FakeDaemonServer(socketPath: socketPath)
        try server.start()
        defer { server.stop() }

        let serverTask = Task {
            let (connFD, request) = try server.acceptHandshakeThenOneRequest()
            defer { close(connFD) }
            #expect(request["method"] as? String == "ping")
            #expect(request["jsonrpc"] as? String == "2.0")
            let id = request["id"] as? Int
            let response = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "id": id as Any,
                "result": "pong",
            ])
            try FakeDaemonServer.writeFramedBlocking(fd: connFD, json: response)
        }

        let client = HostServiceClient(socketPathOverride: socketPath, tokenOverride: testToken)
        try await client.connect()
        let result = try await client.ping()
        #expect(result == "pong")

        try await serverTask.value
    }

    @Test("JSON-RPC error response throws HostServiceError.rpc with code and message")
    func errorResponseThrows() async throws {
        let socketPath = makeTempSocketPath()
        let server = FakeDaemonServer(socketPath: socketPath)
        try server.start()
        defer { server.stop() }

        let serverTask = Task {
            let (connFD, request) = try server.acceptHandshakeThenOneRequest()
            defer { close(connFD) }
            let id = request["id"] as? Int
            let response = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "id": id as Any,
                "error": ["code": -32601, "message": "method not found"],
            ])
            try FakeDaemonServer.writeFramedBlocking(fd: connFD, json: response)
        }

        let client = HostServiceClient(socketPathOverride: socketPath, tokenOverride: testToken)
        try await client.connect()

        await #expect(throws: HostServiceError.rpc(code: -32601, message: "method not found")) {
            _ = try await client.request(method: "agent.unknownMethod")
        }

        try await serverTask.value
    }

    @Test("response id correlates with request id")
    func idCorrelation() async throws {
        let socketPath = makeTempSocketPath()
        let server = FakeDaemonServer(socketPath: socketPath)
        try server.start()
        defer { server.stop() }

        let serverTask = Task {
            let (connFD, request) = try server.acceptHandshakeThenOneRequest()
            defer { close(connFD) }
            let id = request["id"] as? Int
            // Echo a deliberately distinctive result so we know this exact
            // response was decoded, tying it back to the request id.
            let response = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "id": id as Any,
                "result": ["daemonVersion": "9.9.9", "checks": [], "generatedAt": "2026-06-21T00:00:00Z"],
            ])
            try FakeDaemonServer.writeFramedBlocking(fd: connFD, json: response)
            return id
        }

        let client = HostServiceClient(socketPathOverride: socketPath, tokenOverride: testToken)
        try await client.connect()
        let report = try await client.doctor()
        #expect(report.daemonVersion == "9.9.9")

        let requestID = try await serverTask.value
        #expect(requestID == 2) // id 1 is consumed by the hello handshake; doctor is the 2nd request
    }

    @Test("wire framing is exactly 4-byte big-endian length prefix + payload")
    func framingIsExact() async throws {
        let socketPath = makeTempSocketPath()
        let server = FakeDaemonServer(socketPath: socketPath)
        try server.start()
        defer { server.stop() }

        let serverTask = Task { () -> Data in
            let connFD = accept(server.listenFD, nil, nil)
            #expect(connFD >= 0)
            defer { close(connFD) }

            // Service the hello handshake first so connect() succeeds; the
            // frame we want to assert on is the subsequent ping request.
            _ = try respondToHandshake(connFD: connFD, server: server)

            // Read the raw bytes of the frame (length prefix included) so we
            // can assert on the wire format itself, not just the decoded payload.
            let rawFrame = try FakeDaemonServer.readRawFrameBlocking(fd: connFD)

            guard let (payload, _) = DaemonFraming.unframe(rawFrame) else {
                throw FakeDaemonServer.TestSetupError.socket("failed to unframe raw frame")
            }
            let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
            let id = (json?["id"] as? Int) ?? 1

            let response = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0", "id": id, "result": "pong",
            ])
            try FakeDaemonServer.writeFramedBlocking(fd: connFD, json: response)
            return rawFrame
        }

        let client = HostServiceClient(socketPathOverride: socketPath)
        try await client.connect()
        _ = try await client.ping()

        let rawFrame = try await serverTask.value
        #expect(rawFrame.count >= 4)

        let declaredLength = (UInt32(rawFrame[rawFrame.startIndex]) << 24)
            | (UInt32(rawFrame[rawFrame.startIndex + 1]) << 16)
            | (UInt32(rawFrame[rawFrame.startIndex + 2]) << 8)
            | UInt32(rawFrame[rawFrame.startIndex + 3])
        #expect(Int(declaredLength) == rawFrame.count - 4)

        let payloadBytes = rawFrame.suffix(from: rawFrame.startIndex + 4)
        let json = try JSONSerialization.jsonObject(with: Data(payloadBytes)) as? [String: Any]
        #expect(json?["method"] as? String == "ping")
    }

    @Test("handshake exposes the daemon's reported service version")
    func handshakeServiceVersion() async throws {
        let socketPath = makeTempSocketPath()
        let server = FakeDaemonServer(socketPath: socketPath)
        try server.start()
        defer { server.stop() }

        let serverTask = Task {
            let connFD = accept(server.listenFD, nil, nil)
            #expect(connFD >= 0)
            defer { close(connFD) }
            _ = try respondToHandshake(connFD: connFD, server: server, protocolVersion: 1, serviceVersion: "lancerd-2.3.4")
        }

        let client = HostServiceClient(socketPathOverride: socketPath, tokenOverride: testToken)
        try await client.connect()
        let reported = await client.serviceVersion
        #expect(reported == "lancerd-2.3.4")
        try await serverTask.value
    }

    @Test("handshake protocol-version disagreement throws versionMismatch")
    func handshakeVersionMismatch() async throws {
        let socketPath = makeTempSocketPath()
        let server = FakeDaemonServer(socketPath: socketPath)
        try server.start()
        defer { server.stop() }

        let serverTask = Task {
            let connFD = accept(server.listenFD, nil, nil)
            #expect(connFD >= 0)
            defer { close(connFD) }
            _ = try respondToHandshake(connFD: connFD, server: server, protocolVersion: 2, serviceVersion: "future")
        }

        let client = HostServiceClient(socketPathOverride: socketPath, tokenOverride: testToken)
        await #expect(throws: HostServiceError.versionMismatch) {
            try await client.connect()
        }
        try await serverTask.value
    }

    @Test("handshake rejection (-32001) surfaces as HostServiceError.rpc")
    func handshakeUnauthorized() async throws {
        let socketPath = makeTempSocketPath()
        let server = FakeDaemonServer(socketPath: socketPath)
        try server.start()
        defer { server.stop() }

        let serverTask = Task {
            let connFD = accept(server.listenFD, nil, nil)
            #expect(connFD >= 0)
            defer { close(connFD) }
            _ = try respondToHandshakeWithError(connFD: connFD, code: -32001, message: "unauthorized")
        }

        let client = HostServiceClient(socketPathOverride: socketPath, tokenOverride: "wrong")
        await #expect(throws: HostServiceError.rpc(code: -32001, message: "unauthorized")) {
            try await client.connect()
        }
        try await serverTask.value
    }
}
