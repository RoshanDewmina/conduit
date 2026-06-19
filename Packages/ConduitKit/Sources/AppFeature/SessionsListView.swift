#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import PersistenceKit

public struct SessionsListView: View {
    let chatRepo: ChatConversationRepository
    let fleetStore: FleetStore
    let onOpenThread: (String) -> Void

    @State private var conversations: [ChatConversation] = []
    @State private var approvalArtifactsByConversation: [String: [ChatArtifact]] = [:]
    @State private var latestTurnIsTerminal: [String: Bool] = [:]
    @State private var selectedTab: StatusTab = .all
    @Environment(\.conduitTokens) private var t

    public enum StatusTab: String, CaseIterable {
        case all = "All", needsInput = "Needs input", readyForReview = "Ready for review"
    }

    public init(chatRepo: ChatConversationRepository, fleetStore: FleetStore, onOpenThread: @escaping (String) -> Void) {
        self.chatRepo = chatRepo
        self.fleetStore = fleetStore
        self.onOpenThread = onOpenThread
    }

    public var body: some View {
        VStack(spacing: 0) {
            DSScreenHeader("sessions", breadcrumb: "chats & hosts", count: "\(conversations.count) total")
            statusTabBar
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredConversations) { sessionRow($0) }
                }
            }
        }
        .background(t.bg.ignoresSafeArea())
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private func liveState(for conv: ChatConversation) -> Session.ConnectionState? {
        guard let hostIDString = conv.hostID,
              let slot = fleetStore.slots.first(where: { $0.hostID.uuidString == hostIDString })
        else { return nil }
        return fleetStore.connectionState(for: slot)
    }

    private func needsInput(_ conv: ChatConversation) -> Bool {
        guard let artifacts = approvalArtifactsByConversation[conv.id] else { return false }
        let pendingTitles = Set(fleetStore.slots.flatMap {
            $0.inboxVM.approvals.filter(\.isPending).map { $0.id.uuidString }
        })
        return artifacts.contains { $0.kind == .approval && pendingTitles.contains($0.title) }
    }

    private func readyForReview(_ conv: ChatConversation) -> Bool {
        latestTurnIsTerminal[conv.id] == true && !needsInput(conv)
    }

    private var filteredConversations: [ChatConversation] {
        switch selectedTab {
        case .all: return conversations
        case .needsInput: return conversations.filter(needsInput)
        case .readyForReview: return conversations.filter(readyForReview)
        }
    }

    private func loadAll() async {
        conversations = (try? await chatRepo.recent(limit: 50)) ?? []
        await fleetStore.refreshBridgeStatus()
        var artifactMap: [String: [ChatArtifact]] = [:]
        var terminalMap: [String: Bool] = [:]
        for conv in conversations {
            artifactMap[conv.id] = (try? await chatRepo.artifacts(conversationID: conv.id)) ?? []
            if let last = (try? await chatRepo.turns(conversationID: conv.id))?.last {
                terminalMap[conv.id] = (last.status == .completed || last.status == .failed)
            }
        }
        approvalArtifactsByConversation = artifactMap
        latestTurnIsTerminal = terminalMap
    }

    @ViewBuilder
    private func sessionRow(_ conv: ChatConversation) -> some View {
        Button { onOpenThread(conv.id) } label: {
            HStack(spacing: t.s3) {
                Circle().fill(statusColor(for: conv)).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: t.s1) {
                    Text(conv.title.isEmpty ? conv.hostName : conv.title)
                        .font(.dsMono(.callout, weight: .medium))
                        .foregroundStyle(t.text)
                        .lineLimit(1)
                    HStack(spacing: t.s1) {
                        Text(statusLabel(for: conv)).font(.dsMono(.caption2)).foregroundStyle(statusColor(for: conv))
                        Text("\u{00B7}").foregroundStyle(t.text4)
                        Text(conv.lastActivityAt, style: .relative).font(.dsMono(.caption2)).foregroundStyle(t.text4)
                    }
                }
                Spacer()
                if needsInput(conv) { DSChip("needs input", tone: .warn, variant: .soft, size: .sm) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        Rectangle().fill(t.border).frame(height: 0.5).padding(.horizontal, 18)
    }

    private func statusLabel(for conv: ChatConversation) -> String {
        switch liveState(for: conv) {
        case .connected, .relayPaired: return "Connected"
        case .connecting: return "Connecting\u{2026}"
        case .failed: return "Connection failed"
        case .offline, .none: return "Disconnected"
        }
    }

    private func statusColor(for conv: ChatConversation) -> Color {
        switch liveState(for: conv) {
        case .connected, .relayPaired: return t.ok
        case .connecting: return t.warn
        case .failed: return t.danger
        case .offline, .none: return t.text4
        }
    }

    private var statusTabBar: some View {
        HStack(spacing: t.s2) {
            ForEach(StatusTab.allCases, id: \.self) { tab in
                Button { selectedTab = tab } label: {
                    Text(tab.rawValue)
                        .font(.dsMono(.caption, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? t.accentFg : t.text2)
                        .padding(.horizontal, t.s4)
                        .padding(.vertical, t.s2)
                        .background(selectedTab == tab ? t.accent : t.surface2)
                        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, t.s3)
    }
}
#endif