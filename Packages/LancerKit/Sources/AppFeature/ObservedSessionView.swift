#if os(iOS)
import SwiftUI
import DesignSystem
import SessionFeature
import SecurityKit
import LancerCore

/// Transcript viewer + composer for a session discovered on the host (Claude
/// Code, etc.) but not dispatched by Lancer. Watch-only when `onSendFollowUp`
/// is nil (no composer shown); otherwise the phone can send a follow-up prompt
/// into the EXACT on-disk session (by vendor + sessionId + cwd), resuming it via
/// the daemon's `agent.observedSession.continue` RPC. Fetches the transcript once
/// on appear, then re-polls a few times after a send so the resumed turn's
/// output (written by the vendor CLI to the same on-disk transcript) shows up.
public struct ObservedSessionView: View {
    let sessionId: String
    let title: String
    let hostName: String
    /// Vendor id ("claudeCode" | "codex" | "opencode" | "kimi") and working
    /// directory of the observed session — required to target the exact session
    /// on a follow-up send. Empty when the caller hasn't wired them through yet,
    /// in which case the composer stays hidden even if `onSendFollowUp` is set.
    let vendor: String
    let cwd: String
    /// Fetches transcript turns starting at `sinceLine`. AppRoot resolves this to
    /// the connected SSH slot's `DaemonChannel.fetchTranscript` or the relay
    /// bridge's `relayFetchTranscript`.
    let loadTranscript: (_ sinceLine: Int) async -> (messages: [SessionMessage], nextLine: Int, resetRequired: Bool)
    /// Sends a follow-up prompt into this exact session. AppRoot resolves this to
    /// the connected SSH slot's `DaemonChannel.continueObservedSession` (or an
    /// equivalent relay call). nil disables the composer — the view stays
    /// read-only, matching the original Phase 1 behavior.
    let onSendFollowUp: ((_ prompt: String) async -> DispatchResult)?
    let onBack: () -> Void

    @State private var messages: [SessionMessage] = []
    @State private var loaded = false
    @State private var unlocked = false
    @State private var nextLine = 0
    @State private var followUpText = ""
    @State private var sendNotice: String?

    @Environment(\.lancerTokens) private var t

    public init(
        sessionId: String,
        title: String,
        hostName: String,
        vendor: String = "",
        cwd: String = "",
        loadTranscript: @escaping (_ sinceLine: Int) async -> (messages: [SessionMessage], nextLine: Int, resetRequired: Bool),
        onSendFollowUp: ((_ prompt: String) async -> DispatchResult)? = nil,
        onBack: @escaping () -> Void
    ) {
        self.sessionId = sessionId
        self.title = title
        self.hostName = hostName
        self.vendor = vendor
        self.cwd = cwd
        self.loadTranscript = loadTranscript
        self.onSendFollowUp = onSendFollowUp
        self.onBack = onBack
    }

    public var body: some View {
        VStack(spacing: 0) {
            DarkTranscriptHeader(
                title: title,
                subtitle: "Watching · \(hostName)",
                isLive: false,
                onBack: { Haptics.selection(); onBack() },
                onWorkspace: { Haptics.selection(); onBack() },
                shareText: { transcriptText() }
            )
            .overlay(alignment: .topTrailing) {
                watchingBadge.padding(.top, 8).padding(.trailing, 64)
            }
            content
            Spacer(minLength: 0)
        }
        // Fill the screen top-anchored. Without this the header + loading/empty
        // content sized to their intrinsic height and the container centered the
        // whole stack — leaving a large blank top and the header floating mid-screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(t.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { composer }
        .task(id: sessionId) { await loadAndUnlock() }
    }

