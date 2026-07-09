#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore
import SessionFeature
import AgentKit

/// Work Thread transcript backed by the persisted mirror (`ChatTurn` rows +
/// artifacts), with a live overlay on the active run's last row. Bound to a
/// stable `conversationID` route — bridge `activeThread*` fields only overlay
/// the in-flight turn, never replace prior history.
public struct CursorWorkThreadView: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let routedConversationID: String?
    private let fallbackTitle: String
    private let onBack: () -> Void
    private let onViewPR: () -> Void
    private let onOpenReview: () -> Void
    private let onOpenComposer: () -> Void
    private let onOpenComposerPrefilled: (String) -> Void

    @State private var transcriptModel = CursorThreadTranscriptModel()
    @State private var returnPacketPresentation: ReturnPacketPresentation?
    @State private var copiedToastText: String?

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    private struct ReturnPacketPresentation: Identifiable {
        let receipt: ProofReceipt
        var id: String { receipt.runId }
    }

    private var effectiveConversationID: String? {
        routedConversationID ?? liveBridge?.selectedThreadID
    }

    private var isActiveRoutedThread: Bool {
        guard let liveBridge, let effectiveConversationID else { return false }
        return liveBridge.selectedThreadID == effectiveConversationID
    }

    private var headerTitle: String {
        if let title = transcriptModel.conversationTitle, !title.isEmpty {
            return title
        }
        if let prompt = liveBridge?.activeThreadPrompt, !prompt.isEmpty {
            return prompt
        }
        return fallbackTitle
    }

    private var showsApprovalBanner: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LANCER_UITEST_RESEED"] == "1" {
            return true
        }
        #endif
        guard let liveBridge else { return true }
        return liveBridge.pendingApprovalID != nil
    }

    public init(
        routedConversationID: String? = nil,
        fallbackTitle: String = "Thread",
        onBack: @escaping () -> Void = {},
        onViewPR: @escaping () -> Void = {},
        onOpenReview: @escaping () -> Void = {},
        onOpenComposer: @escaping () -> Void = {},
        onOpenComposerPrefilled: @escaping (String) -> Void = { _ in }
    ) {
        self.routedConversationID = routedConversationID
        self.fallbackTitle = fallbackTitle
        self.onBack = onBack
        self.onViewPR = onViewPR
        self.onOpenReview = onOpenReview
        self.onOpenComposer = onOpenComposer
        self.onOpenComposerPrefilled = onOpenComposerPrefilled
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if transcriptModel.rows.isEmpty {
                            startingPlaceholder
                        } else {
                            ForEach(transcriptModel.rows) { row in
                                transcriptRowView(row)
                                    .id(row.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                }
                .onChange(of: transcriptModel.rows.map(\.id)) { _, ids in
                    guard let last = ids.last else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .background(colors.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if showsApprovalBanner {
                    approvalBanner
                }
                composer
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(item: $returnPacketPresentation) { presentation in
            CursorReturnPacketView(
                receipt: presentation.receipt,
                workingDirectory: liveBridge?.activeThreadCWD,
                onDismiss: { returnPacketPresentation = nil }
            )
        }
        #if DEBUG
        .onAppear { applyDebugReturnPacketSeamIfNeeded() }
        #endif
        .overlay(alignment: .top) {
            if let copiedToastText {
                CursorCopiedToast(text: copiedToastText)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear { scheduleToastDismiss() }
            }
        }
        .onAppear {
            bindTranscript()
        }
        .onChange(of: effectiveConversationID) { _, _ in
            bindTranscript()
        }
        .onChange(of: liveBridge?.selectedThreadID) { _, _ in
            refreshTranscriptOverlay()
        }
        .onChange(of: liveBridge?.activeThreadResponse) { _, _ in
            refreshTranscriptOverlay()
        }
        .onChange(of: liveBridge?.activeThreadIsWorking) { _, isWorking in
            refreshTranscriptOverlay()
            if isWorking == false {
                Task { await transcriptModel.reload() }
            }
        }
        .onChange(of: liveBridge?.activeThreadError) { _, _ in
            refreshTranscriptOverlay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lancerChatArtifactPersisted)) { _ in
            Task { await transcriptModel.reload() }
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
            bridgeErrorBanner(message: message)
        }
    }

    @ViewBuilder
    private func turnSectionView(_ section: CursorTranscriptRow.TurnSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            userPromptBubble(section.prompt)
            assistantBody(for: section)
            if let error = section.turnError, !error.isEmpty {
                turnErrorText(error)
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
            if let response = overlay.response, !response.isEmpty {
                Text(response)
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.primaryText)
                    .textSelection(.enabled)
            } else if overlay.isWorking {
                logLine("Working…")
            } else if section.assistantText.isEmpty {
                logLine("Starting…")
            } else {
                Text(section.assistantText)
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.primaryText)
                    .textSelection(.enabled)
            }
        } else if !section.assistantText.isEmpty {
            Text(section.assistantText)
                .font(CursorType.bodyText)
                .foregroundColor(colors.primaryText)
                .textSelection(.enabled)
        } else if section.artifacts.isEmpty {
            logLine("No output recorded for this turn.")
        }
    }

    private var startingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let prompt = liveBridge?.activeThreadPrompt, !prompt.isEmpty {
                userPromptBubble(prompt)
            }
            if liveBridge?.activeThreadIsWorking == true {
                logLine("Working…")
            } else {
                logLine("Starting…")
            }
        }
    }

    private func bridgeErrorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(CursorType.bodyText)
                .foregroundColor(colors.dangerRed)
            HStack(spacing: 12) {
                Button("Retry", action: handleRetry)
                    .font(CursorType.rowTitle)
                    .foregroundColor(colors.primaryText)
                Button("Refresh", action: handleRefresh)
                    .font(CursorType.rowTitle)
                    .foregroundColor(colors.primaryText)
            }
        }
        .padding(14)
        .background(colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous))
        .accessibilityIdentifier("work-thread-bridge-error-banner")
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

    private func scheduleToastDismiss() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1600))
            withAnimation(.easeInOut(duration: 0.2)) { copiedToastText = nil }
        }
    }

    private func showCopiedToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) { copiedToastText = text }
    }

    private var approvalBanner: some View {
        CursorApprovalBanner(
            count: 1,
            onApprove: handleApprovalApprove,
            onReject: handleApprovalReject,
            onOpenReview: onOpenReview
        )
        .accessibilityIdentifier("approval-banner")
        .padding(.horizontal, CursorMetrics.actionRailHorizontalPadding)
        .padding(.top, CursorMetrics.actionRailVerticalPadding)
    }

    private func handleApprovalApprove() {
        if let liveBridge, let approvalID = liveBridge.pendingApprovalID {
            Task { await liveBridge.onDecide?(approvalID, .approved) }
        } else {
            onOpenReview()
        }
    }

    private func handleApprovalReject() {
        guard let liveBridge, let approvalID = liveBridge.pendingApprovalID else { return }
        Task { await liveBridge.onDecide?(approvalID, .rejected) }
    }

    private var composer: some View {
        CursorBottomComposer(
            placeholder: "Follow up...",
            style: .followUp,
            onTap: onOpenComposer
        )
    }

    private var header: some View {
        HStack(spacing: CursorMetrics.headerSpacing) {
            CursorIconButton(systemImageName: "chevron.left", action: onBack)
            Spacer()
            threadOverflowMenu
        }
        .padding(.horizontal, CursorMetrics.headerHorizontalPadding)
        .padding(.top, CursorMetrics.headerTopPadding)
        .overlay(alignment: .center) {
            HStack(spacing: 6) {
                Text(headerTitle)
                    .font(CursorType.sheetTitle)
                    .foregroundColor(colors.primaryText)
                    .lineLimit(1)
                Image(systemName: "display")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.secondaryText)
            }
            .padding(.top, CursorMetrics.headerTopPadding)
        }
    }

    private var threadOverflowMenu: some View {
        Menu {
            Button { } label: { Label("Pin", systemImage: "pin") }
            Button { } label: { Label("Rename", systemImage: "pencil") }
            Button { } label: { Label("Mark as Unread", systemImage: "bell.badge") }
            Button { } label: { Label("Archive", systemImage: "archivebox") }
            Divider()
            Button {
                #if os(iOS)
                UIPasteboard.general.string = effectiveConversationID ?? fallbackTitle
                #endif
                showCopiedToast("Copied ID")
            } label: { Label("Copy ID", systemImage: "doc.on.doc") }
            Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }
        } label: {
            ZStack {
                Circle()
                    .fill(colors.iconButtonBackground)
                    .overlay(Circle().stroke(colors.iconButtonBorder, lineWidth: 1))
                    .frame(width: CursorMetrics.headerButtonDiameter, height: CursorMetrics.headerButtonDiameter)
                Image(systemName: "ellipsis")
                    .font(.system(size: CursorMetrics.headerIconSize, weight: .medium))
                    .foregroundColor(colors.primaryText)
            }
        }
        .accessibilityIdentifier("work-thread-overflow-menu")
    }

    private func userPromptBubble(_ prompt: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(prompt)
                .font(CursorType.bodyText)
                .foregroundColor(colors.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(colors.userBubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private func turnErrorText(_ message: String) -> some View {
        Text(message)
            .font(CursorType.bodyText)
            .foregroundColor(colors.dangerRed)
    }

    @ViewBuilder
    private func changesCard(for artifacts: [ChatArtifact]) -> some View {
        if let receipt = activeReceipt(in: artifacts), let files = receipt.filesTouched, !files.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Changes")
                        .font(CursorType.cardTitle)
                        .foregroundColor(colors.primaryText)
                    Text("\(files.count)")
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, CursorMetrics.cardPadding)
                .padding(.top, CursorMetrics.cardPadding)
                .padding(.bottom, 8)

                ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                    VStack(spacing: 0) {
                        HStack(spacing: CursorMetrics.rowSpacing) {
                            fileExtensionBadge(for: file.path)
                            Text(shortFileName(file.path))
                                .font(CursorType.rowTitle)
                                .foregroundColor(colors.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            CursorDiffStatText(added: file.additions, removed: file.deletions)
                        }
                        .padding(.horizontal, CursorMetrics.cardPadding)
                        .padding(.vertical, 10)
                        if index < files.count - 1 {
                            Rectangle()
                                .fill(colors.hairline)
                                .frame(height: CursorMetrics.rowHairlineHeight)
                                .padding(.leading, CursorMetrics.cardPadding + CursorMetrics.rowIconSize + CursorMetrics.rowSpacing)
                        }
                    }
                }
            }
            .background(colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: CursorMetrics.cardCornerRadius, style: .continuous))
            .accessibilityIdentifier("work-thread-changes-card")

            viewPRPill(files: files)
        }
    }

    private func activeReceipt(in artifacts: [ChatArtifact]) -> ProofReceipt? {
        artifacts.compactMap(ReceiptCardModel.decodeReceipt(from:)).first { receipt in
            !(receipt.filesTouched?.isEmpty ?? true)
        }
    }

    private func viewPRPill(files: [ProofReceipt.FileTouched]) -> some View {
        let added = files.reduce(0) { $0 + $1.additions }
        let removed = files.reduce(0) { $0 + $1.deletions }
        return HStack {
            CursorPillButton(
                segments: [
                    .init("View PR "),
                    .init("+\(added)", color: colors.successGreen),
                    .init(" -\(removed)", color: colors.dangerRed)
                ],
                style: .secondary,
                action: onViewPR
            )
            .accessibilityIdentifier("work-thread-view-pr-pill")
            Spacer()
        }
        .padding(.top, 4)
    }

    private func fileExtensionBadge(for path: String) -> some View {
        let ext = (path as NSString).pathExtension.uppercased()
        let label = ext.isEmpty ? "•" : String(ext.prefix(2))
        return Text(label)
            .font(CursorType.diffLineNumber)
            .foregroundColor(colors.mutedText)
            .frame(width: CursorMetrics.rowIconSize, height: CursorMetrics.rowIconSize)
    }

    private func shortFileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    @ViewBuilder
    private func artifactView(for artifact: ChatArtifact) -> some View {
        switch artifact.kind {
        case .receipt:
            if let receipt = ReceiptCardModel.decodeReceipt(from: artifact) {
                VStack(alignment: .leading, spacing: 10) {
                    ReceiptCardView(
                        artifact: artifact,
                        receipt: receipt,
                        workingDirectory: liveBridge?.activeThreadCWD,
                        onAccept: {
                            Task { await liveBridge?.onAcceptReceipt?(artifact) }
                        },
                        onRequestAnotherPass: { prefill in
                            liveBridge?.composerPrefillText = prefill
                            onOpenComposerPrefilled(prefill)
                        },
                        onOpenOnDesktop: { command in
                            #if os(iOS)
                            UIPasteboard.general.string = command
                            #endif
                        }
                    )
                    returnPacketEntryButton(for: receipt)
                }
            }
        case .question:
            QuestionCardView(artifact: artifact) { answer in
                Task { await liveBridge?.onAnswerQuestion?(artifact, answer) }
            }
        default:
            EmptyView()
        }
    }

    private func logLine(_ text: String) -> some View {
        Text(text)
            .font(CursorType.logLine)
            .foregroundColor(colors.secondaryText)
    }

    private func returnPacketEntryButton(for receipt: ProofReceipt) -> some View {
        Button {
            returnPacketPresentation = ReturnPacketPresentation(receipt: receipt)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 14, weight: .medium))
                Text("Return to desk")
                    .font(CursorType.bodyText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(colors.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(colors.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("return-packet-open")
        .disabled(ReturnPacketModel.continuationCommand(
            receipt: receipt,
            workingDirectory: liveBridge?.activeThreadCWD
        ) == nil)
        .opacity(
            ReturnPacketModel.continuationCommand(
                receipt: receipt,
                workingDirectory: liveBridge?.activeThreadCWD
            ) == nil ? 0.55 : 1
        )
    }

    #if DEBUG
    private func applyDebugReturnPacketSeamIfNeeded() {
        guard ProcessInfo.processInfo.environment["LANCER_RETURN_PACKET_AUTO_PRESENT"] == "1",
              let receipt = ReceiptCardModel.decodeReceipt(from: Self.mockReceiptArtifact) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            returnPacketPresentation = ReturnPacketPresentation(receipt: receipt)
        }
    }

    private static let mockReceiptArtifact: ChatArtifact = {
        let payload = """
        {"schema":"lancer.proof/v0","runId":"r-mock","conversationId":"c-mock","agent":"claude","status":"completed","exitCode":0,"contract":{"goal":"Add proof receipt card UI","doneCriteria":["Receipt card renders","Accept merges acceptedAt"],"validationCommands":["swift test --filter ReceiptCardModelTests"]},"commands":[{"command":"swift test --filter ReceiptCardModelTests","exitCode":0,"kind":"test"}],"filesTouched":[{"path":"Packages/LancerKit/Sources/SessionFeature/Chat/ReceiptCardView.swift","additions":120,"deletions":0}],"tests":{"ran":true,"passed":4,"failed":0},"criteria":[{"text":"Receipt card renders","status":"met","evidence":"ReceiptCardView.swift exists"},{"text":"UI tests pass","status":"unmet","evidence":"Return packet UITest pending"}],"git":{"startRef":"main","endRef":"spec/j3-return-to-desk-packet","dirtyAtStart":true,"worktreePath":"/Users/me/proj/.worktrees/j3-return-to-desk"},"confidence":{"commands":"complete","files":"complete","tests":"bestEffort"},"resume":{"agent":"claude","vendorSessionId":"sess-mock-ui"}}
        """
        return ChatArtifact(
            id: "receipt:r-mock",
            conversationID: "c-mock",
            turnID: "t-mock",
            runID: "r-mock",
            kind: .receipt,
            title: "Run proof",
            payloadJSON: payload,
            status: .done
        )
    }()
    #endif
}
#endif
