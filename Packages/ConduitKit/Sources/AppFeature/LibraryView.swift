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

    @State private var snippetCount: Int = 0
    @State private var keyCount: Int = 0
    @State private var recentSnippets: [Snippet] = []

    @Environment(\.conduitTokens) private var t

    public init(snippetRepo: SnippetRepository, keyStore: KeyStore) {
        self.snippetRepo = snippetRepo
        self.keyStore = keyStore
    }

    private var workflowCount: Int { LibraryMocks.workflows.count }
    private var agentCount: Int { LibraryMocks.agents.count }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSScreenHeader("library", breadcrumb: "your toolkit", spectrumMode: .idle) {
                    DSIconButton(.plus) { /* new snippet — TODO */ }
                }

                if snippetCount == 0 && keyCount == 0 && workflowCount == 0 && agentCount == 0 {
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
                                    KeysView(
                                        viewModel: KeysViewModel(store: keyStore),
                                        store: keyStore
                                    )
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
                                    WorkflowsView()
                                } label: {
                                    DSCategoryCard(
                                        icon: .diff,
                                        count: "\(workflowCount)",
                                        label: "Workflows",
                                        subtitle: "multi-step runs"
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    AgentsView()
                                } label: {
                                    DSCategoryCard(
                                        icon: .sparkles,
                                        count: "\(agentCount)",
                                        label: "Agents",
                                        subtitle: "claude · codex"
                                    )
                                }
                                .buttonStyle(.plain)
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
        .task { await loadCounts() }
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
