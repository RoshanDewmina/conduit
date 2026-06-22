#if os(iOS)
import Foundation
import Observation
import LancerCore
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
    /// Refresh worktrees from all connected hosts.
    ///
    /// `workdirByHost` maps a hostID to the repo/workspace path lancerd should
    /// enumerate worktrees under. Hosts without an entry are skipped (the daemon
    /// returns `[]` for an empty workdir, so the board simply shows nothing for
    /// that host rather than erroring).
    public func refresh(workdirByHost: [HostID: String]? = nil) async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        // Derive each connected host's workdir from its live session cwd unless
        // the caller supplied an explicit map. Keeps `fleetStore` private — the
        // view no longer needs to reach into it.
        let resolved: [HostID: String] = workdirByHost ?? fleetStore.slots.reduce(into: [:]) { dict, slot in
            let cwd = slot.sessionViewModel.cwd
            if slot.sessionViewModel.status == .connected, cwd != "~", !cwd.isEmpty {
                dict[slot.hostID] = cwd
            }
        }

        var collected: [Worktree] = []

        for slot in fleetStore.slots {
            guard slot.sessionViewModel.status == .connected else { continue }
            guard let workdir = resolved[slot.hostID], !workdir.isEmpty else { continue }
            do {
                let items = try await slot.channel.listWorktrees(workdir: workdir)
                collected.append(contentsOf: items)
            } catch {
                // Non-fatal — other slots still load.
            }
        }

        worktrees = collected
    }
}
#endif
