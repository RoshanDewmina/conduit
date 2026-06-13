#if os(iOS)
import SwiftUI
import DesignSystem
import ConduitCore
import KeysFeature
import PersistenceKit
import SecurityKit
import SettingsFeature

// MARK: - Screen 6: KeysManagementView

public struct KeysManagementView: View {
    let keyStore: KeyStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    @State private var vm: KeysViewModel
    @State private var copiedTag: String? = nil

    // Mock host-count associations (TODO: wire real per-key host tracking)
    private let mockHostCounts: [Int] = [3, 1, 0]

    public init(keyStore: KeyStore) {
        self.keyStore = keyStore
        _vm = State(initialValue: KeysViewModel(store: keyStore))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("ssh keys", onBack: { dismiss() }) {
                    DSIconButton(.plus) {
                        Task { await vm.generate() }
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Generate dashed row
                        Button {
                            Task { await vm.generate() }
                        } label: {
                            HStack(spacing: 10) {
                                DSIconView(.plus, size: 14, color: t.accent)
                                Text("generate ed25519 key")
                                    .font(.dsMonoPt(13))
                                    .foregroundStyle(t.accent)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(t.accent.opacity(0.5))
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                        .buttonStyle(.plain)

                        if vm.keys.isEmpty {
                            DSEmptyState(
                                icon: .key,
                                title: "no keys yet",
                                subtitle: "Generate an Ed25519 key to authenticate without passwords."
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        } else {
                            DSListSectionHead("STORED KEYS", count: vm.keys.count)
                                .padding(.top, 8)

                            ForEach(Array(vm.keys.enumerated()), id: \.element.id) { idx, key in
                                keyRow(key, hostCount: idx < mockHostCounts.count ? mockHostCounts[idx] : 0)
                                DSDivider()
                            }
                        }
                    }
                }
            }

            // Copy confirmation toast
            if let tag = copiedTag {
                VStack {
                    Spacer()
                    Text("public key copied for \(tag)")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.textOnDark)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copiedTag = nil }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .animation(.easeInOut(duration: 0.2), value: copiedTag)
        .task { await vm.reload() }
    }

    private func keyRow(_ key: KeysViewModel.StoredKey, hostCount: Int) -> some View {
        HStack(spacing: 12) {
            DSIconView(.key, size: 16, color: t.accent)
                .frame(width: 36, height: 36)
                .background(t.accentSoft)
                .clipShape(Rectangle())

            VStack(alignment: .leading, spacing: 4) {
                Text(key.tag)
                    .font(.dsMonoPt(13, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    DSChip("ed25519", tone: .neutral, variant: .soft, size: .sm)
                    if hostCount > 0 {
                        DSChip("\(hostCount) host\(hostCount == 1 ? "" : "s")", tone: .ok, variant: .soft, size: .sm)
                    } else {
                        DSChip("unused", tone: .neutral, variant: .soft, size: .sm)
                    }
                }
            }

            Spacer()

            Button {
                UIPasteboard.general.string = key.openSSH
                withAnimation { copiedTag = key.tag }
            } label: {
                DSIconView(.copy, size: 16, color: t.text3)
                    .frame(width: 36, height: 36)
                    .background(t.surface)
                    .clipShape(Rectangle())
                    .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Screen 7: SnippetsLibraryView (M5a)

public struct SnippetsLibraryView: View {
    let repository: SnippetRepository

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    @State private var snippets: [Snippet] = []
    @State private var selectedFilter: SnippetFilter = .all
    @State private var isLoading = false

    private enum SnippetFilter: String, CaseIterable, Hashable, Sendable {
        case all, ops, debug, data
    }

    public init(repository: SnippetRepository) {
        self.repository = repository
    }

    private var filtered: [Snippet] {
        guard selectedFilter != .all else { return snippets }
        return snippets.filter { $0.tags.contains(selectedFilter.rawValue) }
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("snippets", onBack: { dismiss() })

                // Filter chips
                DSSegmentedPicker(
                    options: SnippetFilter.allCases.map { (label: $0.rawValue, value: $0) },
                    selection: $selectedFilter
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    DSEmptyState(
                        icon: .list,
                        title: "no snippets",
                        subtitle: "Create reusable shell commands to run on your hosts."
                    )
                    .padding(.horizontal, 24)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { snippet in
                                snippetRow(snippet)
                                DSDivider()
                            }
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            isLoading = true
            snippets = (try? await repository.all()) ?? []
            isLoading = false
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        HStack(spacing: 12) {
            DSIconView(.list, size: 14, color: t.accent)
                .frame(width: 32, height: 32)
                .background(t.accentSoft)
                .clipShape(Rectangle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snippet.name)
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                        .lineLimit(1)
                    if let tag = snippet.tags.first {
                        DSChip(tag, tone: .neutral, variant: .soft, size: .sm)
                    }
                }
                Text("$ \(snippet.body)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                // TODO: run snippet
            } label: {
                DSIconView(.arrowRight, size: 14, color: t.accent)
                    .frame(width: 32, height: 32)
                    .background(t.accentSoft)
                    .clipShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

#endif
