#if os(iOS)
import SwiftUI

/// Section 3 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile "New Chat composer" bottom sheet (owner reference
/// screenshots `IMG_2413`/`IMG_2415` — a rounded floating card over the
/// dimmed Workspaces background with the keyboard raised). Presented from
/// the Workspaces `+` button and the bottom composer pill. Visual-only for
/// this milestone — the repo/branch selector, cloud toggle, and model
/// picker are static sample data with no sub-sheets, no send action, and no
/// live wiring. System `SF Symbols` + semantic colors only, no
/// DesignSystem module.
public struct NewChatComposerView: View {
    @State private var draftText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var isRepoPickerPresented = false
    @State private var isContextPresented = false
    private let initiallyShowsRepoPicker: Bool

    public init(initiallyShowsRepoPicker: Bool = false) {
        self.initiallyShowsRepoPicker = initiallyShowsRepoPicker
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dragHandle
                .padding(.top, 8)
                .padding(.bottom, 6)

            selectorRow
                .padding(.horizontal, 16)

            textField
                .padding(.top, 10)

            bottomRow
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
        .onAppear {
            if initiallyShowsRepoPicker {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isRepoPickerPresented = true
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isTextFieldFocused = true
                }
            }
        }
        .sheet(isPresented: $isRepoPickerPresented) {
            RepoPickerView()
        }
        .sheet(isPresented: $isContextPresented) {
            ContextAttachView()
        }
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
    }

    private var selectorRow: some View {
        HStack(spacing: 18) {
            repoSelector
            cloudSelector
            Spacer()
        }
    }

    private var repoSelector: some View {
        Button {
            isRepoPickerPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(Self.repoBranchLabel)
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var cloudSelector: some View {
        Button {
            // Deferred to a later section.
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cloud")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var textField: some View {
        ZStack(alignment: .topLeading) {
            if draftText.isEmpty {
                Text("Plan, ask, build…")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(.placeholderText))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $draftText)
                .focused($isTextFieldFocused)
                .scrollContentBackground(.hidden)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .frame(height: 120)
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 12) {
            Button {
                isContextPresented = true
            } label: {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add context"))

            Button {
                // Model picker sub-sheet deferred to a later section.
            } label: {
                HStack(spacing: 4) {
                    Text(Self.sampleModelName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

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
    }

    // MARK: - Static sample data

    private static let sampleRepoName = "conduit"
    private static let sampleBranchName = "master"
    private static let sampleModelName = "Composer 2.5"

    /// Single `Text` built from an `AttributedString` so the repo name
    /// (primary) and branch name (secondary) keep distinct colors without
    /// the deprecated `Text` `+` concatenation operator.
    private static var repoBranchLabel: AttributedString {
        var repo = AttributedString("\(sampleRepoName) ")
        repo.foregroundColor = Color.primary
        var branch = AttributedString(sampleBranchName)
        branch.foregroundColor = Color.secondary
        return repo + branch
    }
}

#Preview {
    Color(.systemGroupedBackground)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            NewChatComposerView()
        }
}
#endif
