#if os(iOS)
import Foundation
import Observation
import LancerCore
import PersistenceKit
import SSHTransport

/// Manages loop records: active loops, recent history, and daemon sync.
@MainActor @Observable
public final class LoopStore {
    public var activeLoops: [Loop] = []
    public var recentLoops: [Loop] = []
    public var selectedLoop: Loop?
    public var isLoading = false

    private let loopRepo: LoopRepository
    private var channel: DaemonChannel?

    public init(loopRepo: LoopRepository) {
        self.loopRepo = loopRepo
    }

    /// Attach or replace the daemon channel for live updates.
    public func setChannel(_ channel: DaemonChannel) {
        self.channel = channel
    }

    /// Reload active + recent loops from the local database.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            activeLoops = try await loopRepo.activeLoops()
            recentLoops = try await loopRepo.recentLoops(limit: 50)
        } catch {
            // Silently swallow — UI stays on stale data.
        }
    }

    /// Select a loop for detail view.
    public func selectLoop(_ loop: Loop) {
        selectedLoop = loop
    }

    /// Create a new loop, persist it, and push to the daemon.
    public func createLoop(
        goal: String,
        agent: String,
        hostID: String,
        vendor: String? = nil,
        model: String? = nil,
        repo: String? = nil,
        branch: String? = nil
    ) async throws {
        var loop = Loop(
            goal: goal,
            agent: agent,
            vendor: vendor,
            model: model,
            hostID: hostID,
            repo: repo,
            branch: branch
        )
        loop.lastActivityAt = .now
        try await loopRepo.upsert(loop)
        try? await channel?.updateLoop(loop)
        await refresh()
        selectedLoop = loop
    }

    /// Update an existing loop, persist it, and push to the daemon.
    public func updateLoop(_ loop: Loop) async throws {
        var updated = loop
        updated.lastActivityAt = .now
        try await loopRepo.upsert(updated)
        try? await channel?.updateLoop(updated)
        await refresh()
        if selectedLoop?.id == updated.id {
            selectedLoop = updated
        }
    }

    /// Delete a loop from the local database.
    public func deleteLoop(_ id: String) async throws {
        try await loopRepo.delete(id)
        if selectedLoop?.id == id { selectedLoop = nil }
        await refresh()
    }
}
#endif
