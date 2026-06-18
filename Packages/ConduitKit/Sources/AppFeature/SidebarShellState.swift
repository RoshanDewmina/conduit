#if os(iOS)
import Foundation
import Observation
import ConduitCore
import PersistenceKit

public enum SidebarDestination: Hashable, Sendable {
    case newChat
    case thread(id: String)
    case needsAttention
    case fleet
    case settings
}

public enum SidebarSection: Hashable, Sendable {
    case actions
    case search
    case recentThreads
    case needsAttention
    case fleet
    case settings
}

@MainActor @Observable
public final class SidebarShellState {
    public var selectedDestination: SidebarDestination = .newChat
    public var isDrawerOpen = false
    public var searchQuery = ""
    public var recentThreads: [ChatConversation] = []
    public var searchResults: [ChatConversationSearchResult] = []
    public var pendingApprovalCount = 0
    public var fleetSlotCount = 0

    private let chatRepo: ChatConversationRepository?

    public init(chatRepo: ChatConversationRepository? = nil) {
        self.chatRepo = chatRepo
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
#endif
