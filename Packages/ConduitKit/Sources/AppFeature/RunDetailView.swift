#if os(iOS)
import SwiftUI
import DesignSystem
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

    @Environment(\.conduitTokens) private var t

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
        onReject: (() -> Void)? = nil
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

    private var spectrumMode: SpectrumMode {
        switch store.status {
        case .stopped, .budgetExceeded:
            return .idle
        case .paused:
            return .idle
        case .running:
            switch agentState {
            case .thinking:  return .loading
            case .streaming: return .working
            case .approval:  return .working
            case .done:      return .idle
            case .error:     return .scan
            case .offline:   return .scan
            }
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
                        error: .other("Run failed"),
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
            SpectrumBar(mode: spectrumMode, height: 6, gap: 1.5)
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
                    approvalBanner(count: pendingApprovalCount, onApprove: approve, onReject: reject)
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

    // Destructive-left ordering per CONDUIT_UI_CONSISTENCY_RULES R3.3; equal-width row.
    @ViewBuilder
    private var controlBar: some View {
        if runIsTerminal {
            finishedBar
        } else {
            liveControlBar
        }
    }

    // Shown once the run has exited/failed: a calm status line, not live controls.
    private var finishedBar: some View {
        let failed = currentRun?.status == "failed"
        return HStack(spacing: 8) {
            Image(systemName: failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(failed ? t.termErr : t.termPrompt)
            Text(failed
                 ? "Run failed\(currentRun?.exitCode.map { " · exit \($0)" } ?? "")"
                 : "Run complete")
                .font(.dsMonoPt(13, weight: .semibold))
                .foregroundStyle(t.text)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
    }

    private var liveControlBar: some View {
        HStack(spacing: 8) {
            DSButton("Stop", systemImage: "stop.fill", variant: .destructive, fullWidth: true) {
                Haptics.warning()
                confirmStop = true
            }
            .disabled(!store.canStop)

            if store.canResume {
                DSButton("Resume", systemImage: "play.fill", variant: .secondary, fullWidth: true) {
                    Haptics.selection()
                    Task { await store.resume() }
                }
            } else {
                DSButton("Pause", systemImage: "pause.fill", variant: .secondary, fullWidth: true) {
                    Haptics.selection()
                    Task { await store.pause() }
                }
                .disabled(!store.canPause)
            }

            DSButton("Budget", systemImage: "gauge.with.dots.needle.50percent", variant: .secondary, fullWidth: true) {
                Haptics.selection()
                showBudgetSheet = true
            }
            .disabled(!store.canSetBudget)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Approval Banner

    private func approvalBanner(count: Int, onApprove: @escaping () -> Void, onReject: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.warn)
            Text(count == 1 ? "1 pending approval" : "\(count) pending approvals")
                .font(.dsMonoPt(12, weight: .semibold))
                .foregroundStyle(t.text2)
            Spacer()
            Button {
                Haptics.selection()
                onReject()
            } label: {
                Text("DENY")
                    .font(.dsMonoPt(11, weight: .semibold))
                    .foregroundStyle(t.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(t.dangerSoft)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button {
                Haptics.medium()
                onApprove()
            } label: {
                Text("APPROVE")
                    .font(.dsMonoPt(11, weight: .semibold))
                    .foregroundStyle(t.accentFg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(t.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(t.warnSoft)
        .overlay(Rectangle().fill(t.warn.opacity(0.25)).frame(height: 1), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: pendingApprovalCount)
    }

    // MARK: - Follow-up Bar

    private var followUpBar: some View {
        let textEmpty = followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            Text("$")
                .font(.dsMonoPt(15))
                .foregroundStyle(t.termPrompt)
                .padding(.leading, 4)
            TextField("follow-up", text: $followUpText, axis: .vertical)
                .font(.dsMonoPt(15))
                .foregroundStyle(t.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(isErrorState)
            if isErrorState {
                DSButton("Reconnect", systemImage: "arrow.clockwise", variant: .primary) {
                    let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSendFollowUp?(text.isEmpty ? "/reconnect" : text)
                    followUpText = ""
                }
            } else {
                Button {
                    let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    onSendFollowUp?(text)
                    followUpText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(textEmpty ? t.text4 : t.accent)
                }
                .disabled(textEmpty)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(t.surf2)
        .clipShape(RoundedRectangle(cornerRadius: t.pill, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.pill, style: .continuous).stroke(t.border, lineWidth: 0.5))
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .background(.bar)
    }
}

// MARK: - Streaming output

/// Renders accumulated run output as a single flowing monospace block with a
/// blinking block caret while the agent is still writing. Concatenating the text
/// (rather than one Text per chunk) lets sub-line token deltas flow inline like a
/// real terminal; the caret is appended via Text composition so it sits right
/// after the last glyph and wraps with the text.
private struct StreamingOutputText: View {
    let text: String
    let isStreaming: Bool

    @Environment(\.conduitTokens) private var t

    var body: some View {
        Group {
            if isStreaming {
                // 0.55s blink phase, no per-frame state — TimelineView re-renders the
                // composed Text and we flip the caret's opacity from the wall clock.
                TimelineView(.periodic(from: .now, by: 0.55)) { ctx in
                    let on = Int(ctx.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
                    composed(caretOpacity: on ? 1 : 0.12)
                }
            } else {
                composed(caretOpacity: 0)
            }
        }
        .textSelection(.enabled)
    }

    private func composed(caretOpacity: Double) -> Text {
        let body = Text(text)
            .font(.dsMonoPt(13))
            .foregroundColor(t.termText)
        let caret = Text(isStreaming ? "▋" : "")
            .font(.dsMonoPt(13))
            .foregroundColor(t.termPrompt.opacity(caretOpacity))
        return Text("\(body)\(caret)")
    }
}

// MARK: - Budget sheet

private struct BudgetSheet: View {
    let onSet: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = "5.00"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set daily budget")
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
            HStack(spacing: 8) {
                Text("$").font(.system(size: 16, design: .monospaced)).foregroundStyle(.secondary)
                TextField("5.00", text: $amount)
                    .font(.system(size: 16, design: .monospaced))
                    .keyboardType(.decimalPad)
            }
            .padding(.horizontal, 13).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 2).stroke(.secondary.opacity(0.3)))

            // Disabled until the input parses, so "Set cap" can't silently dismiss on bad input.
            DSButton("Set cap", variant: .primary, fullWidth: true) {
                guard let usd = Double(amount) else { return }
                Haptics.success()
                onSet(usd)
                dismiss()
            }
            .disabled(Double(amount) == nil)
        }
        .padding(18)
    }
}

#Preview {
    // Sendable fake so the preview compiles without a live bridge.
    final class PreviewChannel: RunControlling, @unchecked Sendable {
        func pauseRun(runId: String) async throws -> Bool { true }
        func resumeRun(runId: String) async throws -> Bool { true }
        func stopRun(runId: String) async throws -> Bool { true }
        func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { true }
    }
    return NavigationStack {
        RunDetailView(
            channel: PreviewChannel(),
            runId: "r1",
            title: "Claude Code · conduit",
            subtitle: "Dev VPS · claude-sonnet-4.6"
        )
    }
}
#endif
