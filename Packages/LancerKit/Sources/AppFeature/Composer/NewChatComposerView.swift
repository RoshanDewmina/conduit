#if os(iOS)
import SwiftUI
import PersistenceKit
import SessionFeature
import SSHTransport

/// New Chat composer — repo picker uses the real workspace list; send
/// requires a selected repo cwd (never a guessed `~/name`). Attachments
/// upload via `attachment.put` before the prompt is dispatched.
public struct NewChatComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceDataStore.self) private var workspaceData
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @State private var draftText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var isRepoPickerPresented = false
    @State private var isModelPickerPresented = false
    @State private var isContextPresented = false
    @State private var selectedRepo: WorkspaceRepo?
    @State private var attachments: [AttachmentDraft] = []
    @State private var isUploadingAttachments = false
    @AppStorage(DispatchModelSelection.storageKey) private var selectedModelSlug: String =
        DispatchModelSelection.default.rawValue
    private let initiallyShowsRepoPicker: Bool
    /// Hands (prompt, cwd) to the presenting view. Cwd is always the selected
    /// repo's real path — missing selection blocks send.
    private let onSend: (_ prompt: String, _ cwd: String) -> Void

    private var selectedModel: DispatchModelSelection {
        DispatchModelSelection.resolve(selectedModelSlug)
    }

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

            if !attachments.isEmpty {
                attachmentChips
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

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
        .presentationDetents([.height(attachments.isEmpty ? 280 : 340)])
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
        .sheet(isPresented: $isModelPickerPresented) {
            ModelPickerView(selected: selectedModel) { model in
                selectedModelSlug = model.rawValue
            }
        }
        .sheet(isPresented: $isContextPresented) {
            ContextAttachView(attachments: $attachments)
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

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { draft in
                    AttachmentChipView(draft: draft) {
                        attachments.removeAll { $0.id == draft.id }
                    }
                }
            }
        }
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
                isModelPickerPresented = true
            } label: {
                HStack(spacing: 4) {
                    Text(selectedModel.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Model, \(selectedModel.displayName)"))

            Spacer()

            let trimmedDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
            // Pending attachments upload on send; errored chips must be removed first.
            let sendAllowed = !trimmedDraft.isEmpty
                && selectedRepo != nil
                && !isUploadingAttachments
                && !attachments.contains(where: \.state.isError)
                && !attachments.contains(where: {
                    if case .uploading = $0.state { return true }
                    return false
                })

            if sendAllowed, let cwd = selectedRepo?.cwd {
                Button {
                    Task { await send(trimmedDraft, cwd: cwd) }
                } label: {
                    if isUploadingAttachments {
                        ProgressView()
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.tint)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUploadingAttachments)
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

    private func send(_ prompt: String, cwd: String) async {
        var drafts = attachments
        if !drafts.isEmpty {
            isUploadingAttachments = true
            let sshChannel = ApprovalRelay.shared.channel
            let relayMachine = relayFleetStore.firstConnectedMachine
            guard sshChannel != nil || relayMachine != nil else {
                for draft in drafts where draft.state == .pending {
                    drafts = AttachmentDraftStore.withState(
                        drafts, id: draft.id, state: .error(message: AttachmentUploadError.noTransport.localizedDescription)
                    )
                }
                publishDrafts(&drafts)
                isUploadingAttachments = false
                return
            }
            for draft in drafts {
                guard attachments.contains(where: { $0.id == draft.id }) else { continue }
                guard case .pending = draft.state else { continue }
                drafts = AttachmentDraftStore.withState(
                    drafts, id: draft.id, state: .uploading(progress: 0)
                )
                publishDrafts(&drafts)
                do {
                    let path = try await AttachmentUploader.upload(
                        draft: draft,
                        conversationId: nil,
                        sendChunk: { params in
                            try await self.putAttachmentChunk(
                                params,
                                sshChannel: sshChannel,
                                relayBridge: relayMachine?.bridge
                            )
                        },
                        onProgress: { progress in
                            drafts = AttachmentDraftStore.withState(
                                drafts, id: draft.id, state: .uploading(progress: progress)
                            )
                            publishDrafts(&drafts)
                        }
                    )
                    if !attachments.contains(where: { $0.id == draft.id }) {
                        isUploadingAttachments = false
                        return
                    }
                    drafts = AttachmentDraftStore.withState(
                        drafts, id: draft.id, state: .done(hostPath: path)
                    )
                    publishDrafts(&drafts)
                } catch {
                    drafts = AttachmentDraftStore.withState(
                        drafts, id: draft.id, state: .error(message: error.localizedDescription)
                    )
                    publishDrafts(&drafts)
                    isUploadingAttachments = false
                    return
                }
            }
            isUploadingAttachments = false
            guard AttachmentDraftStore.canSend(drafts) else { return }
        }

        let prefixed = AttachmentPromptPrefix.apply(
            userPrompt: prompt,
            hostPaths: AttachmentDraftStore.hostPaths(drafts)
        )
        onSend(prefixed, cwd)
        dismiss()
    }

    private func publishDrafts(_ drafts: inout [AttachmentDraft]) {
        let surviving = Set(attachments.map(\.id))
        drafts.removeAll { !surviving.contains($0.id) }
        attachments = drafts
    }

    /// The prompt dispatches through the relay machine (onSend → ShellLiveBridge),
    /// so the file must land on that same host; SSH is the no-relay fallback.
    private func putAttachmentChunk(
        _ params: AttachmentUploader.ChunkParams,
        sshChannel: DaemonChannel?,
        relayBridge: E2ERelayBridge?
    ) async throws -> AttachmentUploader.ChunkResult {
        if let relayBridge {
            let result = try await relayBridge.relayPutAttachment(
                conversationId: params.conversationId,
                name: params.name,
                totalBytes: params.totalBytes,
                seq: params.seq,
                dataBase64: params.dataBase64,
                done: params.done
            )
            return AttachmentUploader.ChunkResult(path: result.path, error: result.error)
        }
        guard let sshChannel else { throw AttachmentUploadError.noTransport }
        let result = try await sshChannel.putAttachment(
            conversationId: params.conversationId,
            name: params.name,
            totalBytes: params.totalBytes,
            seq: params.seq,
            dataBase64: params.dataBase64,
            done: params.done
        )
        return AttachmentUploader.ChunkResult(path: result.path, error: result.error)
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
                .environment(RelayFleetStore())
        }
}
#endif
