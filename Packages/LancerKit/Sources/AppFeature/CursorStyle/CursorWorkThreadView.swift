#if os(iOS)
import SwiftUI
import LancerCore
import SessionFeature
import AgentKit

/// Work Thread transcript + docked composer. Engine (mapper/model/pacer) unchanged.
public struct CursorWorkThreadView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let routedConversationID: String?
    private let fallbackTitle: String
    private let onBack: () -> Void
    private let onViewPR: () -> Void
    private let onOpenReview: () -> Void

    @State private var transcriptModel = CursorThreadTranscriptModel()
    @State private var streamingPacer = CursorStreamingTextPacer()
    @State private var scrollFollowState = CursorTranscriptAutoScrollPolicy.FollowState()
    @State private var bottomOffset: CGFloat = 0
    @State private var composerPrefill: String?

    private var effectiveConversationID: String? {
        routedConversationID ?? liveBridge?.selectedThreadID
    }

    private var isActiveRoutedThread: Bool {
        guard let liveBridge, let effectiveConversationID else { return false }
        return liveBridge.selectedThreadID == effectiveConversationID
    }

    private var headerTitle: String {
        if let title = transcriptModel.conversationTitle, !title.isEmpty { return title }
        if let prompt = liveBridge?.activeThreadPrompt, !prompt.isEmpty { return prompt }
        return fallbackTitle
    }

    private var showsApprovalBanner: Bool {
        liveBridge?.pendingApprovalID != nil
    }

    private var showsPendingQuestion: Bool {
        CursorQuestionCardModel.shouldShowCard(liveBridge?.pendingQuestion)
    }

    public init(
        routedConversationID: String? = nil,
        fallbackTitle: String = "Thread",
        onBack: @escaping () -> Void = {},
        onViewPR: @escaping () -> Void = {},
        onOpenReview: @escaping () -> Void = {}
    ) {
        self.routedConversationID = routedConversationID
        self.fallbackTitle = fallbackTitle
        self.onBack = onBack
        self.onViewPR = onViewPR
        self.onOpenReview = onOpenReview
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if transcriptModel.rows.isEmpty {
                        startingPlaceholder
                    } else {
                        ForEach(transcriptModel.rows) { row in
                            transcriptRowView(row).id(row.id)
                        }
                    }
                }
                .padding()
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            } action: { _, newValue in
                bottomOffset = newValue
                scrollFollowState = scrollFollowState.handlingScroll(offsetFromBottom: newValue)
            }
            .onChange(of: transcriptModel.rows.map(\.id)) { _, ids in
                handleNewRow(ids: ids, proxy: proxy)
            }
            .overlay(alignment: .bottom) {
                if CursorTranscriptAutoScrollPolicy.shouldShowJumpToLatest(
                    isFollowing: scrollFollowState.isFollowing,
                    hasContentBelow: !CursorTranscriptAutoScrollPolicy.isNearBottom(offsetFromBottom: bottomOffset)
                ) {
                    Button {
                        guard let last = transcriptModel.rows.last?.id else { return }
                        scrollFollowState = scrollFollowState.handlingJumpToLatest()
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    } label: {
                        Text(scrollFollowState.unreadCount > 0 ? "\(scrollFollowState.unreadCount) new" : "Jump to latest")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("work-thread-jump-to-latest")
                }
            }
        }
        .navigationTitle(headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: onBack)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if showsPendingQuestion, let question = liveBridge?.pendingQuestion {
                    CursorQuestionCard(
                        state: question,
                        onToggleOption: { itemIndex, label in
                            liveBridge?.togglePendingQuestionOption(itemIndex: itemIndex, label: label)
                        },
                        onSetFreeText: { itemIndex, text in
                            liveBridge?.setPendingQuestionFreeText(itemIndex: itemIndex, text: text)
                        },
                        onSubmit: {
                            Task { await liveBridge?.submitPendingQuestion() }
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                if showsApprovalBanner {
                    approvalBanner
                }
                composer
            }
        }
        .onAppear {
            liveBridge?.startQuestionPendingListener()
            bindTranscript()
        }
        .onChange(of: effectiveConversationID) { _, _ in bindTranscript() }
        .onChange(of: liveBridge?.selectedThreadID) { _, _ in refreshTranscriptOverlay() }
        .onChange(of: liveBridge?.activeThreadResponse) { _, _ in refreshTranscriptOverlay() }
        .onChange(of: liveBridge?.activeThreadIsWorking) { _, isWorking in
            refreshTranscriptOverlay()
            if isWorking == false {
                Task { await transcriptModel.reload() }
            }
        }
        .onChange(of: liveBridge?.activeThreadError) { _, _ in refreshTranscriptOverlay() }
        .onReceive(NotificationCenter.default.publisher(for: .lancerChatArtifactPersisted)) { _ in
            Task { await transcriptModel.reload() }
        }
        .task(id: effectiveConversationID) { await pollThreadWhileWorking() }
    }

    private func handleNewRow(ids: [String], proxy: ScrollViewProxy) {
        guard let last = ids.last else { return }
        scrollFollowState = scrollFollowState.handlingNewRow(offsetFromBottom: bottomOffset)
        guard scrollFollowState.isFollowing else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    private func pollThreadWhileWorking() async {
        guard let conversationID = effectiveConversationID else { return }
        var pollInFlight = false
        while !Task.isCancelled {
            let isWorking = (liveBridge?.activeThreadIsWorking == true) || transcriptModel.lastTurnIsRunning
            guard isWorking else { return }
            if !pollInFlight {
                pollInFlight = true
                if let onPoll = liveBridge?.onPollThread {
                    await onPoll(conversationID)
                }
                await transcriptModel.reload()
                refreshTranscriptOverlay()
                pollInFlight = false
            }
            let stillWorking = (liveBridge?.activeThreadIsWorking == true) || transcriptModel.lastTurnIsRunning
            guard stillWorking else { return }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func bindTranscript() {
        transcriptModel.configure(conversationID: effectiveConversationID)
        refreshTranscriptOverlay()
        if effectiveConversationID != nil {
            Task { await transcriptModel.reload() }
        }
    }

    private func refreshTranscriptOverlay() {
        transcriptModel.refreshRows(
            bridge: liveBridge,
            bridgeError: isActiveRoutedThread ? liveBridge?.activeThreadError : nil,
            isActiveThread: isActiveRoutedThread
        )
    }

    @ViewBuilder
    private func transcriptRowView(_ row: CursorTranscriptRow) -> some View {
        switch row {
        case .turnSection(let section):
            turnSectionView(section)
        case .bridgeErrorBanner(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).foregroundStyle(.red)
                HStack {
                    Button("Retry", action: handleRetry)
                    Button("Refresh", action: handleRefresh)
                }
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("work-thread-bridge-error-banner")
        }
    }

    @ViewBuilder
    private func turnSectionView(_ section: CursorTranscriptRow.TurnSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.prompt)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            assistantBody(for: section)
            if let group = section.toolCallGroup, !group.isEmpty {
                CursorToolCallGroupView(group: group)
            }
            if let error = section.turnError, !error.isEmpty {
                Text(error).foregroundStyle(.red)
            }
            ForEach(section.artifacts) { artifact in
                artifactView(for: artifact)
            }
            changesCard(for: section.artifacts)
        }
    }

    @ViewBuilder
    private func assistantBody(for section: CursorTranscriptRow.TurnSection) -> some View {
        if let overlay = section.liveOverlay {
            let resolved = CursorStreamingTextSmoother.resolvedDisplayText(
                overlayResponse: overlay.response,
                persistedAssistantText: section.assistantText
            )
            if !resolved.isEmpty {
                let displayed = streamingPacer.displayText.isEmpty ? resolved : streamingPacer.displayText
                CursorAssistantMarkdownView(text: displayed, onCopyCodeBlock: { UIPasteboard.general.string = $0 })
                    .textSelection(.enabled)
                    .task(id: section.turnID) { streamingPacer.reset(to: resolved) }
                    .onChange(of: resolved) { _, newValue in streamingPacer.ingest(newValue) }
            } else if let indicator = overlay.workingIndicator {
                Text(indicator.displayLabel)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("work-thread-working-indicator")
            } else if overlay.isWorking {
                Text(CursorWorkingIndicator.thinking.displayLabel)
                    .foregroundStyle(.secondary)
            } else {
                Text(CursorWorkingIndicator.starting.displayLabel)
                    .foregroundStyle(.secondary)
            }
        } else if !section.assistantText.isEmpty {
            CursorAssistantMarkdownView(text: section.assistantText, onCopyCodeBlock: { UIPasteboard.general.string = $0 })
                .textSelection(.enabled)
        } else if section.artifacts.isEmpty, section.toolCallGroup == nil {
            Text("No output recorded for this turn.").foregroundStyle(.secondary)
        }
    }

    private var startingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prompt = liveBridge?.activeThreadPrompt, !prompt.isEmpty {
                Text(prompt)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            Text(
                (liveBridge?.activeThreadIsWorking == true
                    ? CursorWorkingIndicator.thinking
                    : CursorWorkingIndicator.starting).displayLabel
            )
            .foregroundStyle(.secondary)
        }
    }

    private func handleRetry() {
        guard let liveBridge, let conversationID = effectiveConversationID else { return }
        let prompt = liveBridge.activeThreadPrompt.isEmpty
            ? (transcriptModel.lastPersistedPrompt ?? "")
            : liveBridge.activeThreadPrompt
        guard !prompt.isEmpty else { return }
        let model = ManagedModel.cliDispatchSlug(for: liveBridge.composerModelSlug)
        liveBridge.activeThreadError = nil
        Task { await liveBridge.onContinue?(conversationID, prompt, model, nil) }
    }

    private func handleRefresh() {
        guard let liveBridge, let conversationID = effectiveConversationID else { return }
        liveBridge.activeThreadError = nil
        Task {
            await transcriptModel.reload()
            await liveBridge.onOpenThread?(conversationID)
            refreshTranscriptOverlay()
        }
    }

    private var approvalBanner: some View {
        HStack {
            Text("Approval pending")
            Spacer()
            Button("Review", action: onOpenReview)
            Button("Approve") {
                if let liveBridge, let approvalID = liveBridge.pendingApprovalID {
                    Task { await liveBridge.onDecide?(approvalID, .approved) }
                } else {
                    onOpenReview()
                }
            }
            Button("Reject", role: .destructive) {
                guard let liveBridge, let approvalID = liveBridge.pendingApprovalID else { return }
                Task { await liveBridge.onDecide?(approvalID, .rejected) }
            }
        }
        .padding(8)
        .background(.bar)
        .accessibilityIdentifier("approval-banner")
    }

    private var composer: some View {
        CursorDockedComposer(
            placeholder: "Follow up...",
            draftKey: effectiveConversationID,
            cwdResolution: .init(path: liveBridge?.activeThreadCWD ?? "~", blocked: false, message: nil),
            selectedModelID: liveBridge?.composerModelSlug,
            prefillText: composerPrefill,
            isWorking: liveBridge?.activeThreadIsWorking == true && isActiveRoutedThread,
            onSend: { prompt in
                guard let liveBridge, let conversationID = effectiveConversationID else { return }
                composerPrefill = nil
                let model = ManagedModel.cliDispatchSlug(for: liveBridge.composerModelSlug)
                liveBridge.activeThreadError = nil
                liveBridge.activeThreadPrompt = prompt
                Task { await liveBridge.onContinue?(conversationID, prompt, model, nil) }
            }
        )
        .onChange(of: composerPrefill) { _, newValue in
            guard newValue != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                composerPrefill = nil
            }
        }
    }

    @ViewBuilder
    private func changesCard(for artifacts: [ChatArtifact]) -> some View {
        if let receipt = artifacts.compactMap(ReceiptCardModel.decodeReceipt(from:)).first(where: {
            !($0.filesTouched?.isEmpty ?? true)
        }), let files = receipt.filesTouched, !files.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Changes (\(files.count))").font(.headline)
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    HStack {
                        Text((file.path as NSString).lastPathComponent)
                        Spacer()
                        Text("+\(file.additions)").foregroundStyle(.green)
                        Text("-\(file.deletions)").foregroundStyle(.red)
                    }
                    .font(.caption)
                }
                Button("View PR", action: onViewPR)
                    .accessibilityIdentifier("work-thread-view-pr-pill")
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("work-thread-changes-card")
        }
    }

    @ViewBuilder
    private func artifactView(for artifact: ChatArtifact) -> some View {
        switch artifact.kind {
        case .receipt:
            if let receipt = ReceiptCardModel.decodeReceipt(from: artifact) {
                ReceiptCardView(
                    artifact: artifact,
                    receipt: receipt,
                    workingDirectory: liveBridge?.activeThreadCWD,
                    onAccept: { Task { await liveBridge?.onAcceptReceipt?(artifact) } },
                    onRequestAnotherPass: { prefill in composerPrefill = prefill },
                    onOpenOnDesktop: { command in UIPasteboard.general.string = command }
                )
            }
        case .question:
            if CursorQuestionCardModel.shouldSuppressTranscriptArtifact(
                artifact: artifact,
                pending: liveBridge?.pendingQuestion
            ) {
                EmptyView()
            } else {
                QuestionCardView(artifact: artifact) { answer in
                    Task { await liveBridge?.onAnswerQuestion?(artifact, answer) }
                }
            }
        default:
            EmptyView()
        }
    }
}
#endif
