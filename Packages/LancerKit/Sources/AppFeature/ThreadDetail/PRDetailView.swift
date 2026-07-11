#if os(iOS)
import SwiftUI

/// Section 7 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile PR detail screen (owner reference screenshot
/// `IMG_2411`). Pushed via the "View PR" pill on `ThreadDetailView`.
/// Visual-only for this milestone — title, stats, and the file list are
/// invented static content matching `ThreadDetailView`'s sample "Fix
/// onboarding flow" thread. The link-icon button, "..." menu, "Squash &
/// Merge" button, and the file row are all decorative (no gesture handler).
/// System `SF Symbols` + semantic colors only, no DesignSystem module.
public struct PRDetailView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        prTitleText
                            .font(.system(size: 22, weight: .bold))
                            .padding(.top, 20)

                        statLine

                        readyToMergeCard

                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(Self.changedFiles.count) File\(Self.changedFiles.count == 1 ? "" : "s")")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 8)

                            VStack(spacing: 0) {
                                ForEach(Array(Self.changedFiles.enumerated()), id: \.offset) { index, file in
                                    fileRow(file)

                                    if index < Self.changedFiles.count - 1 {
                                        Divider()
                                            .padding(.leading, 40)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color(.separator), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                circleButton(systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            Spacer()

            HStack(spacing: 12) {
                circleButton(systemImage: "link")
                    .accessibilityHidden(true)

                circleButton(systemImage: "ellipsis")
                    .accessibilityHidden(true)
            }
        }
    }

    private func circleButton(systemImage: String) -> some View {
        Circle()
            .fill(Color(.secondarySystemBackground))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
            )
    }

    /// Single `Text` built from an `AttributedString` so the title (primary)
    /// and PR number (secondary) keep distinct colors without the
    /// deprecated `Text` `+` concatenation operator.
    private var prTitleText: Text {
        var title = AttributedString("\(Self.prTitle) ")
        title.foregroundColor = Color.primary
        var number = AttributedString("#\(Self.prNumber)")
        number.foregroundColor = Color.secondary
        return Text(title + number)
    }

    // MARK: - Stat line

    private var statLine: some View {
        HStack(spacing: 8) {
            Text("Open")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.green.opacity(0.15)))

            chatDiffStatText(added: Self.prAdded, removed: Self.prRemoved)
                .font(.system(size: 14, design: .monospaced))

            Text("· \(Self.changedFiles.count) File · \(Self.commitCount) Commits")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Ready to merge card

    private var readyToMergeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to Merge")
                .font(.system(size: 16, weight: .semibold))

            HStack(spacing: 10) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    )

                Text("All Checks Passed")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
            }

            Text("Squash & Merge")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.green))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Text(file.name)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            chatDiffStatText(added: file.added, removed: file.removed)
                .font(.system(size: 14, design: .monospaced))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Static sample data (matches ThreadDetailView's "Fix onboarding flow" sample)

    private static let prTitle = "Fix onboarding flow: consolidate permissions + account setup"
    private static let prNumber = 47
    private static let prAdded = 142
    private static let prRemoved = 18
    private static let commitCount = 3

    private static let changedFiles: [ChangedFile] = [
        ChangedFile(badge: "SW", name: "OnboardingCoordinator.swift", added: 96, removed: 18),
        ChangedFile(badge: "SW", name: "PermissionRequestView.swift", added: 46, removed: 0),
    ]
}

#Preview {
    NavigationStack {
        PRDetailView()
    }
}
#endif
