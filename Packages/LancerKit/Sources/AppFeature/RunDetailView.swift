#if os(iOS)
import SwiftUI
import DesignSystem
import LancerCore
import SSHTransport

// MARK: - DaemonChannel conforms to RunControlling
// DaemonChannel already exposes pauseRun/resumeRun/stopRun/setRunBudget (the run-control
// RPC calls), so the conformance is structural — the bridge IS the production channel.
extension DaemonChannel: RunControlling {}

// MARK: - Run Detail
// Two-way control surface for a dispatched bridge run: live status + stop / pause-resume /
// set-budget. Mirrors the migration board's `AgentRunDetailScreen`.

public struct RunDetailView: View {
    @State private var store: RunControlStore
    @State private var confirmStop = false
    @State private var showBudgetSheet = false
    @State private var followUpText: String = ""
    @State private var runStartTime = Date()

    private let title: String
    private let subtitle: String
    private let runId: String
    private let runOutputStore: RunOutputStore?
    private let onSendFollowUp: ((String) -> Void)?
    private let pendingApprovalCount: Int
    private let onApprove: (() -> Void)?
    private let onReject: (() -> Void)?
    private let replyStatus: ReplyDeliveryStatus?
    private let onRetryDelivery: (() -> Void)?

    @Environment(\.lancerTokens) private var t

    public init(
        channel: any RunControlling,
        runId: String,
        title: String,
        subtitle: String,
        status: RunControlStatus = .running,
        outputStore: RunOutputStore? = nil,
        onSendFollowUp: ((String) -> Void)? = nil,
        pendingApprovalCount: Int = 0,
        onApprove: (() -> Void)? = nil,
        onReject: (() -> Void)? = nil,
        replyStatus: ReplyDeliveryStatus? = nil,
        onRetryDelivery: (() -> Void)? = nil
    ) {
        _store = State(initialValue: RunControlStore(channel: channel, runId: runId, status: status))
        self.title = title
        self.subtitle = subtitle
        self.runId = runId
        self.runOutputStore = outputStore
        self.onSendFollowUp = onSendFollowUp
        self.pendingApprovalCount = pendingApprovalCount
        self.onApprove = onApprove
        self.onReject = onReject
        self.replyStatus = replyStatus
        self.onRetryDelivery = onRetryDelivery
    }

    // MARK: - Derived state

    private var currentRun: RunOutputStore.Run? {
        runOutputStore?.run(runId)
    }

    private var agentState: AgentState {
        guard let run = currentRun else { return .thinking }
        switch run.status {
        case "running":
            return run.chunks.isEmpty ? .thinking : .streaming
        case "exited":
            return .done
        case "failed":
            return .error
        default:
            return run.chunks.isEmpty ? .thinking : .streaming
        }
    }

    private var dotMatrixState: DotMatrixState {
        switch agentState {
        case .thinking:  return .connecting
        case .streaming: return .working
        case .approval:  return .working
        case .done:      return .done
        case .error:     return .error
        case .offline:   return .idle
        }
    }

    private var hasOutput: Bool {
        (currentRun?.chunks.isEmpty).map { !$0 } ?? false
    }

    // The run is actively producing output: drives the blinking caret. False once
    // the process exits/fails or is stopped, so the caret disappears when done.
    private var isStreaming: Bool {
        store.status == .running && agentState != .done && agentState != .error
    }

    private static let bottomAnchor = "run-output-bottom"

    // The run has finished (exited/failed) per streamed status. Once terminal, the
    // control bar collapses to a single done/failed indicator — no dead Stop/Pause
    // buttons that would error against an already-finished process.
    private var runIsTerminal: Bool {
        currentRun?.isTerminal ?? false
    }

