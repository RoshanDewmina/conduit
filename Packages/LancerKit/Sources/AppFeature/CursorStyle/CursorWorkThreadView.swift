#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore
import SessionFeature

/// Work Thread transcript: a user prompt bubble followed by the run's real
/// live/final output text, with a floating sticky action rail above a
/// follow-up composer. Bound to `CursorShellLiveBridge.activeThread*` —
/// previously this rendered a single hardcoded example conversation
/// regardless of what was actually dispatched (2026-07-07: found via a real
/// device test — "the chat is just a template"). There is no real plan/
/// todo-checklist/diff-stat data anywhere in Lancer's V1 model, so those
/// cards are gone rather than filled with more fake content. Forces `.light`
/// to match the rest of the app.
public struct CursorWorkThreadView: View {
    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.cursorShellLiveBridge) private var liveBridge

    private let missionTitle: String
    private let onBack: () -> Void
    private let onViewPR: () -> Void
    private let onOpenReview: () -> Void
    private let onOpenComposer: () -> Void
    private let onOpenComposerPrefilled: (String) -> Void

    @State private var returnPacketPresentation: ReturnPacketPresentation?

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    private struct ReturnPacketPresentation: Identifiable {
        let receipt: ProofReceipt
        var id: String { receipt.runId }
    }

    /// Mock shell always shows the banner for UI tests; live shell only when a
    /// pending approval is wired through `CursorShellLiveBridge`.
    private var showsApprovalBanner: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LANCER_UITEST_RESEED"] == "1" {
            return true
        }
        #endif
        guard let liveBridge else { return true }
        return liveBridge.pendingApprovalID != nil
    }

    private var displayedArtifacts: [ChatArtifact] {
        if let liveBridge, !liveBridge.activeThreadArtifacts.isEmpty {
            return liveBridge.activeThreadArtifacts
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["LANCER_CURSOR_MOCK_RECEIPT"] == "1" {
            return [Self.mockReceiptArtifact]
        }
        #endif
        return []
    }

    public init(
        missionTitle: String = "Fix onboarding pairing flow",
        onBack: @escaping () -> Void = {},
        onViewPR: @escaping () -> Void = {},
        onOpenReview: @escaping () -> Void = {},
        onOpenComposer: @escaping () -> Void = {},
        onOpenComposerPrefilled: @escaping (String) -> Void = { _ in }
    ) {
        self.missionTitle = missionTitle
        self.onBack = onBack
        self.onViewPR = onViewPR
        self.onOpenReview = onOpenReview
        self.onOpenComposer = onOpenComposer
        self.onOpenComposerPrefilled = onOpenComposerPrefilled
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    userPromptBubble
                    narration
                    artifactCards
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 12)
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
        // Pushed via `.navigationDestination` inside a `NavigationStack` whose
        // ancestor hides the nav bar — that hidden state doesn't reliably
        // propagate onto pushed destinations, so the system re-adds its own
        // back chevron alongside this view's own custom one. Hide both the
        // bar and the system back button explicitly, here, so this view is
        // correct regardless of what its host `NavigationStack` does.
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
    }

    // MARK: Needs-approval banner

    /// Governed-approval quick actions above the sticky action rail. Live shell
    /// gates on `pendingApprovalID`; mock shell always shows for UI tests.
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

    // MARK: Composer

    private var composer: some View {
        CursorBottomComposer(
            placeholder: "Follow up...",
            style: .followUp,
            onTap: onOpenComposer
        )
    }

    // MARK: Header

    private var header: some View {
        CursorHeaderBar(
            leading: AnyView(
                CursorIconButton(systemImageName: "chevron.left", action: onBack)
            ),
            trailing: [
                CursorIconButton(systemImageName: "ellipsis", action: {})
            ]
        )
        .overlay(alignment: .center) {
            HStack(spacing: 6) {
                Text(missionTitle)
                    .font(CursorType.sheetTitle)
                    .foregroundColor(CursorColors.light.primaryText)
                    .lineLimit(1)
                Image(systemName: "display")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CursorColors.light.secondaryText)
            }
            .padding(.top, CursorMetrics.headerTopPadding)
        }
    }

    // MARK: User prompt bubble

    /// The real dispatched prompt if this is the thread just sent from the
    /// composer; falls back to the mission title (the conversation's stored
    /// title, itself derived server-side from the original prompt) when
    /// opening an older thread from the list/search rather than a fresh send.
    private var displayedPrompt: String {
        let live = liveBridge?.activeThreadPrompt ?? ""
        return live.isEmpty ? missionTitle : live
    }

    private var userPromptBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(displayedPrompt)
                .font(CursorType.bodyText)
                .foregroundColor(CursorColors.light.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(CursorColors.light.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: Narration — the run's real output, not a scripted example

    private var narration: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = liveBridge?.activeThreadError, !error.isEmpty {
                Text(error)
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.light.dangerRed)
            } else if let text = liveBridge?.activeThreadResponse, !text.isEmpty {
                Text(text)
                    .font(CursorType.bodyText)
                    .foregroundColor(CursorColors.light.primaryText)
                    .textSelection(.enabled)
            } else if liveBridge?.activeThreadIsWorking == true {
                logLine("Working…")
            } else if displayedArtifacts.isEmpty {
                logLine("No output recorded for this thread yet.")
            }
        }
    }

    // MARK: Artifacts

    @ViewBuilder
    private var artifactCards: some View {
        ForEach(displayedArtifacts) { artifact in
            artifactView(for: artifact)
        }
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
            .foregroundColor(CursorColors.light.secondaryText)
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
            .foregroundColor(CursorColors.light.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(CursorColors.light.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CursorColors.light.hairline, lineWidth: 0.5)
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
