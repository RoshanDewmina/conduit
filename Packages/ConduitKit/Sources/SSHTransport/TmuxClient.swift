import Foundation
import ConduitCore

/// Thin actor wrapper around tmux shell commands executed over an SSH session.
/// All methods run synchronously on the remote host via `executeCollected`.
public actor TmuxClient {
    private let session: SSHSession

    public init(session: SSHSession) {
        self.session = session
    }

    // MARK: - Session discovery

    /// Returns the names of all currently-running tmux sessions on the remote host.
    public func listSessions() async throws -> [String] {
        let output = try await session.executeCollected(
            "tmux list-sessions -F '#{session_name}' 2>/dev/null || true"
        )
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Attach or create

    /// Attaches to an existing tmux session called `name`, or creates a new
    /// detached session with that name if one does not already exist.
    public func attachOrCreate(name: String) async throws {
        // Validate name to prevent shell injection.
        guard isValidTmuxName(name) else {
            throw ConduitError.unknown(detail: "Invalid tmux session name: \(name)")
        }
        _ = try await session.executeCollected(
            "tmux has-session -t \(name) 2>/dev/null && tmux attach-session -d -t \(name) || tmux new-session -d -s \(name)"
        )
    }

    // MARK: - Capture pane

    /// Returns the last `lastLines` lines of visible output from the given tmux session.
    public func capturePane(name: String, lastLines: Int) async throws -> String {
        guard isValidTmuxName(name) else {
            throw ConduitError.unknown(detail: "Invalid tmux session name: \(name)")
        }
        let safeLines = max(1, min(lastLines, 50_000))
        return try await session.executeCollected(
            "tmux capture-pane -p -t \(name) -S -\(safeLines) 2>/dev/null || true"
        )
    }

    // MARK: - Kill

    /// Kills the named tmux session. No-ops (returns nil) if the session does
    /// not exist.
    public func kill(name: String) async throws {
        guard isValidTmuxName(name) else {
            throw ConduitError.unknown(detail: "Invalid tmux session name: \(name)")
        }
        _ = try await session.executeCollected(
            "tmux kill-session -t \(name) 2>/dev/null || true"
        )
    }

    // MARK: - Helpers

    /// Returns true when `name` contains only alphanumerics, hyphens, underscores,
    /// and dots — the characters tmux accepts in session names.
    private func isValidTmuxName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }
}
