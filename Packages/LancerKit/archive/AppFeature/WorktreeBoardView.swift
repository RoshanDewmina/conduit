#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

/// Board view for multi-branch supervision — tracks worktrees across repos.
public struct WorktreeBoardView: View {
    private let store: WorktreeStore

    @Environment(\.lancerTokens) private var t

    public init(store: WorktreeStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSScreenHeader(
                    "worktrees",
                    breadcrumb: "branches & agents"
                ) {}

                if store.isLoading && store.worktrees.isEmpty {
                    loadingState
                } else if store.worktrees.isEmpty {
                    emptyState
                } else {
                    boardContent
                }
            }
        }
        .task {
            await store.refresh()
        }
    }

    // MARK: - Board

    private var boardContent: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                columnSection(
                    title: "Active",
                    tone: .ok,
                    count: store.activeWorktrees.count,
                    worktrees: store.activeWorktrees
                )

                columnSection(
                    title: "Review Ready",
                    tone: .info,
                    count: store.completedWorktrees.count,
                    worktrees: store.completedWorktrees
                )

                columnSection(
                    title: "Idle",
                    tone: .neutral,
                    count: store.idleWorktrees.count,
                    worktrees: store.idleWorktrees
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .refreshable {
            await store.refresh()
        }
    }

    private func columnSection(
        title: String,
        tone: DSChipTone,
        count: Int,
        worktrees: [Worktree]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.dsSansPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                DSChip("\(count)", tone: tone, variant: .solid, size: .sm)
            }
            .padding(.bottom, 4)

            if worktrees.isEmpty {
                emptyColumnCard
            } else {
                ForEach(worktrees) { worktree in
                    worktreeCard(worktree)
                }
            }
        }
        .frame(width: 280, alignment: .topLeading)
    }

    private var emptyColumnCard: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 18))
                .foregroundStyle(t.text4)
            Text("None")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .dsCard()
    }

    // MARK: - Card

    private func worktreeCard(_ worktree: Worktree) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: repo + branch
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(t.text3)
                Text(worktree.repoName)
                    .font(.dsSansPt(12, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(t.text3)
                Text(worktree.branch)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.accent)
                    .lineLimit(1)
            }

            if let agent = worktree.agentID {
                HStack(spacing: 4) {
                    DSStatusDot(tone: .ok, size: 6)
                    Text(agent)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text2)
                        .lineLimit(1)
                }
            }

            // Changed files
            if !worktree.changedFiles.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(t.text3)
                    Text("\(worktree.changedFiles.count) file\(worktree.changedFiles.count == 1 ? "" : "s") changed")
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(worktree.changedFiles.prefix(3)) { file in
                        HStack(spacing: 4) {
                            Text(file.statusIcon)
                                .font(.dsMonoPt(9))
                                .foregroundStyle(file.statusColor(tokens: t))
                            Text(file.path)
                                .font(.dsMonoPt(9))
                                .foregroundStyle(t.text3)
                                .lineLimit(1)
                        }
                    }
                    if worktree.changedFiles.count > 3 {
                        Text("+\(worktree.changedFiles.count - 3) more")
                            .font(.dsMonoPt(9))
                            .foregroundStyle(t.text4)
                    }
                }
            }

            // Last commit
            if let commit = worktree.lastCommit {
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.message)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text2)
                        .lineLimit(2)
                    Text(commit.hash.prefix(7).lowercased() + " · " + commit.author)
                        .font(.dsMonoPt(9))
                        .foregroundStyle(t.text4)
                }
            }

            // Status chip + timestamp
            HStack {
                DSChip(
                    worktree.status.rawValue,
                    tone: statusChipTone(worktree.status),
                    variant: .outlined,
                    size: .sm
                )
                Spacer()
                Text(worktree.lastActivity, style: .relative)
                    .font(.dsMonoPt(9))
                    .foregroundStyle(t.text4)
            }
        }
        .padding(12)
        .dsCard()
        .onTapGesture { store.selectWorktree(worktree) }
    }

    // MARK: - Helpers

    private func statusChipTone(_ status: Worktree.Status) -> DSChipTone {
        switch status {
        case .active:    return .ok
        case .idle:      return .neutral
        case .completed: return .info
        case .stale:     return .warn
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(t.accent)
            Text("Loading worktrees…")
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        DSEmptyState(
            icon: .folder,
            title: "No worktrees found",
            subtitle: "Connect a host with active branches to see multi-branch supervision.",
            action: nil
        )
    }
}

// MARK: - ChangedFile helpers

private extension Worktree.ChangedFile {
    var statusIcon: String {
        switch status {
        case .added:    return "+"
        case .modified: return "~"
        case .deleted:  return "-"
        case .renamed:  return "→"
        }
    }

    func statusColor(tokens: LancerTokens) -> Color {
        switch status {
        case .added:    return tokens.ok
        case .modified: return tokens.accent
        case .deleted:  return tokens.danger
        case .renamed:  return tokens.info
        }
    }
}

// MARK: - DSEmptyState (shared fallback)

private struct DSEmptyState: View {
    let icon: DSIcon
    let title: String
    let subtitle: String
    let action: (label: String, handler: (() -> Void)?)?

    @Environment(\.lancerTokens) private var t

    var body: some View {
        VStack(spacing: 12) {
            DSIconView(icon, size: 28, color: t.text4)
            Text(title)
                .font(.dsSansPt(15, weight: .medium))
                .foregroundStyle(t.text2)
            Text(subtitle)
                .font(.dsSansPt(13))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action, let handler = action.handler {
                DSButton(action.label, variant: .primary) { handler() }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
    }
}
#endif
