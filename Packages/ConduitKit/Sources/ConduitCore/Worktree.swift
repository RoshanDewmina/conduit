import Foundation

/// A git worktree or branch being worked on by an agent
public struct Worktree: Sendable, Codable, Identifiable {
    public let id: String
    public let repoName: String
    public let branch: String
    public let path: String
    public let baseBranch: String?
    public let status: Status
    public let agentID: String?
    public let loopID: String?
    public let changedFiles: [ChangedFile]
    public let lastCommit: CommitInfo?
    public let lastActivity: Date

    public enum Status: String, Codable, Sendable {
        case active
        case idle
        case completed
        case stale
    }

    public struct ChangedFile: Sendable, Codable, Identifiable {
        public let path: String
        public let status: FileStatus

        public var id: String { path }

        public enum FileStatus: String, Codable, Sendable {
            case added, modified, deleted, renamed
        }

        public init(path: String, status: FileStatus) {
            self.path = path
            self.status = status
        }
    }

    public struct CommitInfo: Sendable, Codable {
        public let hash: String
        public let message: String
        public let author: String
        public let date: Date

        public init(hash: String, message: String, author: String, date: Date) {
            self.hash = hash
            self.message = message
            self.author = author
            self.date = date
        }
    }

    public init(
        id: String = UUID().uuidString,
        repoName: String,
        branch: String,
        path: String,
        baseBranch: String? = nil,
        status: Status,
        agentID: String? = nil,
        loopID: String? = nil,
        changedFiles: [ChangedFile] = [],
        lastCommit: CommitInfo? = nil,
        lastActivity: Date = .now
    ) {
        self.id = id
        self.repoName = repoName
        self.branch = branch
        self.path = path
        self.baseBranch = baseBranch
        self.status = status
        self.agentID = agentID
        self.loopID = loopID
        self.changedFiles = changedFiles
        self.lastCommit = lastCommit
        self.lastActivity = lastActivity
    }
}

#if DEBUG
extension Worktree {
    public static let sample = Worktree(
        repoName: "gateway",
        branch: "feat/rate-limit",
        path: "/Users/dev/repos/gateway",
        baseBranch: "main",
        status: .active,
        agentID: "claude-code",
        changedFiles: [
            ChangedFile(path: "src/middleware/ratelimit.ts", status: .modified),
            ChangedFile(path: "src/config/gateway.yaml", status: .modified),
            ChangedFile(path: "tests/ratelimit.test.ts", status: .added),
        ],
        lastCommit: CommitInfo(
            hash: "a1b2c3d",
            message: "feat: add token bucket rate limiter",
            author: "claude-code",
            date: Date().addingTimeInterval(-300)
        ),
        lastActivity: Date().addingTimeInterval(-60)
    )

    public static let sampleCompleted = Worktree(
        repoName: "gateway",
        branch: "fix/auth-timeout",
        path: "/Users/dev/repos/gateway-fix",
        baseBranch: "main",
        status: .completed,
        agentID: "claude-code",
        changedFiles: [
            ChangedFile(path: "src/auth/handler.ts", status: .modified),
        ],
        lastCommit: CommitInfo(
            hash: "e4f5g6h",
            message: "fix: extend auth timeout to 30s",
            author: "claude-code",
            date: Date().addingTimeInterval(-1800)
        ),
        lastActivity: Date().addingTimeInterval(-900)
    )

    public static let sampleIdle = Worktree(
        repoName: "gateway",
        branch: "chore/deps",
        path: "/Users/dev/repos/gateway-deps",
        status: .idle,
        changedFiles: [],
        lastActivity: Date().addingTimeInterval(-3600)
    )
}
#endif
