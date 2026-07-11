#if os(iOS)
import SwiftUI

/// Section 7 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile thread detail screen (owner reference screenshots
/// `IMG_2412`/`IMG_2410`). Pushed via `NavigationLink` when tapping a thread
/// row in `ThreadListView` (Section 5) or `WorkspacesView`'s DEBUG seam.
/// Visual-only for this milestone — the user message, assistant response,
/// table, and changed files are entirely invented static content, not real
/// `SessionFeature`/chat-engine output. The "..." menu, the "Changes" file
/// row, and "Squash & Merge" are decorative (no gesture handler, matching
/// the "line.3.horizontal" precedent in `ThreadListView`). "View PR" is the
/// one functional push, to `PRDetailView`. System `SF Symbols` + semantic
/// colors only, no DesignSystem module.
struct ThreadDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isFollowUpPresented = false

    let thread: ThreadRow

    init(thread: ThreadRow) {
        self.thread = thread
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        userBubble
                            .padding(.top, 16)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Worked 26s")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)

                            assistantParagraph1
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)

                            assistantParagraph2
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                        }

                        summaryTable

                        wireframesLine
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)

                        changesCard

                        pillRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 96)
                }
            }

            Button {
                isFollowUpPresented = true
            } label: {
                followUpComposer
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Follow up"))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isFollowUpPresented) {
            NewChatComposerView()
        }
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

            Text(thread.title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)

            Spacer()

            circleButton(systemImage: "ellipsis")
                .accessibilityHidden(true)
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

    // MARK: - Message bubble

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)

            Text("Can you take a look at the onboarding flow and clean up the handoff between the permissions screen and account setup? It feels like there are a couple of redundant taps in there.")
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    // MARK: - Assistant prose (manual bold/inline-code substrings, no Markdown renderer)

    /// Built from an `AttributedString` so "step ordering" can be bolded
    /// inline without the deprecated `Text` `+` concatenation operator.
    private var assistantParagraph1: Text {
        var emphasis = AttributedString("step ordering")
        emphasis.inlinePresentationIntent = .stronglyEmphasized

        let combined = AttributedString("I went through the onboarding flow and found a few places where ")
            + emphasis
            + AttributedString(" was causing the redundant taps you mentioned. The permissions screen was requesting camera access before it was actually needed, which pushed users through an extra confirmation step later on.")
        return Text(combined)
    }

    /// Built from an `AttributedString` so "PermissionCoordinator" can carry
    /// its own monospaced font + color inline without the deprecated `Text`
    /// `+` concatenation operator.
    private var assistantParagraph2: Text {
        var code = AttributedString("PermissionCoordinator")
        code.font = .system(size: 15, design: .monospaced)
        code.foregroundColor = Color.primary

        let combined = AttributedString("The fix consolidates permission requests into a single ")
            + code
            + AttributedString(" pass and removes the duplicate account-setup confirmation screen. I also tightened up the transition animation so the flow feels like one continuous handoff instead of five separate screens.")
        return Text(combined)
    }

    // MARK: - Summary table

    private var summaryTable: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.summaryRows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 0) {
                    Text(row.label)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 96, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.leading, 14)

                    Divider()

                    Text(row.value)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.trailing, 14)
                        .padding(.leading, 12)
                }

                if index < Self.summaryRows.count - 1 {
                    Divider()
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

    /// Built from an `AttributedString` so the "Screens touched: " label can
    /// be bolded inline without the deprecated `Text` `+` concatenation
    /// operator.
    private var wireframesLine: Text {
        var label = AttributedString("Screens touched: ")
        label.inlinePresentationIntent = .stronglyEmphasized

        let combined = label + AttributedString("Welcome, Permissions, Account setup, Tutorial, Confirmation.")
        return Text(combined)
    }

    // MARK: - Changes card

    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Changes")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(Self.changedFiles.count)")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            ForEach(Array(Self.changedFiles.enumerated()), id: \.offset) { index, file in
                changedFileRow(file)

                if index < Self.changedFiles.count - 1 {
                    Divider()
                        .padding(.leading, 50)
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

    private func changedFileRow(_ file: ChangedFile) -> some View {
        HStack(spacing: 12) {
            fileBadge(file.badge)

            Text(file.name)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            diffStatText(added: file.added, removed: file.removed)
                .font(.system(size: 14))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Pills

    private var pillRow: some View {
        HStack(spacing: 10) {
            NavigationLink {
                PRDetailView()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.trianglehead.branch")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("View PR")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    diffStatText(added: Self.prAdded, removed: Self.prRemoved)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(
                    Capsule().strokeBorder(Color(.separator), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            Text("Squash & Merge")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(
                    Capsule().strokeBorder(Color(.separator), lineWidth: 0.5)
                )
        }
        .padding(.top, 4)
    }

    private var followUpComposer: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                )

            Text("Follow up...")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Spacer()

            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
    }

    // MARK: - Static sample data

    private struct SummaryRow {
        let label: String
        let value: String
    }

    private static let summaryRows: [SummaryRow] = [
        SummaryRow(label: "Priority", value: "High"),
        SummaryRow(label: "Owner", value: "You"),
        SummaryRow(label: "Reviewers", value: "2 requested"),
        SummaryRow(label: "Target", value: "This sprint"),
        SummaryRow(label: "Risk", value: "Low"),
    ]

    private static let changedFiles: [ChangedFile] = [
        ChangedFile(badge: "SW", name: "OnboardingCoordinator.swift", added: 96, removed: 18),
        ChangedFile(badge: "SW", name: "PermissionRequestView.swift", added: 46, removed: 0),
    ]

    private static let prAdded = 142
    private static let prRemoved = 18
}

// MARK: - Shared helpers (used by ThreadDetailView + PRDetailView)

struct ChangedFile: Identifiable {
    let id = UUID()
    let badge: String
    let name: String
    let added: Int
    let removed: Int
}

func fileBadge(_ text: String) -> some View {
    RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Color(.tertiarySystemFill))
        .frame(width: 28, height: 20)
        .overlay(
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        )
}

/// Built from an `AttributedString` so the added/removed counts keep
/// distinct colors without the deprecated `Text` `+` concatenation operator.
func diffStatText(added: Int, removed: Int) -> Text {
    var addedText = AttributedString("+\(added)")
    addedText.foregroundColor = Color.green
    var removedText = AttributedString(" -\(removed)")
    removedText.foregroundColor = Color.red
    return Text(addedText + removedText)
}

#Preview {
    NavigationStack {
        ThreadDetailView(thread: ThreadRow(title: "Fix onboarding flow", status: .checksPassed, diffStat: "+142 -18"))
    }
}
#endif
