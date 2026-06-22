#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

// MARK: - WorktreeConflictsView
// Merge conflict resolution screen — overlapping files across worktrees,
// explanation, and rebase action. Matches design 04 (WorktreeConflicts).

public struct WorktreeConflictsView: View {
    public struct ConflictFile: Identifiable {
        public let id = UUID()
        public let filePath: String
        public let worktreeBranch: String
        public let isOwnBranch: Bool

        public init(filePath: String, worktreeBranch: String, isOwnBranch: Bool = false) {
            self.filePath = filePath
            self.worktreeBranch = worktreeBranch
            self.isOwnBranch = isOwnBranch
        }
    }

    let conflictCount: Int
    let overlappingFiles: [ConflictFile]
    let onDismiss: () -> Void
    let onRebase: () -> Void

    @Environment(\.lancerTokens) private var t

    public init(
        conflictCount: Int = 0,
        overlappingFiles: [ConflictFile] = [],
        onDismiss: @escaping () -> Void = {},
        onRebase: @escaping () -> Void = {}
    ) {
        self.conflictCount = conflictCount
        self.overlappingFiles = overlappingFiles
        self.onDismiss = onDismiss
        self.onRebase = onRebase
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSScreenHeader(
                    "conflicts",
                    breadcrumb: "merge resolution",
                    count: "\(conflictCount) overlap\(conflictCount == 1 ? "" : "s")"
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Warning banner
                        warningBanner

                        // Overlapping files section
                        if !overlappingFiles.isEmpty {
                            DSListSectionHead("OVERLAPPING FILES", count: overlappingFiles.count)
                            VStack(spacing: 6) {
                                ForEach(overlappingFiles) { file in
                                    conflictFileRow(file)
                                }
                            }
                            .padding(.horizontal, 18)
                        }

                        // Explanation
                        explanationCard

                        // Action buttons
                        actionButtons
                            .padding(.horizontal, 18)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: - Warning banner

    private var warningBanner: some View {
        HStack(spacing: 10) {
            DSIconView(.alertTri, size: 16, color: t.warn)
            Text("\(conflictCount) worktree\(conflictCount == 1 ? "" : "s") touch the same files")
                .font(.dsMonoPt(11, weight: .medium))
                .foregroundStyle(t.warn)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(t.warnSoft)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.warn.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    // MARK: - Conflict file row

    private func conflictFileRow(_ file: ConflictFile) -> some View {
        HStack(spacing: 8) {
            Text(file.filePath)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(file.worktreeBranch)
                .font(.dsMonoPt(10))
                .foregroundStyle(file.isOwnBranch ? LancerTokens.riskOrange : t.ok)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    // MARK: - Explanation card

    private var explanationCard: some View {
        Text("Agents on these worktrees cannot merge independently. Serialize the worktrees or rebase one onto master to resolve overlaps before conflict resolution.")
            .font(.dsMonoPt(11))
            .foregroundStyle(t.text3)
            .lineSpacing(4)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            DSButton("Dismiss", variant: .secondary, size: .md) {
                Haptics.selection()
                onDismiss()
            }

            DSButton("Rebase onto master", variant: .primary, size: .md) {
                Haptics.selection()
                onRebase()
            }
        }
    }
}

#if DEBUG
#Preview {
    WorktreeConflictsView(
        conflictCount: 2,
        overlappingFiles: [
            .init(filePath: "src/relay/handler.swift", worktreeBranch: "feat/relay-fix", isOwnBranch: true),
            .init(filePath: "src/relay/connection.swift", worktreeBranch: "feat/relay-fix", isOwnBranch: true),
            .init(filePath: "src/relay/handler.swift", worktreeBranch: "fix/connection-timeout", isOwnBranch: false),
        ]
    )
}
#endif
#endif
