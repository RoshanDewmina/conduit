#if os(iOS)
import SwiftUI
import DesignSystem
import ConduitCore
import SettingsFeature
import KeysFeature
import PersistenceKit
import SecurityKit

public struct LibraryView: View {
    let snippetRepo: SnippetRepository
    let keyStore: KeyStore
    @Bindable var agentStore: AgentStore

    @State private var snippetCount: Int = 0
    @State private var keyCount: Int = 0
    @State private var recentSnippets: [Snippet] = []
    @State private var pm = PurchaseManager.shared

    @Environment(\.conduitTokens) private var t

    public init(snippetRepo: SnippetRepository, keyStore: KeyStore, agentStore: AgentStore) {
        self.snippetRepo = snippetRepo
        self.keyStore = keyStore
        self.agentStore = agentStore
    }

    private var agentCount: Int { agentStore.hasCloudEntitlement ? agentStore.agents.count : 0 }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSScreenHeader("library", breadcrumb: "your toolkit", spectrumMode: .idle) {
                    DSIconButton(.plus) { /* new snippet — TODO */ }
                }

                if snippetCount == 0 && keyCount == 0 && !agentStore.hasCloudEntitlement {
                    Spacer()
                    DSEmptyState(
                        icon: .list,
                        title: "nothing saved",
                        subtitle: "Snippets, keys, and workflows you create will collect here for one-tap reuse."
                    )
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                                spacing: 12
                            ) {
                                NavigationLink {
                                    SnippetEditorView(repository: snippetRepo)
                                } label: {
                                    DSCategoryCard(
                                        icon: .list,
                                        count: "\(snippetCount)",
                                        label: "Snippets",
                                        subtitle: "reusable commands"
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    KeysView(viewModel: KeysViewModel(store: keyStore))
                                } label: {
                                    DSCategoryCard(
                                        icon: .key,
                                        count: "\(keyCount)",
                                        label: "SSH Keys",
                                        subtitle: "on-device keychain"
                                    )
                                }
                                .buttonStyle(.plain)

                                if agentStore.hasCloudEntitlement {
                                    NavigationLink {
                                        AgentsView(store: agentStore)
                                    } label: {
                                        DSCategoryCard(
                                            icon: .sparkles,
                                            count: "\(agentCount)",
                                            label: "Agents",
                                            subtitle: "hosted · SSH"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    cloudAgentsCard
                                }
                            }

                            if !recentSnippets.isEmpty {
                                VStack(spacing: 0) {
                                    DSListSectionHead("RECENT")
                                    ForEach(recentSnippets) { snippet in
                                        DSSnippetRow(
                                            name: snippet.name,
                                            snippetBody: snippet.body,
                                            useCount: snippet.useCount
                                        ) { /* run snippet — TODO */ }
                                        DSDivider()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .task {
            await pm.refreshCloudEntitlement()
            await loadCounts()
            await agentStore.loadAgents()
        }
    }

    private var cloudAgentsCard: some View {
        DSCategoryCard(
            icon: .sparkles,
            count: "—",
            label: "Agents",
            subtitle: "Conduit Cloud"
        )
        .opacity(0.55)
    }

    private func loadCounts() async {
        async let snippets = (try? snippetRepo.all()) ?? []
        async let tags = (try? keyStore.allTags()) ?? []
        let (s, k) = await (snippets, tags)
        snippetCount = s.count
        recentSnippets = Array(s.sorted { $0.useCount > $1.useCount }.prefix(3))
        keyCount = k.count
    }
}


private struct DSCategoryCard: View {
    let icon: DSIcon
    let count: String
    let label: String
    let subtitle: String

    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DSIconView(icon, size: 16, color: t.accent)
                Spacer()
                Text(count)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Text(label)
                .font(.dsSansPt(14, weight: .semibold))
                .foregroundStyle(t.text)
            Text(subtitle)
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text3)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(t.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DSSnippetRow: View {
    let name: String
    let snippetBody: String
    let useCount: Int
    let action: () -> Void

    @Environment(\.conduitTokens) private var t

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                DSIconView(.command, size: 14, color: t.text3)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.dsSansPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(snippetBody)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(useCount)x")
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

#endif
