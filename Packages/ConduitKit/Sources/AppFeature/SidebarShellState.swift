import Foundation
import Observation
import ConduitCore
import PersistenceKit

public enum SidebarDestination: Hashable, Sendable {
    case home
    case newChat
    case thread(id: String)
    case needsAttention
    /// Machine Detail (Fleet) — a primary sidebar root, also reachable from a Home machine tap.
    case machines
    case settings
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
    public var searchResults: [ChatConversationSearchResult] = []
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
            recentThreads = try await repo.recent()
        } catch {
            recentThreads = []
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
}
