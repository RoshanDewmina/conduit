#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

// MARK: - WorktreesBoardView
// The full worktree management screen — list of all worktrees with status,
// agent, branch, and diff stats. Matches design 01 (WorktreeBoardView).

public struct WorktreesBoardView: View {
    let worktrees: [Worktree]
    let onCreateNew: () -> Void
    let onSelect: (Worktree) -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        worktrees: [Worktree] = [],
        onCreateNew: @escaping () -> Void = {},
        onSelect: @escaping (Worktree) -> Void = { _ in }
    ) {
        self.worktrees = worktrees
        self.onCreateNew = onCreateNew
        self.onSelect = onSelect
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSScreenHeader(
                    "worktrees",
                    breadcrumb: "parallel agents",
                    count: worktrees.isEmpty ? nil : "\(activeCount) active"
                ) {
                    DSIconButton(.plus, accessibilityLabel: "New worktree") {
                        Haptics.selection()
                        onCreateNew()
                    }
                }

                if worktrees.isEmpty {
                    emptyState
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(worktrees) { worktree in
                                worktreeRow(worktree)
                                    .padding(.horizontal, 18)
                                    .onTapGesture {
                                        Haptics.selection()
                                        onSelect(worktree)
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
    }

    // MARK: - Active count

    private var activeCount: Int {
        worktrees.filter { $0.status == .active }.count
    }

    // MARK: - Worktree row

    private func worktreeRow(_ w: Worktree) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                PixelAvatar(seed: w.agentID ?? w.branch, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(w.branch)
                        .font(.dsMonoPt(12, weight: .medium))
                        .foregroundStyle(t.text)
                        .lineLimit(1)
                    Text(agentLabel(for: w))
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                statusChip(for: w.status)
            }

            if !w.changedFiles.isEmpty || w.lastCommit != nil {
                HStack(spacing: 10) {
                    Spacer()
                    statsRow(w)
                    Text(relativeTime(w.lastActivity))
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text3)
                }
                .padding(.top, 8)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(t.divider)
                        .frame(height: 1)
                        .padding(.top, 7)
                }
            }
        }
        .padding(12)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(borderColor(for: w.status), lineWidth: 1)
        )
    }

    // MARK: - Stats row

    private func statsRow(_ w: Worktree) -> some View {
        HStack(spacing: 8) {
            let additions = w.changedFiles.count
            let deletions = w.lastCommit != nil ? w.changedFiles.filter { $0.status == .deleted }.count : 0

            if additions > 0 {
                HStack(spacing: 3) {
                    Text("+\(additions)")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.ok)
                }
            }
            if deletions > 0 {
                HStack(spacing: 3) {
                    Text("-\(deletions)")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.danger)
                }
            }
        }
    }

    // MARK: - Status chip

    @ViewBuilder
    private func statusChip(for status: Worktree.Status) -> some View {
        switch status {
        case .active:
            DSChip("running", tone: .ok, variant: .outlined, size: .sm, leadingDot: t.ok)
        case .idle:
            DSChip("idle", tone: .neutral, variant: .outlined, size: .sm)
        case .completed:
            DSChip("done", tone: .ok, variant: .outlined, size: .sm, leadingDot: t.ok)
        case .stale:
            DSChip("stale", tone: .warn, variant: .outlined, size: .sm, leadingDot: t.warn)
        }
    }

    // MARK: - Border color

    private func borderColor(for status: Worktree.Status) -> Color {
        switch status {
        case .active:   return t.border
        case .idle:     return t.border
        case .completed: return t.border
        case .stale:    return t.warn.opacity(0.45)
        }
    }

    // MARK: - Agent label

    private func agentLabel(for w: Worktree) -> String {
        let agent = w.agentID ?? "Unknown agent"
        let model = w.loopID ?? ""
        if model.isEmpty {
            return agent
        }
        return "\(agent) · \(model)"
    }

    // MARK: - Relative time

    private func relativeTime(_ date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins) min\(mins == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hrs = Int(interval / 3600)
            return "\(hrs) hr\(hrs == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        DSEmptyState(
            icon: .folder,
            title: "No worktrees",
            subtitle: "Create a worktree to isolate parallel agent work on separate branches.",
            action: (label: "New worktree", handler: onCreateNew)
        )
    }
}

#if DEBUG
#Preview {
    WorktreesBoardView(worktrees: [
        .sample,
        .sampleIdle,
        .sampleCompleted,
    ])
}
#endif
#endif