    private var isErrorState: Bool {
        currentRun?.status == "failed" ||
        (store.lastError != nil && store.status != .running)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            PixelBox(state: .offline, size: 64)
            Text("No active run")
                .font(.dsMonoPt(14))
                .foregroundStyle(t.text3)
            Text("Deploy an agent task from the dashboard to get started")
                .font(.dsMonoPt(14))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
            DSButton("Start new run", variant: .primary) {
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var errorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let err = store.lastError {
                    DSTypedErrorCard(
                        error: .other(err),
                        onPrimary: nil,
                        onSecondary: nil
                    )
                } else if currentRun?.status == "failed" {
                    DSTypedErrorCard(
                        error: .runFailed(""),
                        onPrimary: nil,
                        onSecondary: nil
                    )
                }
                if hasOutput, let run = currentRun {
                    outputContent(for: run)
                }
                Color.clear.frame(height: 1).id(Self.bottomAnchor)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            hudStrip
            DSDivider(.strong)
            if currentRun == nil {
                emptyState
            } else if isErrorState {
                errorContent
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if hasOutput, let run = currentRun {
                                outputContent(for: run)
                            } else if currentRun != nil {
                                thinkingPlaceholder
                            }
                            // Bottom anchor: the view auto-scrolls here as output streams
                            // in so the freshest tokens stay visible (terminal-tail feel).
                            Color.clear.frame(height: 1).id(Self.bottomAnchor)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                    }
                    .onChange(of: currentRun?.chunks.count ?? 0) { _, _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("run")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let approve = onApprove, let reject = onReject, pendingApprovalCount > 0 {
                    DSApprovalBanner(count: pendingApprovalCount, onApprove: approve, onReject: reject)
                }
                if let status = replyStatus, pendingApprovalCount == 0 {
                    replyStatusBanner(status)
                }
                if onSendFollowUp != nil {
                    followUpBar
                }
                controlBar
            }
        }
        .confirmationDialog("Stop this run?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop run", role: .destructive) {
                Haptics.warning()
                Task { await store.stop() }
            }
            Button("Keep running", role: .cancel) {}
        } message: {
            Text("The agent process is terminated. This can't be undone.")
        }
        .sheet(isPresented: $showBudgetSheet) {
            BudgetSheet { usd in Task { await store.setBudget(usd) } }
                .presentationDetents([.height(260)])
        }
    }

    // MARK: - HUD Strip

    private var hudStrip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                PixelBox(state: agentState, size: 12, subdivisions: 2)
                Text(agentState.label)
                    .font(.dsMonoPt(12, weight: .semibold))
                    .foregroundStyle(t.hudText)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let e = ctx.date.timeIntervalSince(runStartTime)
                    let m = Int(e) / 60
                    let s = Int(e) % 60
                    Text("\(m)m \(String(format: "%02d", s))s")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.hudText.opacity(0.7))
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            DotMatrixView(state: dotMatrixState, cols: 10, rows: 3, cell: 5, dot: 2.5)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.hudBg)
        .overlay(Rectangle().fill(t.hudBorder).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Thinking Placeholder

    private var thinkingPlaceholder: some View {
        VStack(spacing: 16) {
            PixelBox(state: .thinking, size: 16, subdivisions: 2)
            Text("Waiting for first output…")
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Output Content

    private func outputContent(for run: RunOutputStore.Run) -> some View {
        // One flowing mono block, not one Text per chunk: token-level deltas (which
        // arrive without trailing newlines) must concatenate inline, exactly like a
        // terminal, rather than each landing on its own line.
        StreamingOutputText(text: run.text, isStreaming: isStreaming)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeIn(duration: 0.1), value: run.chunks.count)
    }

    // Destructive-left ordering per LANCER_UI_CONSISTENCY_RULES R3.3; equal-width row.
    private var controlBar: some View {
        RunControlBar(
            store: store,
            isTerminal: runIsTerminal,
            failed: currentRun?.status == "failed",
            exitCode: currentRun?.exitCode,
            onStop: { confirmStop = true },
            onShowBudget: { showBudgetSheet = true }
        )
        .padding(.bottom, 12)
    }

    // MARK: - Reply Status Banner

    @ViewBuilder
    private func replyStatusBanner(_ status: ReplyDeliveryStatus) -> some View {
        HStack(spacing: 10) {
            switch status {
            case .sending:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Sending decision…")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            case .delivered:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(t.ok)
                Text("Decision sent ✓")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.ok)
            case .failed(let reason):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(t.warn)
                Text("Failed to deliver — \(reason)")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.warn)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let onRetryDelivery {
                    Spacer()
                    DSButton("Retry", variant: .quiet, size: .sm, mono: true, action: onRetryDelivery)
                }
            case .expiredBeforeDelivery:
                Image(systemName: "clock.badge.xmark")
                    .foregroundStyle(t.text3)
                Text("Approval expired before reply was sent")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Follow-up Bar

    private var followUpBar: some View {
        RunFollowUpBar(
            text: $followUpText,
            isErrorState: isErrorState,
            onSend: { onSendFollowUp?($0) }
        )
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .background(.bar)
    }
}

#Preview {
    // Sendable fake so the preview compiles without a live bridge.
    final class PreviewChannel: RunControlling, @unchecked Sendable {
        func pauseRun(runId: String) async throws -> Bool { true }
        func resumeRun(runId: String) async throws -> Bool { true }
        func stopRun(runId: String) async throws -> Bool { true }
        func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { true }
        func continueRun(runId: String, prompt: String) async throws -> DispatchResult {
            DispatchResult(runId: "r2", status: "started", decision: "allow", rule: nil, message: nil)
        }
    }
    return NavigationStack {
        RunDetailView(
            channel: PreviewChannel(),
            runId: "r1",
            title: "Claude Code · lancer",
            subtitle: "Dev VPS · claude-sonnet-4.6"
        )
    }
}

#if DEBUG
#Preview("Fixture 6 – Decision delivered") {
    final class PreviewChannel: RunControlling, @unchecked Sendable {
        func pauseRun(runId: String) async throws -> Bool { true }
        func resumeRun(runId: String) async throws -> Bool { true }
        func stopRun(runId: String) async throws -> Bool { true }
        func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { true }
        func continueRun(runId: String, prompt: String) async throws -> DispatchResult {
            DispatchResult(runId: "r2", status: "started", decision: "allow", rule: nil, message: nil)
        }
    }
    return NavigationStack {
        RunDetailView(
            channel: PreviewChannel(),
            runId: "r1",
            title: "Claude Code · lancer",
            subtitle: "Dev VPS · claude-sonnet-4.6",
            replyStatus: .delivered
        )
    }
}

#Preview("Fixture 7 – Delivery failed") {
    final class PreviewChannel: RunControlling, @unchecked Sendable {
        func pauseRun(runId: String) async throws -> Bool { true }
        func resumeRun(runId: String) async throws -> Bool { true }
        func stopRun(runId: String) async throws -> Bool { true }
        func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { true }
        func continueRun(runId: String, prompt: String) async throws -> DispatchResult {
            DispatchResult(runId: "r2", status: "started", decision: "allow", rule: nil, message: nil)
        }
    }
    return NavigationStack {
        RunDetailView(
            channel: PreviewChannel(),
            runId: "r1",
            title: "Claude Code · lancer",
            subtitle: "Dev VPS · claude-sonnet-4.6",
            replyStatus: .failed(reason: "Relay connection lost"),
            onRetryDelivery: { print("retry tapped") }
        )
    }
}
#endif
#endif
