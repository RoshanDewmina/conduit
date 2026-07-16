#if os(iOS)
import Foundation

// Ported from Orca (MIT, Lovecast Inc.) — https://github.com/stablyai/orca
// Source: src/shared/terminal-stream-protocol.ts

public enum TerminalStreamOpcode: UInt8, Sendable {
    case output = 1
    case snapshotStart = 2
    case snapshotChunk = 3
    case snapshotEnd = 4
    case resized = 5
    case error = 6
    case input = 7
    case resize = 8
    case subscribe = 9
    case unsubscribe = 10
    case snapshotRequest = 11
    case metadata = 12
    case ack = 13
}

public struct TerminalStreamFrame: Sendable {
    public let opcode: TerminalStreamOpcode
    public let streamId: UInt32
    public let seq: UInt64
    public let payload: Data
}

public enum TerminalStreamCodec {
    private static let kind: UInt8 = 0x74
    private static let version: UInt8 = 1
    private static let headerBytes = 16

    public static func encode(
        opcode: TerminalStreamOpcode,
        streamId: UInt32,
        seq: UInt64,
        payload: Data
    ) -> Data {
        var out = Data(count: headerBytes + payload.count)
        out[0] = kind
        out[1] = version
        out[2] = opcode.rawValue
        out[3] = 0
        out.replaceSubrange(4..<8, with: withUnsafeBytes(of: streamId.littleEndian, Array.init))
        let high = UInt32(seq >> 32)
        let low = UInt32(truncatingIfNeeded: seq)
        out.replaceSubrange(8..<12, with: withUnsafeBytes(of: high.littleEndian, Array.init))
        out.replaceSubrange(12..<16, with: withUnsafeBytes(of: low.littleEndian, Array.init))
        if !payload.isEmpty {
            out.replaceSubrange(headerBytes..<(headerBytes + payload.count), with: payload)
        }
        return out
    }

    public static func decode(_ data: Data) -> TerminalStreamFrame? {
        guard data.count >= headerBytes,
              data[data.startIndex] == kind,
              data[data.startIndex + 1] == version,
              let opcode = TerminalStreamOpcode(rawValue: data[data.startIndex + 2])
        else { return nil }
        let streamId: UInt32 = data.subdata(in: (data.startIndex + 4)..<(data.startIndex + 8))
            .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let high: UInt32 = data.subdata(in: (data.startIndex + 8)..<(data.startIndex + 12))
            .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let low: UInt32 = data.subdata(in: (data.startIndex + 12)..<(data.startIndex + 16))
            .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let seq = (UInt64(high) << 32) | UInt64(low)
        let payload = data.count > headerBytes
            ? data.subdata(in: (data.startIndex + headerBytes)..<data.endIndex)
            : Data()
        return TerminalStreamFrame(opcode: opcode, streamId: streamId, seq: seq, payload: payload)
    }
}

// MARK: - Wire types (Orca runtime terminal.* over Lancer relay)

public struct TerminalCreateRequest: Codable, Sendable {
    public var sessionId: String?
    public var cwd: String?
    public var cols: Int
    public var rows: Int
    public var command: String?
    public var env: [String: String]?

    public init(
        sessionId: String? = nil,
        cwd: String? = nil,
        cols: Int = 80,
        rows: Int = 24,
        command: String? = nil,
        env: [String: String]? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.cols = cols
        self.rows = rows
        self.command = command
        self.env = env
    }
}

public struct TerminalHandlePayload: Codable, Sendable {
    public let handle: String
    public let sessionId: String?
    public let pid: Int?
    public let title: String?
    public let isNew: Bool?
}

public struct TerminalCreateResponse: Codable, Sendable {
    public let terminal: TerminalHandlePayload?
    public let error: String?
}

public struct TerminalSendRequest: Codable, Sendable {
    public let handle: String
    public let text: String
}

public struct TerminalSendResponse: Codable, Sendable {
    public struct Send: Codable, Sendable {
        public let handle: String
        public let accepted: Bool
        public let bytesWritten: Int?
    }
    public let send: Send?
    public let error: String?
}

public struct TerminalResizeRequest: Codable, Sendable {
    public let handle: String
    public let cols: Int
    public let rows: Int
    public var mode: String?
    public var clientId: String?
}

public struct TerminalResizeResponse: Codable, Sendable {
    public let handle: String?
    public let cols: Int?
    public let rows: Int?
    public let error: String?
}

public struct TerminalCloseRequest: Codable, Sendable {
    public let handle: String
}

public struct TerminalCloseResponse: Codable, Sendable {
    public let handle: String?
    public let error: String?
}

public struct TerminalSubscribeRequest: Codable, Sendable {
    public struct Client: Codable, Sendable {
        public let id: String
        public let type: String
    }
    public let handle: String
    public let client: Client
}

public struct TerminalSubscribeResponse: Codable, Sendable {
    public let handle: String?
    public let streamId: UInt32?
    public let error: String?
}

public struct TerminalStreamEnvelope: Codable, Sendable {
    public let sessionId: String
    public let frame: String // base64 Orca frame
}
#endif
