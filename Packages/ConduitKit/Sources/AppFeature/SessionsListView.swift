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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                statusTabBar
                conversationsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 92)
            .padding(.bottom, 112)
        }
        .background(t.bg.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What should your agents do next?")
                .font(.dsDisplayPt(31, weight: .bold))
                .foregroundStyle(t.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Start a chat, resume recent work, or jump into anything waiting for your approval.")
                .font(.dsSansPt(15))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                StatusSummaryPill(label: "Chats", value: "\(conversations.count)", tone: t.text2)
                StatusSummaryPill(label: "Waiting", value: "\(conversations.filter(needsInput).count)", tone: t.warn)
                StatusSummaryPill(label: "Done", value: "\(conversations.filter(readyForReview).count)", tone: t.ok)
            }
            .padding(.top, 2)
        }
    }

    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This week")
                .font(.dsSansPt(17, weight: .semibold))
                .foregroundStyle(t.text2)
            if filteredConversations.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredConversations) { sessionRow($0) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            DSIconView(.terminal, size: 24, color: t.text3)
            Text("No chats here yet")
                .font(.dsSansPt(16, weight: .semibold))
                .foregroundStyle(t.text)
            Text("Use New chat to dispatch work to a connected agent.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 20)
        .background(t.surface, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border.opacity(0.65), lineWidth: 1)
        )
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

    private func sessionRow(_ conv: ChatConversation) -> some View {
        Button { onOpenThread(conv.id) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(t.surfaceSunk)
                            .frame(width: 48, height: 48)
                        Circle()
                            .fill(statusColor(for: conv))
                            .frame(width: 10, height: 10)
                            .offset(x: 2, y: -2)
                        DSIconView(needsInput(conv) ? .inbox : .terminal, size: 20, color: t.text3)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(conv.title.isEmpty ? conv.hostName : conv.title)
                                .font(.dsSansPt(17, weight: .semibold))
                                .foregroundStyle(t.text)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(conv.lastActivityAt, style: .relative)
                                .font(.dsSansPt(12, weight: .medium))
                                .foregroundStyle(t.text3)
                                .lineLimit(1)
                        }
                        Text("\(statusLabel(for: conv)) · \(conv.hostName)")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text3)
                            .lineLimit(1)
                    }
                }
                if needsInput(conv) {
                    HStack(spacing: 7) {
                        DSStatusDot(tone: .warn, size: 7)
                        Text("Needs your approval before the agent continues")
                            .font(.dsSansPt(13, weight: .medium))
                            .foregroundStyle(t.warn)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(t.warnSoft, in: RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                }
            }
            .padding(16)
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border.opacity(0.72), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(conv.title.isEmpty ? conv.hostName : conv.title)
    }

    private func statusLabel(for conv: ChatConversation) -> String {
        switch liveState(for: conv) {
        case .connected, .relayPaired: return "Connected"
        case .connecting: return "Connecting"
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(StatusTab.allCases, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        HStack(spacing: 7) {
                            Text(tab.rawValue)
                            Text("\(count(for: tab))")
                                .foregroundStyle(selectedTab == tab ? t.accentFg.opacity(0.75) : t.text3)
                        }
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? t.accentFg : t.text2)
                        .padding(.horizontal, 15)
                        .frame(height: 42)
                        .background(selectedTab == tab ? t.accent : t.surface2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func count(for tab: StatusTab) -> Int {
        switch tab {
        case .all: conversations.count
        case .needsInput: conversations.filter(needsInput).count
        case .readyForReview: conversations.filter(readyForReview).count
        }
    }
}

private struct StatusSummaryPill: View {
    let label: String
    let value: String
    let tone: Color
    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(tone).frame(width: 7, height: 7)
            Text(value)
                .font(.dsSansPt(13, weight: .bold))
                .foregroundStyle(t.text)
            Text(label)
                .font(.dsSansPt(12, weight: .medium))
                .foregroundStyle(t.text3)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(t.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(t.border.opacity(0.6), lineWidth: 1))
    }
}
#endif