    @ViewBuilder
    private var content: some View {
        if !unlocked {
            lockedState
        } else if !loaded {
            // Fetch in flight. Without this the unlocked-but-not-loaded state fell
            // through to an empty scroll view — a confusing permanent blank if the
            // transcript reply was slow or never arrived.
            loadingState
        } else if messages.isEmpty {
            emptyState
        } else {
            ConversationScrollView(bottomID: "observed-bottom", scrollKey: messages.count) {
                ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                    row(for: message)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading transcript…")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var watchingBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "eye").font(.system(size: 10, weight: .semibold))
            Text("Watching").font(.dsMonoPt(11, weight: .medium))
        }
        .foregroundStyle(t.text3)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(t.surface2, in: Capsule())
    }

    @ViewBuilder
    private func row(for message: SessionMessage) -> some View {
        switch message.role {
        case .user:
            DarkUserBubble(message.text)
        case .assistant:
            DarkAssistantBubble(message.text)
        case .toolCall, .toolResult:
            DarkTerminalBlockCard(
                host: hostName,
                command: message.role == .toolCall ? message.toolName : nil,
                output: message.text,
                state: .done,
                isShellSession: message.toolName.map(DarkTerminalBlockCard.isShellToolName) ?? false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        case .system, .unknown:
            Text(message.text)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            DSIconView(.sparkles, size: 28, color: t.text4)
            Text("No transcript recorded for this session yet.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var lockedState: some View {
        VStack(spacing: 8) {
            DSIconView(.shield, size: 28, color: t.text4)
            Text("Authenticate to view this transcript.")
                .font(.dsSansPt(14))
                .foregroundStyle(t.text4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func transcriptText() -> String {
        var out = "# \(title)\n\(hostName)\n\n"
        for message in messages {
            out += "## \(message.role.rawValue)\n\(message.text)\n\n"
        }
        return out
    }

    // Viewing an observed transcript needs no write capability, and a follow-up
    // send is gated the same way a normal dispatch is (daemon policy + budget on
    // the resumed run, not a per-open phone prompt) — so a per-open Face ID
    // prompt here is friction without a matching threat (app-launch app-lock
    // already gates entry to the app when the user enables it). Load directly.
    private func loadAndUnlock() async {
        unlocked = true
        let result = await loadTranscript(0)
        messages = result.messages
        nextLine = result.nextLine
        loaded = true
    }

    private var canSend: Bool {
        onSendFollowUp != nil && !vendor.isEmpty && !cwd.isEmpty
    }

    @ViewBuilder
    private var composer: some View {
        if canSend {
            VStack(alignment: .leading, spacing: 6) {
                if let sendNotice {
                    Text(sendNotice)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.warn)
                        .padding(.horizontal, 18)
                }
                RunFollowUpBar(
                    text: $followUpText,
                    isErrorState: false,
                    onSend: { prompt in Task { await sendFollowUp(prompt) } }
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .background(t.bg.opacity(0.96).ignoresSafeArea(edges: .bottom))
        }
    }

    private func sendFollowUp(_ prompt: String) async {
        guard let onSendFollowUp, canSend else { return }
        sendNotice = nil
        messages.append(SessionMessage(role: .user, text: prompt))
        let result = await onSendFollowUp(prompt)
        switch result.status {
        case "started":
            await pollForReply()
        case "needsApproval":
            sendNotice = "Waiting for approval on \(hostName)."
        case "denied":
            sendNotice = "Denied by policy on \(hostName)" + (result.rule.map { " (\($0))" } ?? "") + "."
        case "budgetExceeded":
            sendNotice = "Daily budget reached on \(hostName)."
        default:
            sendNotice = result.message ?? "Couldn't reach \(hostName)."
        }
    }

    // The resumed vendor CLI writes its reply to the same on-disk transcript
    // loadTranscript already reads (no separate live-output channel is wired to
    // this view), so pick it up by re-polling a few times rather than a single
    // fixed-delay fetch that would race a slow reply.
    private func pollForReply() async {
        for _ in 0..<8 {
            try? await Task.sleep(for: .seconds(2))
            let result = await loadTranscript(nextLine)
            if !result.messages.isEmpty {
                messages.append(contentsOf: result.messages)
                nextLine = result.nextLine
                return
            }
            nextLine = result.resetRequired ? 0 : result.nextLine
        }
    }
}
#endif
