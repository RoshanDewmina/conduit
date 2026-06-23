import Foundation
import Observation
import LancerCore
import PersistenceKit

public enum SidebarDestination: Hashable, Sendable {
    case home
    case newChat
    case thread(id: String)
    case needsAttention
    /// Machine Detail (Fleet) — a primary sidebar root, also reachable from a Home machine tap.
    case machines
    case settings
    /// A read-only transcript viewer for a session discovered on the host but not
    /// dispatched by Lancer (watch-only, Phase 1). `title`/`hostName` travel with
    /// the route since observed sessions aren't persisted in `recentThreads`.
    case observedSession(sessionId: String, title: String, hostName: String)
}

public enum SidebarSection: Hashable, Sendable {
    case home
    case actions
    case search
    case recentThreads
    case needsAttention
    case settings
}

@MainActor @Observable
public final class SidebarShellState {
    public var selectedDestination: SidebarDestination = .home
    public var previousDestination: SidebarDestination? = nil
    public var isDrawerOpen = false
    public var searchQuery = ""
    public var recentThreads: [ChatConversation] = []
    public var archivedThreads: [ChatConversation] = []
    public var searchResults: [ChatConversationSearchResult] = []
    /// Pinned conversation ids, persisted in UserDefaults (ponytail: no schema
    /// change — a small id set the sidebar sorts to the top is all pinning needs).
    public var pinnedIDs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: SidebarShellState.pinnedKey) ?? [])
    public var pendingApprovalCount = 0
    public var fleetSlotCount = 0

    private var chatRepo: ChatConversationRepository?

    public init(chatRepo: ChatConversationRepository? = nil) {
        self.chatRepo = chatRepo
    }

    public func configure(chatRepo: ChatConversationRepository) {
        self.chatRepo = chatRepo
    }

    /// The only route reducer for the sidebar shell. Keeping this transition here
    /// makes compact and split-view navigation agree about history and drawer state.
    public func navigate(to destination: SidebarDestination) {
        if selectedDestination != destination {
            previousDestination = selectedDestination
            selectedDestination = destination
        }
        isDrawerOpen = false
    }

    public func returnToPreviousDestination() {
        navigate(to: previousDestination ?? .home)
    }

    public func loadRecent() async {
        guard let repo = chatRepo else { return }
        do {
            recentThreads = try await repo.recent().filter { $0.status != .archived }
        } catch {
            recentThreads = []
        }
    }

    /// Loads archived conversations for the manage/archive view. Kept separate from
    /// `recentThreads` so the main sidebar list never has to filter on every render.
    public func loadArchived() async {
        guard let repo = chatRepo else { return }
        do {
            archivedThreads = try await repo.recent(limit: 200).filter { $0.status == .archived }
        } catch {
            archivedThreads = []
        }
    }

    public func performSearch() async {
        guard let repo = chatRepo else { return }
        do {
            searchResults = try await repo.search(searchQuery)
        } catch {
            searchResults = []
        }
    }

    /// Delete a conversation and refresh the recent list (+ search results if a
    /// query is active) so the row disappears immediately.
    public func deleteConversation(_ id: String) async {
        guard let repo = chatRepo else { return }
        try? await repo.deleteConversation(id)
        await loadRecent()
        archivedThreads.removeAll { $0.id == id }
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await performSearch()
        }
    }

    /// Rename a conversation and refresh so the new title shows immediately.
    public func renameConversation(_ id: String, to title: String) async {
        guard let repo = chatRepo else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repo.updateConversationTitle(id, title: trimmed)
        await loadRecent()
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await performSearch()
        }
    }

    /// Archive a conversation: it drops out of the main recent list immediately and
    /// surfaces in `archivedThreads` instead.
    public func archiveConversation(_ id: String) async {
        guard let repo = chatRepo else { return }
        try? await repo.updateConversationStatus(id, status: .archived)
        await loadRecent()
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await performSearch()
        }
    }

    /// Restore an archived conversation back to active so it reappears in the recent list.
    public func unarchiveConversation(_ id: String) async {
        guard let repo = chatRepo else { return }
        try? await repo.updateConversationStatus(id, status: .active)
        await loadArchived()
        await loadRecent()
    }

    public func isPinned(_ id: String) -> Bool { pinnedIDs.contains(id) }

    /// Toggle a conversation's pinned state (persisted). Pinned threads sort to the
    /// top of the recent list.
    public func togglePinned(_ id: String) {
        if pinnedIDs.contains(id) { pinnedIDs.remove(id) } else { pinnedIDs.insert(id) }
        UserDefaults.standard.set(Array(pinnedIDs), forKey: Self.pinnedKey)
    }

    /// Recent threads with pinned ones first (each group keeps its recency order).
    public var orderedRecentThreads: [ChatConversation] {
        let pinned = recentThreads.filter { pinnedIDs.contains($0.id) }
        let rest = recentThreads.filter { !pinnedIDs.contains($0.id) }
        return pinned + rest
    }

    static let pinnedKey = "lancer.pinnedConversations"
}
