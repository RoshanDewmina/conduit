import Foundation
import ConduitCore

// MARK: - Git value types

/// A single changed path reported by `git status --porcelain`.
public struct GitFileChange: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    /// Two-letter XY porcelain code (e.g. " M", "??", "A ", "R ").
    public let code: String
    /// True when the change is staged in the index (X column is set, non-`?`).
    public let staged: Bool

    public init(path: String, code: String, staged: Bool) {
        self.path = path
        self.code = code
        self.staged = staged
    }

    /// Human label for the change kind, derived from the porcelain code.
    public var label: String {
        switch code {
        case "??":            return "untracked"
        case let c where c.hasPrefix("A"): return "added"
        case let c where c.hasPrefix("D"): return "deleted"
        case let c where c.hasPrefix("R"): return "renamed"
        case let c where c.contains("M"):  return "modified"
        default:                            return "changed"
        }
    }
}

/// Parsed result of `git status --porcelain=v1 -b` in a workspace.
public struct GitStatus: Sendable, Equatable {
    public let branch: String
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let changes: [GitFileChange]

    public init(branch: String, upstream: String?, ahead: Int, behind: Int, changes: [GitFileChange]) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changes = changes
    }

    public var isClean: Bool { changes.isEmpty }
    public var hasStagedChanges: Bool { changes.contains(where: \.staged) }
}

/// Result of the conduitd `agent.git.ship` RPC (stage+commit+push+PR).
/// Idempotent: `committed`/`pushed` report exactly which stages completed so a
/// partial failure (e.g. commit ok, push rejected) is safely retryable.
public struct GitShipResult: Sendable, Equatable {
    public let committed: Bool
    public let pushed: Bool
    public let prURL: String?
    /// Human-readable detail when a stage did not fully complete (push rejected,
    /// PR auth missing, etc.). Empty on full success.
    public let message: String?

    public init(committed: Bool, pushed: Bool, prURL: String? = nil, message: String? = nil) {
        self.committed = committed
        self.pushed = pushed
        self.prURL = prURL
        self.message = message
    }

    /// True when commit + push both succeeded (PR is best-effort / optional).
    public var isShipped: Bool { committed && pushed }
}

/// Error raised when a git/gh command exits non-zero. Carries the combined
/// stdout+stderr so callers can surface the real failure reason.
public struct GitCommandError: Error, Sendable, Equatable {
    public let exitCode: Int
    public let output: String
    public init(exitCode: Int, output: String) {
        self.exitCode = exitCode
        self.output = output
    }
    public var localizedDescription: String {
        output.isEmpty ? "git exited \(exitCode)" : output
    }
}

// MARK: - GitClient

