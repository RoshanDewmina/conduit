#if os(iOS)
import SwiftUI
import LancerCore

/// M3: the real, live conversation view — reached only from the New Chat
/// composer's send action (a brand-new conversation flow). This is
/// deliberately separate from `ThreadDetailView` (Section 7's static,
/// owner-approved PR-review-style mockup for browsing sample thread rows) —
/// see the M3 brief's scope boundary. Apple-native `NavigationStack` /
/// `ScrollView` / `TextField` only, no DesignSystem module.
public struct LiveThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellLiveBridge.self) private var bridge

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
