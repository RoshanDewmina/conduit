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

    private var workflowCount: Int { LibraryMocks.workflows.count }
    private var agentCount: Int { agentStore.hasCloudEntitlement ? agentStore.agents.count : 0 }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSScreenHeader("library", breadcrumb: "your toolkit", spectrumMode: .idle) {
                    DSIconButton(.plus) { /* new snippet — TODO */ }
                }

                if snippetCount == 0 && keyCount == 0 && workflowCount == 0 && !agentStore.hasCloudEntitlement {
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
                                    SnippetsLibraryView(repository: snippetRepo)
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
                                    KeysManagementView(keyStore: keyStore)
                                } label: {
                                    DSCategoryCard(
                                        icon: .key,
                                        count: "\(keyCount)",
                                        label: "SSH Keys",
                                        subtitle: "enclave-backed"
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    WorkflowBuilderView()
                                } label: {
                                    DSCategoryCard(
                                        icon: .diff,
                                        count: "\(workflowCount)",
                                        label: "Workflows",
                                        subtitle: "multi-step runs"
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
                                            body: snippet.body,
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
#endif
