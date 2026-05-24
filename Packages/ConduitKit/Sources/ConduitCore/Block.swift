import Foundation

/// A `Block` is the unit of the Warp-style terminal: a single submitted
/// command plus its complete output and exit status. Blocks are the
/// canonical container for non-TUI output. TUI / alt-screen programs are
/// rendered into a single synthetic Block on exit.
public struct Block: Identifiable, Sendable, Hashable {
    public let id: BlockID
    public let sessionID: SessionID
    public var prompt: PromptInfo
    public var command: String
    public var chunks: [BlockChunk]
    public var exitStatus: ExitStatus?
    public var startedAt: Date
    public var finishedAt: Date?
    public var isCollapsed: Bool
    public var isStarred: Bool

    public struct PromptInfo: Sendable, Hashable, Codable {
        public var cwd: String
        public var hostName: String

        public init(cwd: String, hostName: String) {
            self.cwd = cwd
            self.hostName = hostName
        }
    }

    public init(
        id: BlockID = .init(),
        sessionID: SessionID,
        prompt: PromptInfo,
        command: String,
        chunks: [BlockChunk] = [],
        exitStatus: ExitStatus? = nil,
        startedAt: Date = .now,
        finishedAt: Date? = nil,
        isCollapsed: Bool = false,
        isStarred: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.prompt = prompt
        self.command = command
        self.chunks = chunks
        self.exitStatus = exitStatus
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isCollapsed = isCollapsed
        self.isStarred = isStarred
    }

    public var hasOutput: Bool { !chunks.isEmpty }

    public var duration: TimeInterval? {
        guard let end = finishedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }

    public var joinedOutput: String {
        chunks.map(\.text).joined()
    }
}

public struct BlockChunk: Sendable, Hashable, Codable {
    public enum Stream: String, Sendable, Codable, Hashable { case stdout, stderr }

    public let text: String
    public let stream: Stream
    public let receivedAt: Date

    public init(text: String, stream: Stream, receivedAt: Date = .now) {
        self.text = text
        self.stream = stream
        self.receivedAt = receivedAt
    }
}

public struct ExitStatus: Sendable, Hashable, Codable {
    public let code: Int
    public init(code: Int) { self.code = code }
    public var isSuccess: Bool { code == 0 }
}
