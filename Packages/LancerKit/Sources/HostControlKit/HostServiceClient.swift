import Darwin
import Foundation
import LancerCore

/// Errors surfaced by ``HostServiceClient``.
public enum HostServiceError: Error, Sendable, Equatable {
    case notConnected
    case rpc(code: Int, message: String)
    case decoding
    case socket(String)
    /// Thrown when a successful `hello` handshake reports a
    /// `protocolVersion` that doesn't match `HostServiceClient.protocolVersion`.
    case versionMismatch
}

/// JSON-RPC 2.0 client for `lancerd`'s local control socket
/// (`~/.lancer/lancerd.sock`).
///
/// One actor instance owns one connection. Not reentrant-safe across
/// reconnects — callers that need retry/backoff build it on top.
public actor HostServiceClient {
    /// JSON-RPC handshake protocol version this client speaks. Bumped only
    /// in lockstep with the daemon's wire contract.
    public static let protocolVersion = 1

    private let socketPath: String
    private let token: String
    private var fd: Int32 = -1
    private var nextID: Int = 1

    /// `lancerd`'s reported version string from the most recent successful
    /// `hello` handshake. `nil` until `connect()` succeeds.
    public private(set) var serviceVersion: String?

    /// - Parameters:
    ///   - socketPathOverride: explicit socket path, bypassing the
    ///     `~/.lancer` resolution. Used by tests.
    ///   - tokenOverride: explicit IPC token, bypassing the
    ///     `~/.lancer/ipc-token` resolution. Used by tests.
    public init(socketPathOverride: String? = nil, tokenOverride: String? = nil) {
        if let override = socketPathOverride {
            socketPath = override
        } else {
            socketPath = Self.resolveSocketPath()
        }
        if let tokenOverride {
            token = tokenOverride
        } else {
            token = Self.resolveToken()
        }
    }

    deinit {
        if fd >= 0 {
            close(fd)
        }
    }

    /// The current user's home directory. `homeDirectoryForCurrentUser` is
    /// macOS-only and returns the real home even when sandboxed — required for the
    /// daemon socket path. iOS gets a sandbox-home fallback purely so the package
    /// compiles for iOS test builds; HostControlKit is never used on iOS.
    private static var homeDirectory: String {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser.path
        #else
        NSHomeDirectory()
        #endif
    }

    private static func resolveSocketPath() -> String {
        homeDirectory + "/.lancer/lancerd.sock"
    }

    /// Reads the local IPC auth token from `~/.lancer/ipc-token`. Returns an
    /// empty string (never throws/crashes) if the file does not exist — the
    /// daemon will reject the empty token with -32001, which `connect()`
    /// surfaces as `HostServiceError.rpc`.
    private static func resolveToken() -> String {
        let tokenPath = homeDirectory + "/.lancer/ipc-token"
        if let raw = try? String(contentsOfFile: tokenPath, encoding: .utf8) {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// Opens the `AF_UNIX`/`SOCK_STREAM` connection. Safe to call once per
    /// instance; call again after a `socket(...)` error to reconnect.
    public func connect() async throws {
        if fd >= 0 {
            close(fd)
            fd = -1
        }

        let newFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard newFD >= 0 else {
            throw HostServiceError.socket("socket() failed: \(String(cString: strerror(errno)))")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(newFD)
            throw HostServiceError.socket("socket path too long: \(socketPath)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
            let buf = rawPtr.bindMemory(to: UInt8.self)
            for (i, byte) in pathBytes.enumerated() {
                buf[i] = byte
            }
            buf[pathBytes.count] = 0
        }

        let addrSize = MemoryLayout<sockaddr_un>.size
        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(newFD, sockaddrPtr, socklen_t(addrSize))
            }
        }
        guard connectResult == 0 else {
            let err = String(cString: strerror(errno))
            close(newFD)
            throw HostServiceError.socket("connect() failed for \(socketPath): \(err)")
        }

        fd = newFD

        try await performHandshake()
    }

    /// Sends the first framed message on a freshly-opened socket: a
    /// `hello` JSON-RPC request carrying the protocol version and the local
    /// IPC token. A JSON-RPC `error` response (bad token → -32001, version
    /// mismatch the daemon itself detects → -32002) surfaces uniformly as
    /// `HostServiceError.rpc(code:message:)` via `rawRequest`. Only a
    /// *successful* `hello` whose `result.protocolVersion` disagrees with
    /// ours throws the dedicated `.versionMismatch` case.
    private func performHandshake() async throws {
        let helloParams: [String: Any] = [
            "protocolVersion": Self.protocolVersion,
            "token": token,
        ]
        let result = try await rawRequest(method: "hello", paramsObject: helloParams)

        guard let resultDict = result as? [String: Any],
              let reportedVersion = (resultDict["protocolVersion"] as? Int) ?? (resultDict["protocolVersion"] as? NSNumber)?.intValue,
              let reportedServiceVersion = resultDict["serviceVersion"] as? String else {
            throw HostServiceError.decoding
        }

        guard reportedVersion == Self.protocolVersion else {
            throw HostServiceError.versionMismatch
        }

        serviceVersion = reportedServiceVersion
    }

    /// Sends a JSON-RPC 2.0 request and returns the raw `result` payload as
    /// `Data` (an empty/`"ok"`/`"pong"` string result is re-encoded as JSON
    /// so callers can decode it uniformly).
    public func request(method: String, params: Encodable? = nil) async throws -> Data {
        var paramsObject: Any?
        if let params {
            let encoder = JSONEncoder()
            let paramsData = try encoder.encode(AnyEncodable(params))
            guard let decoded = try? JSONSerialization.jsonObject(with: paramsData) else {
                throw HostServiceError.decoding
            }
            paramsObject = decoded
        }

        let result = try await rawRequest(method: method, paramsObject: paramsObject)

        // Scalar results ("pong", "ok") aren't valid top-level JSON on their
        // own from JSONSerialization's perspective for re-encoding into a
        // typed decode, so wrap them as a bare JSON string/bool/number.
        if JSONSerialization.isValidJSONObject(result) || result is [Any] {
            return try JSONSerialization.data(withJSONObject: result as Any)
        }
        if let s = result as? String {
            return try JSONEncoder().encode(s)
        }
        if let b = result as? Bool {
            return try JSONEncoder().encode(b)
        }
        if let n = result as? NSNumber {
            return try JSONEncoder().encode(n.doubleValue)
        }
        throw HostServiceError.decoding
    }

    /// Shared framing/correlation/error-handling core used by both the
    /// `hello` handshake and `request(method:params:)`. Returns the decoded
    /// `result` value (still `Any` — callers downcast as needed).
    private func rawRequest(method: String, paramsObject: Any? = nil) async throws -> Any {
        guard fd >= 0 else { throw HostServiceError.notConnected }

        let id = nextID
        nextID += 1

        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
        ]
        if let paramsObject {
            payload["params"] = paramsObject
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let requestData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw HostServiceError.decoding
        }

        try writeFramed(requestData)
        let responseData = try await readFramed()

        guard let dict = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] else {
            throw HostServiceError.decoding
        }

        let responseID = (dict["id"] as? Int) ?? (dict["id"] as? NSNumber)?.intValue
        guard responseID == id else {
            throw HostServiceError.decoding
        }

        if let errorDict = dict["error"] as? [String: Any] {
            let code = (errorDict["code"] as? Int) ?? (errorDict["code"] as? NSNumber)?.intValue ?? -1
            let message = (errorDict["message"] as? String) ?? "unknown error"
            throw HostServiceError.rpc(code: code, message: message)
        }

        guard let result = dict["result"] else {
            throw HostServiceError.decoding
        }

        return result
    }

    // MARK: - Convenience methods

    public func ping() async throws -> String {
        let data = try await request(method: "ping")
        return try JSONDecoder().decode(String.self, from: data)
    }

    public func doctor() async throws -> DoctorReport {
        let data = try await request(method: "agent.doctor")
        guard let report = try? JSONDecoder().decode(DoctorReport.self, from: data) else {
            throw HostServiceError.decoding
        }
        return report
    }

    public func status() async throws -> AgentStatusSnapshot {
        let data = try await request(method: "agent.status")
        guard let snapshot = try? JSONDecoder().decode(AgentStatusSnapshot.self, from: data) else {
            throw HostServiceError.decoding
        }
        return snapshot
    }

    /// Scans `root` (a repo path) for instruction-file drift — dead imports and
    /// dead markdown links across CLAUDE.md / AGENTS.md / skills / rules.
    public func driftScan(root: String) async throws -> DriftReport {
        let data = try await request(method: "agent.drift.scan", params: ["root": root])
        guard let report = try? JSONDecoder().decode(DriftReport.self, from: data) else {
            throw HostServiceError.decoding
        }
        return report
    }

    /// Starts a new phone-pairing session: the daemon mints a one-time relay
    /// session, a 6-digit code, and a QR payload the Lancer iPhone app scans
    /// to connect.
    public func beginPairing() async throws -> PairingPayload {
        let data = try await request(method: "agent.pair.begin")
        guard let payload = try? JSONDecoder().decode(PairingPayload.self, from: data) else {
            throw HostServiceError.decoding
        }
        return payload
    }

    // MARK: - Framed I/O

    private func writeFramed(_ json: Data) throws {
        let framed = DaemonFraming.frame(json)
        var remaining = framed
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { rawPtr -> Int in
                Darwin.write(fd, rawPtr.baseAddress, remaining.count)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw HostServiceError.socket("write() failed: \(String(cString: strerror(errno)))")
            }
            if written == 0 {
                throw HostServiceError.socket("write() returned 0 (peer closed)")
            }
            remaining = remaining.dropFirst(written)
        }
    }

    /// Reads bytes until a complete frame (4-byte BE length + payload) is
    /// available, handling partial `read(2)`s and EOF.
    private func readFramed() async throws -> Data {
        var buffer = Data()

        // Read the 4-byte length prefix.
        while buffer.count < 4 {
            let chunk = try readSome(upTo: 4 - buffer.count)
            buffer.append(chunk)
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
            let chunk = try readSome(upTo: needed - buffer.count)
            buffer.append(chunk)
        }

        guard let (payload, _) = DaemonFraming.unframe(buffer) else {
            throw HostServiceError.decoding
        }
        return payload
    }

    private func readSome(upTo maxLength: Int) throws -> Data {
        guard fd >= 0 else { throw HostServiceError.notConnected }
        var tempBuffer = [UInt8](repeating: 0, count: max(maxLength, 1))
        let bytesRead = tempBuffer.withUnsafeMutableBytes { rawPtr -> Int in
            Darwin.read(fd, rawPtr.baseAddress, rawPtr.count)
        }
        if bytesRead < 0 {
            if errno == EINTR {
                return Data()
            }
            throw HostServiceError.socket("read() failed: \(String(cString: strerror(errno)))")
        }
        if bytesRead == 0 {
            throw HostServiceError.socket("read() returned EOF (peer closed)")
        }
        return Data(tempBuffer[0..<bytesRead])
    }
}

/// Type-erasing box so `request(method:params:)` can accept any `Encodable`
/// without making the whole client generic over the params type.
private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