/// Runs git (and `gh` for PRs) against a repository on an `SSHSession`'s host.
///
/// Commands run via `git -C <workdir> …` over the SSH command channel. Every
/// caller-supplied value (workdir, branch, message, paths, PR title/body) is
/// single-quote shell-escaped to prevent command injection. Output and exit
/// code are captured together via a sentinel marker so a non-zero git exit
/// surfaces as `GitCommandError` rather than an opaque transport failure.
public actor GitClient {
    private let session: SSHSession

    public init(session: SSHSession) {
        self.session = session
    }

    private static let exitMarker = "__CONDUIT_GIT_EXIT__"

    // MARK: - Read operations

    /// Parses `git status --porcelain=v1 -b` for `workdir`.
    public func status(workdir: String) async throws -> GitStatus {
        let out = try await runGit(workdir: workdir, ["status", "--porcelain=v1", "-b"])
        return Self.parseStatus(out)
    }

    /// Returns the current branch name (or "HEAD" when detached).
    public func currentBranch(workdir: String) async throws -> String {
        let out = try await runGit(workdir: workdir, ["rev-parse", "--abbrev-ref", "HEAD"])
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns a unified diff. When `path` is given, scopes to that path;
    /// when `staged` is true, diffs the index (`--cached`).
    public func diff(workdir: String, path: String? = nil, staged: Bool = false) async throws -> String {
        var args = ["--no-pager", "diff"]
        if staged { args.append("--cached") }
        if let path { args.append(contentsOf: ["--", path]) }
        return try await runGit(workdir: workdir, args)
    }

    /// Returns recent log lines (`--oneline`, capped at `limit`).
    public func log(workdir: String, limit: Int = 20) async throws -> String {
        try await runGit(workdir: workdir, ["--no-pager", "log", "--oneline", "-n", String(limit)])
    }

    // MARK: - Worktree / branch operations

    /// Lists local branches in `workdir`, one per line of `git branch` output.
    public func listBranches(workdir: String) async throws -> [String] {
        let out = try await runGit(workdir: workdir, ["branch", "--format=%(refname:short)"])
        return out.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Returns changed files between `baseBranch` (or current) and `branch`.
    /// Uses `git diff --name-status` for compact file-status pairs.
    public func changedFiles(
        workdir: String,
        baseBranch: String? = nil,
        branch: String? = nil
    ) async throws -> [Worktree.ChangedFile] {
        var args = ["diff", "--name-status"]
        if let base = baseBranch {
            args.append(base)
        }
        if let target = branch {
            args.append(target)
        }
        let out = try await runGit(workdir: workdir, args)
        return Self.parseNameStatus(out)
    }

    /// Returns the latest commit info for `branch`.
    public func latestCommit(workdir: String, branch: String? = nil) async throws -> Worktree.CommitInfo? {
        var args = ["log", "-1", "--pretty=format:%H%n%s%n%an%n%aI"]
        if let branch { args.append(branch) }
        let out = try await runGit(workdir: workdir, args)
        let lines = out.split(separator: "\n").map(String.init)
        guard lines.count >= 4 else { return nil }
        let date = ISO8601DateFormatter().date(from: lines[3]) ?? Date.distantPast
        return Worktree.CommitInfo(hash: lines[0], message: lines[1], author: lines[2], date: date)
    }

    /// Parses `git diff --name-status` output into ChangedFile values.
    nonisolated static func parseNameStatus(_ output: String) -> [Worktree.ChangedFile] {
        output.split(separator: "\n").compactMap { line -> Worktree.ChangedFile? in
            let parts = line.split(separator: "\t")
            guard parts.count >= 2 else { return nil }
            let code = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let path = String(parts[1])
            let status: Worktree.ChangedFile.FileStatus
            if code.hasPrefix("A") {
                status = .added
            } else if code.hasPrefix("D") {
                status = .deleted
            } else if code.hasPrefix("R") {
                status = .renamed
            } else {
                status = .modified
            }
            return Worktree.ChangedFile(path: path, status: status)
        }
    }

    // MARK: - Write operations

    /// Creates and checks out a new branch.
    public func createBranch(workdir: String, name: String) async throws {
        _ = try await runGit(workdir: workdir, ["checkout", "-b", name])
    }

    /// Checks out an existing branch.
    public func checkout(workdir: String, name: String) async throws {
        _ = try await runGit(workdir: workdir, ["checkout", name])
    }

    /// Stages paths, or everything when `paths` is empty (`git add -A`).
    public func stage(workdir: String, paths: [String] = []) async throws {
        var args = ["add"]
        if paths.isEmpty { args.append("-A") } else { args.append(contentsOf: paths) }
        _ = try await runGit(workdir: workdir, args)
    }

    /// Commits staged changes with `message`.
    public func commit(workdir: String, message: String) async throws {
        _ = try await runGit(workdir: workdir, ["commit", "-m", message])
    }

    /// Pushes the current branch, setting upstream to `origin` on first push.
    public func push(workdir: String, setUpstream: Bool = true) async throws {
        let branch = try await currentBranch(workdir: workdir)
        var args = ["push"]
        if setUpstream { args.append(contentsOf: ["--set-upstream", "origin", branch]) }
        _ = try await runGit(workdir: workdir, args)
    }

    /// Opens a pull request via the GitHub CLI and returns the PR URL.
    /// Requires `gh` to be installed and authenticated on the host.
    public func createPullRequest(
        workdir: String,
        title: String,
        body: String,
        base: String? = nil
    ) async throws -> String {
        var args = ["pr", "create", "--title", title, "--body", body]
        if let base { args.append(contentsOf: ["--base", base]) }
        let out = try await run(workdir: workdir, tool: "gh", args)
        // `gh pr create` prints the PR URL on the last non-empty line.
        let url = out.split(separator: "\n").last { $0.contains("http") }.map(String.init)
        return (url ?? out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Command execution

    private func runGit(workdir: String, _ args: [String]) async throws -> String {
        try await run(workdir: workdir, tool: "git", args)
    }

    /// Builds `cd <workdir> && <tool> <args…> 2>&1; echo <marker>$?`, executes it,
    /// and splits off the trailing exit code. Throws `GitCommandError` on non-zero.
    private func run(workdir: String, tool: String, _ args: [String]) async throws -> String {
        let quotedArgs = args.map(Self.shellQuote).joined(separator: " ")
        let command = "cd \(Self.shellQuote(workdir)) && \(tool) \(quotedArgs) 2>&1; "
            + "echo \"\(Self.exitMarker)$?\""
        let raw = try await session.executeCollected(command)
        let (output, exitCode) = Self.splitExit(raw)
        guard exitCode == 0 else {
            throw GitCommandError(exitCode: exitCode, output: output)
        }
        return output
    }

    // MARK: - Pure helpers (nonisolated, testable)

    /// Separates the trailing `<marker><code>` sentinel from command output.
    nonisolated static func splitExit(_ raw: String) -> (output: String, exitCode: Int) {
        guard let range = raw.range(of: exitMarker, options: .backwards) else {
            return (raw.trimmingCharacters(in: .newlines), 0)
        }
        let codeText = raw[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let output = String(raw[..<range.lowerBound]).trimmingCharacters(in: .newlines)
        return (output, Int(codeText) ?? 0)
    }

    /// Parses `git status --porcelain=v1 -b` output into a `GitStatus`.
    nonisolated static func parseStatus(_ output: String) -> GitStatus {
        var branch = "HEAD"
        var upstream: String?
        var ahead = 0
        var behind = 0
        var changes: [GitFileChange] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("## ") {
                (branch, upstream, ahead, behind) = parseBranchLine(String(line.dropFirst(3)))
            } else if line.count >= 3 {
                let code = String(line.prefix(2))
                var path = String(line.dropFirst(3))
                // Renames are reported as "old -> new"; keep the new path.
                if let arrow = path.range(of: " -> ") {
                    path = String(path[arrow.upperBound...])
                }
                let x = code.first ?? " "
                let staged = x != " " && x != "?"
                changes.append(GitFileChange(path: path, code: code, staged: staged))
            }
        }
        return GitStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, changes: changes)
    }

    /// Parses the `## branch...upstream [ahead N, behind M]` header line.
    nonisolated private static func parseBranchLine(
        _ line: String
    ) -> (branch: String, upstream: String?, ahead: Int, behind: Int) {
        var rest = Substring(line)
        var ahead = 0
        var behind = 0

        // Strip the optional "[ahead N, behind M]" suffix first.
        if let bracket = rest.range(of: " [") {
            let tracking = rest[bracket.upperBound...].dropLast() // remove trailing ']'
            for token in tracking.split(separator: ",") {
                let parts = token.split(separator: " ").filter { !$0.isEmpty }
                guard parts.count == 2, let n = Int(parts[1]) else { continue }
                if parts[0] == "ahead" { ahead = n }
                if parts[0] == "behind" { behind = n }
            }
            rest = rest[..<bracket.lowerBound]
        }

        // "branch...upstream" or "No commits yet on branch" or "HEAD (no branch)".
        if let sep = rest.range(of: "...") {
            let branch = String(rest[..<sep.lowerBound])
            let upstream = String(rest[sep.upperBound...])
            return (branch, upstream.isEmpty ? nil : upstream, ahead, behind)
        }
        return (rest.trimmingCharacters(in: .whitespaces), nil, ahead, behind)
    }

    /// Single-quote shell escaping: wraps in '…' and escapes embedded quotes.
    nonisolated static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
