#if os(iOS)
import Foundation
import Observation
import ConduitCore
import SSHTransport

/// Manages worktree state across connected hosts.
@MainActor @Observable
public final class WorktreeStore {
    public var worktrees: [Worktree] = []
    public var selectedWorktree: Worktree?
    public var isLoading = false
    public var error: String?

    private let fleetStore: FleetStore

    public init(fleetStore: FleetStore) {
        self.fleetStore = fleetStore
    }

    // MARK: - Computed

    public var activeWorktrees: [Worktree] {
        worktrees.filter { $0.status == .active }
    }

    public var completedWorktrees: [Worktree] {
        worktrees.filter { $0.status == .completed }
    }

    public var idleWorktrees: [Worktree] {
        worktrees.filter { $0.status == .idle || $0.status == .stale }
    }

    public var repos: [String: [Worktree]] {
        Dictionary(grouping: worktrees, by: \.repoName)
    }

    public var repoNames: [String] {
        Array(Set(worktrees.map(\.repoName))).sorted()
    }

    // MARK: - Actions

    public func selectWorktree(_ worktree: Worktree) {
        selectedWorktree = worktree
    }

    /// Refresh worktrees from all connected hosts.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        var collected: [Worktree] = []

        for slot in fleetStore.slots {
            guard slot.sessionViewModel.status == .connected else { continue }
            let channel = slot.channel
            do {
                let items = try await channel.fetchWorktrees()
                collected.append(contentsOf: items)
            } catch {
                // Non-fatal — other slots still load.
            }
        }

        worktrees = collected
    }
}

// MARK: - DaemonChannel worktree helpers

extension DaemonChannel {
    /// Fetches worktrees for this host via the bridge.
    func fetchWorktrees() async throws -> [Worktree] {
        // Bridge protocol: request worktrees over the SSH channel.
        // For now, delegate to the git client via the session.
        // This will be wired to the daemon protocol when the
        // bridge-side worktree endpoint is implemented.
        return []
    }
}
#endif
