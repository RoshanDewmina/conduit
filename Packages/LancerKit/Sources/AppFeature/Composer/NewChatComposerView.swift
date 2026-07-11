#if os(iOS)
import SwiftUI
import PersistenceKit

/// New Chat composer — repo picker uses the real workspace list; send
/// requires a selected repo cwd (never a guessed `~/name`).
public struct NewChatComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceDataStore.self) private var workspaceData
    @State private var draftText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var isRepoPickerPresented = false
    @State private var isContextPresented = false
    @State private var selectedRepo: WorkspaceRepo?
    private let initiallyShowsRepoPicker: Bool
    /// Hands (prompt, cwd) to the presenting view. Cwd is always the selected
    /// repo's real path — missing selection blocks send.
    private let onSend: (_ prompt: String, _ cwd: String) -> Void

    public init(
        initiallyShowsRepoPicker: Bool = false,
        initialRepo: WorkspaceRepo? = nil,
        onSend: @escaping (_ prompt: String, _ cwd: String) -> Void
    ) {
        self.initiallyShowsRepoPicker = initiallyShowsRepoPicker
        self.onSend = onSend
        _selectedRepo = State(initialValue: initialRepo)
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
            if selectedRepo == nil {
                selectedRepo = workspaceData.repos.first
            }
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
            RepoPickerView(
                repos: workspaceData.repos,
                selectedCwd: selectedRepo?.cwd,
                onSelect: { repo in
                    selectedRepo = repo
                }
            )
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
                Text(repoBranchLabel)
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
                    Text("Model")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            let trimmedDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            let canSend = !trimmedDraft.isEmpty && selectedRepo != nil
            if canSend, let cwd = selectedRepo?.cwd {
                Button {
                    send(trimmedDraft, cwd: cwd)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Send"))
            } else {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: trimmedDraft.isEmpty ? "mic.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    )
            }
        }
    }

    private func send(_ prompt: String, cwd: String) {
        onSend(prompt, cwd)
        dismiss()
    }

    private var repoBranchLabel: AttributedString {
        if let selectedRepo {
            var repo = AttributedString(selectedRepo.name)
            repo.foregroundColor = Color.primary
            return repo
        }
        var placeholder = AttributedString(
            workspaceData.repos.isEmpty ? "Add a repo first" : "Select a repo"
        )
        placeholder.foregroundColor = Color.secondary
        return placeholder
    }
}

#Preview {
    let db = try! PersistenceKit.AppDatabase.inMemory()
    Color(.systemGroupedBackground)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            NewChatComposerView(onSend: { _, _ in })
                .environment(WorkspaceDataStore(chatRepo: ChatConversationRepository(db)))
        }
}
#endif
