#if os(iOS)
import SwiftUI
import PersistenceKit
import SessionFeature
import SSHTransport
import LancerCore

/// How the composer is hosted. `.sheet` keeps detent / drag-handle chrome for
/// ThreadList and other sheet call sites; `.inline` is the Workspaces in-place morph.
public enum ComposerHostStyle: Sendable {
    case sheet
    case inline
}

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
    @State private var isVendorPickerPresented = false
    @State private var isContextPresented = false
    @State private var selectedRepo: WorkspaceRepo?
    @State private var attachments: [AttachmentDraft] = []
    @State private var isUploadingAttachments = false
    /// Sheet-level honesty when attachment upload aborts for missing transport.
    @State private var attachmentNoTransportBanner: String?
    @AppStorage(DispatchModelSelection.storageKey) private var selectedModelSlug: String =
        DispatchModelSelection.default.rawValue
    @AppStorage(DispatchVendorSelection.storageKey) private var selectedVendorSlug: String =
        DispatchVendorSelection.default.rawValue
    @AppStorage(FullToolsSelection.storageKey) private var fullToolsEnabled: Bool =
        FullToolsSelection.default
    private let initiallyShowsRepoPicker: Bool
    private let lockRepo: Bool
    private let hostStyle: ComposerHostStyle
    /// Inline host only — swipe-down / explicit collapse (sheet uses `dismiss`).
    private let onCollapse: (() -> Void)?
    /// Hands (clean prompt, cwd, attachment refs) to the presenting view.
    /// Cwd is always the selected repo's real path — missing selection blocks send.
    private let onSend: (_ prompt: String, _ cwd: String, _ attachments: [ConversationAttachmentReference]) -> Void

    private var selectedModel: DispatchModelSelection {
        DispatchModelSelection.resolve(selectedModelSlug)
    }

    private var selectedVendor: DispatchVendorSelection {
        DispatchVendorSelection.resolve(selectedVendorSlug)
    }

    /// "Full tools" only means anything for claudeCode (`--strict-mcp-config`
    /// is claudeCode-only, dispatch.go's agentArgv) — hidden for every other
    /// vendor rather than shown-but-inert.
    private var showFullToolsToggle: Bool { selectedVendor.usesClaudeModelPicker }

    private var showFullToolsCaption: Bool { showFullToolsToggle && fullToolsEnabled }

    private var composerHeight: CGFloat {
        var height: CGFloat = attachments.isEmpty ? 280 : 340
        if showFullToolsCaption { height += 22 }
        return height
    }

    public init(
        initiallyShowsRepoPicker: Bool = false,
        initialRepo: WorkspaceRepo? = nil,
        lockRepo: Bool = false,
        hostStyle: ComposerHostStyle = .sheet,
        onCollapse: (() -> Void)? = nil,
        onSend: @escaping (_ prompt: String, _ cwd: String, _ attachments: [ConversationAttachmentReference]) -> Void
    ) {
        self.initiallyShowsRepoPicker = initiallyShowsRepoPicker
        self.hostStyle = hostStyle
        self.onCollapse = onCollapse
        self.onSend = onSend
        // A follow-up composer inside a thread is pinned to that thread's
        // folder — offering the picker there silently retargeted sends
        // (owner report 2026-07-12: Home thread offered command-center).
        self.lockRepo = lockRepo && initialRepo != nil
        _selectedRepo = State(initialValue: initialRepo)
    }

    public var body: some View {
        cardContent
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, hostStyle == .sheet ? 8 : 0)
            .padding(.top, hostStyle == .sheet ? 6 : 0)
            .modifier(ComposerSheetChromeModifier(
                enabled: hostStyle == .sheet,
                height: composerHeight
            ))
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
            .onDisappear {
                isTextFieldFocused = false
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
            .sheet(isPresented: $isVendorPickerPresented) {
                VendorPickerView(
                    selected: selectedVendor,
                    installed: relayFleetStore.firstConnectedMachine?.installedAgentVendors
                ) { vendor in
                    selectedVendorSlug = vendor.rawValue
                }
            }
            .sheet(isPresented: $isContextPresented) {
                ContextAttachView(attachments: $attachments)
            }
            .task {
                await refreshInstalledVendorsIfNeeded()
            }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hostStyle == .sheet {
                dragHandle
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            } else {
                Color.clear
                    .frame(height: 20)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(collapseDragGesture)
            }

            selectorRow
                .padding(.horizontal, 16)

            if !attachments.isEmpty {
                attachmentChips
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            if let attachmentNoTransportBanner {
                InlineRetryBanner(
                    title: attachmentNoTransportBanner,
                    message: "Connect a machine, then retry send.",
                    retryTitle: "Dismiss",
                    accessibilityRetryLabel: "Dismiss attachment upload error"
                ) {
                    self.attachmentNoTransportBanner = nil
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            textField
                .padding(.top, 10)

            bottomRow
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if showFullToolsCaption {
                Text("Slower first reply; enables MCP tools")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
                .frame(height: 14)
        }
    }

    private var dragHandle: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
    }

    private var collapseDragGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard value.translation.height > 72 else { return }
                isTextFieldFocused = false
                onCollapse?()
            }
    }

    private var selectorRow: some View {
        HStack(spacing: 18) {
            repoSelector
            Spacer()
        }
    }

    private var repoSelector: some View {
        Group {
            if lockRepo {
                Text(repoBranchLabel)
                    .font(.system(size: 15, weight: .medium))
            } else {
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
        }
    }

    /// Per-dispatch opt-out of `--strict-mcp-config` (default OFF = fast
    /// strict mode) — see `FullToolsSelection`'s doc comment for the tradeoff.
    /// Only rendered when `showFullToolsToggle` (claudeCode selected).
    private var fullToolsToggleChip: some View {
        Button {
            fullToolsEnabled.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Full tools")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(fullToolsEnabled ? Color.accentColor : Color(.secondaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(fullToolsEnabled ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("composer-full-tools-toggle")
        .accessibilityLabel(Text("Full tools"))
        .accessibilityValue(Text(fullToolsEnabled ? "On" : "Off"))
        .accessibilityHint(Text("Slower first reply; enables MCP tools"))
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
                isVendorPickerPresented = true
            } label: {
                HStack(spacing: 4) {
                    Text(selectedVendor.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Agent, \(selectedVendor.displayName)"))

            if selectedVendor.usesClaudeModelPicker {
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
            }

            if showFullToolsToggle {
                fullToolsToggleChip
            }

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
                .accessibilityIdentifier("composer.send")
            } else if !trimmedDraft.isEmpty {
                // Draft present but send blocked (no repo / upload in flight / errors).
                // No decorative mic — empty draft shows no trailing control.
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    )
                    .accessibilityHidden(true)
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
                let message = AttachmentUploadError.noTransport.localizedDescription
                for draft in drafts where draft.state == .pending {
                    drafts = AttachmentDraftStore.withState(
                        drafts, id: draft.id, state: .error(message: message)
                    )
                }
                publishDrafts(&drafts)
                attachmentNoTransportBanner = message
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
                    let receipt = try await AttachmentUploader.upload(
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
                        drafts, id: draft.id, state: .done(receipt)
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

        // Cache previews from draft bytes before clearing the composer.
        let refs = AttachmentDraftStore.references(from: drafts)
        if !refs.isEmpty {
            let cache = try? AttachmentPreviewCache()
            for draft in drafts {
                guard case .done = draft.state else { continue }
                if let preview = await AttachmentPreviewCache.makePreviewDataOffMain(
                    from: draft.data, mimeType: draft.mimeType
                ) {
                    try? cache?.storePreview(preview, for: draft.id.uuidString)
                }
            }
        }

        let cleanPrompt = prompt
        // Clear the bound TextEditor before collapsing — sheet `dismiss()` is
        // async, and the inline host unmounts on the same turn as live-thread
        // presentation. Leaving the just-sent prompt enumerable races the
        // live-thread bubble in AX-tree tests (2026-07-15 reconnect re-proof).
        draftText = ""
        isTextFieldFocused = false
        onSend(cleanPrompt, cwd, refs)
        // Inline: parent collapses immediately in onSend (no spring). Sheet: dismiss.
        if hostStyle == .sheet {
            dismiss()
        }
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
            return AttachmentUploader.ChunkResult(
                id: result.id,
                path: result.path,
                contentDigest: result.contentDigest,
                error: result.error
            )
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
        return AttachmentUploader.ChunkResult(
            id: result.id,
            path: result.path,
            contentDigest: result.contentDigest,
            error: result.error
        )
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

    /// Pulls host-installed vendor CLIs once per machine so the agent picker
    /// can hide CLIs that aren't on PATH. Best-effort — empty/failure keeps
    /// the full catalog visible.
    private func refreshInstalledVendorsIfNeeded() async {
        guard let machine = relayFleetStore.firstConnectedMachine else { return }
        if let existing = machine.installedAgentVendors, !existing.isEmpty { return }
        do {
            let vendors = try await machine.bridge.relayInstalledAgents()
            relayFleetStore.setInstalledAgentVendors(vendors, for: machine.id)
        } catch {
            // Leave installedAgentVendors nil → picker shows full catalog.
        }
    }
}

/// Sheet-only presentation chrome. No-ops when the composer is hosted inline.
private struct ComposerSheetChromeModifier: ViewModifier {
    let enabled: Bool
    let height: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .presentationDetents([.height(height)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        } else {
            content
        }
    }
}

#Preview {
    let db = try! PersistenceKit.AppDatabase.inMemory()
    Color(.systemGroupedBackground)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            NewChatComposerView(onSend: { _, _, _ in })
                .environment(WorkspaceDataStore(chatRepo: ChatConversationRepository(db)))
                .environment(RelayFleetStore())
        }
}
#endif
