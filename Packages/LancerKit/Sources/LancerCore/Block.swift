import Foundation

// MARK: - Block lifecycle state

/// Lifecycle state of a `Block`, matching the OSC 133 A/B/C/D
/// shell-integration state machine (Warp-style: blocks are display
/// slices of the PTY stream bounded by shell-integration markers).
public enum BlockState: Sendable, Hashable, Codable {
    /// Shell is showing the prompt (OSC 133 A received).
    /// The user is composing their command locally.
    case promptEditing
    /// User submitted the command (Enter/Send tapped); the shell has
    /// received the bytes but OSC 133 C has not yet arrived.
    case submitted
    /// Command is executing (OSC 133 C received).
    /// Every keystroke from the composer is forwarded directly to PTY.
    case executing
    /// Command finished (OSC 133 D received).  Block is immutable.
    case done(exitCode: Int)
}

// MARK: - Block model

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
    /// Tier 2.3: set when block was invoked from a snippet in the palette.
    public var originatingSnippetID: SnippetID?
    /// Current lifecycle state.  Drives the input model in `SessionView`.
    public var state: BlockState

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
        isStarred: Bool = false,
        originatingSnippetID: SnippetID? = nil,
        state: BlockState = .promptEditing
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
        self.originatingSnippetID = originatingSnippetID
        self.state = state
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
