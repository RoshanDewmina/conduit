#if os(iOS)
import SwiftUI
import LancerCore

/// M3: the real, live conversation view — reached only from the New Chat
/// composer's send action (a brand-new conversation flow). This is
/// deliberately separate from `ThreadDetailView` (Section 7's static,
/// owner-approved PR-review-style mockup for browsing sample thread rows) —
/// see the M3 brief's scope boundary. Apple-native `NavigationStack` /
/// `ScrollView` / `TextField` only, no DesignSystem module.
///
/// M4: also renders a pending-approval card (see `approvalCard`) — a fully
/// separate, orthogonal piece of UI state from `SendState` below. A pending
/// approval can appear at any point regardless of whether the current turn
/// is still working or already completed.
public struct LiveThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellLiveBridge.self) private var bridge
    @Environment(RelayApprovalIngest.self) private var approvalIngest

    let prompt: String
    let cwd: String

    @State private var hasSentInitialPrompt = false
    @State private var followUpText: String = ""
    @FocusState private var isFollowUpFocused: Bool

    public init(prompt: String, cwd: String) {
        self.prompt = prompt
        self.cwd = cwd
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        userBubble(prompt)

                        replyState
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }

                if let machineID = bridge.activeMachineID, let pendingApproval {
                    approvalCard(pendingApproval, machineID: machineID)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                Divider()
                followUpBar
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            guard !hasSentInitialPrompt else { return }
            hasSentInitialPrompt = true
            await bridge.send(prompt: prompt, cwd: cwd)
        }
    }

    // MARK: - Reply state (Orca rule: working indicator and visible reply text
    // are mutually exclusive on screen)

    @ViewBuilder
    private var replyState: some View {
        switch bridge.sendState {
        case .idle:
            EmptyView()
        case .working:
            workingIndicator
        case .completed(let turn):
            if turn.status == .failed {
                errorState(turn.errorMessage ?? "Run failed")
            } else {
                Text(turn.assistantText.isEmpty ? "(no reply text)" : turn.assistantText)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
            }
        case .failed(let message):
            errorState(message)
        }
    }

    private var workingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Working…")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Couldn't get a reply")
                    .font(.system(size: 15, weight: .semibold))
            }
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await bridge.send(prompt: prompt, cwd: cwd) }
            }
            .font(.system(size: 14, weight: .medium))
        }
    }

    // MARK: - Pending approval card (M4)

    /// The most recent pending approval that arrived from the same paired
    /// machine this thread is talking to — see `RelayApprovalIngest`'s doc
    /// comment for why this is machine-scoped, not strictly run-scoped.
    private var pendingApproval: Approval? {
        guard let machineID = bridge.activeMachineID,
              let approval = approvalIngest.latestPendingApproval[machineID],
              approval.isPending
        else { return nil }
        return approval
    }

    private func approvalCard(_ approval: Approval, machineID: RelayMachineID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.blue)
                Text(approval.kind.rawValue.capitalized)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                riskLabel(approval.risk)
            }
            Text(approval.command ?? approval.patch ?? "(no detail)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(6)
            HStack(spacing: 12) {
                Button("Deny", role: .destructive) {
                    Task { await approvalIngest.decide(approval, decision: .rejected, machineID: machineID) }
                }
                .buttonStyle(.bordered)

                Button("Approve") {
                    Task { await approvalIngest.decide(approval, decision: .approved, machineID: machineID) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func riskLabel(_ risk: Approval.Risk) -> some View {
        let (text, color): (String, Color) = {
            switch risk {
            case .low: return ("Low", .secondary)
            case .medium: return ("Medium", .secondary)
            case .high: return ("High", .orange)
            case .critical: return ("Critical", .red)
            }
        }()
        return Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    // MARK: - Follow-up composer (plain field, not the ornate composer sheet)

    private var followUpBar: some View {
        HStack(spacing: 10) {
            TextField("Reply…", text: $followUpText)
                .textFieldStyle(.roundedBorder)
                .focused($isFollowUpFocused)
                .disabled(bridge.sendState == .working)

            Button {
                sendFollowUp()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
            }
            .disabled(
                followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || bridge.sendState == .working
                    || bridge.activeConversationID == nil
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sendFollowUp() {
        let text = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let conversationID = bridge.activeConversationID else { return }
        followUpText = ""
        isFollowUpFocused = false
        Task { await bridge.sendFollowUp(prompt: text, conversationID: conversationID, cwd: cwd) }
    }
}
#endif
